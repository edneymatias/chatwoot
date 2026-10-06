# frozen_string_literal: true

# rubocop:disable Rails/Output, Rails/Exit, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength

# script/tag_contacts_from_csv.rb
#
# Aplica etiqueta e/ou atributo personalizado a contatos a partir de um CSV, e (opcionalmente)
# cria os contatos que não existem. Documentação completa: rode com --help (ou HELP=true).

require 'csv'
require 'fileutils'
require 'optparse'

HELP_TEXT = <<~HELP
  tag_contacts_from_csv.rb - aplica etiqueta e/ou atributo personalizado a contatos a partir de um CSV,
  e opcionalmente cria os contatos que ainda não existem

  COMO EXECUTAR
    Dentro do container (na raiz do app, onde existe a pasta script/):
      bundle exec rails runner script/tag_contacts_from_csv.rb --csv tmp/visitas.csv [opções]

    A partir do host:
      docker compose exec rails bundle exec rails runner script/tag_contacts_from_csv.rb --csv tmp/visitas.csv [opções]

  OPÇÕES (cada uma tem uma variável de ambiente equivalente)
    --csv PATH            CSV_PATH       (obrigatória) Caminho do CSV, relativo à raiz do app ou absoluto.
                                         Precisa existir dentro do container (ex.: tmp/visitas.csv).
    --mode MODE           MODE           O que aplicar em cada contato encontrado/criado:
                                           label      (padrão) só a etiqueta
                                           attribute  só o atributo personalizado
                                           both       etiqueta e atributo na mesma execução
    --label NAME          LABEL          Nome da etiqueta, gravado em minúsculas. Padrão: cliente. Usada em
                                         mode label/both. Se não existir na conta, é criada (cor #1f93ff).
    --attribute-key KEY   ATTRIBUTE_KEY  Chave do atributo personalizado (ex.: ultima_visita).
                                         Obrigatória em mode attribute/both.
    --account-id ID       ACCOUNT_ID     Restringe a uma conta. Se omitida, processa TODAS as contas: o mesmo
                                         telefone em várias contas altera todos os contatos. Em instalação
                                         multi-conta, sempre informe. Obrigatória com --create-missing.
    --create-missing      CREATE_MISSING=true
                                         Cria um contato para cada telefone que não existe na conta. O nome vem
                                         da coluna "nome" (obrigatória nesse caso). Exige --account-id.
    --inbox-id ID         INBOX_ID       Vincula os contatos CRIADOS a esta caixa de entrada (só com
                                         --create-missing). Precisa ser da conta e de canal WhatsApp, Twilio
                                         SMS/WhatsApp, SMS ou API. Contatos que já existiam não são vinculados.
    --dry-run             DRY_RUN=true   Simula e mostra o resumo, sem gravar nada. Rode sempre antes da
                                         execução real. (--no-dry-run desfaz DRY_RUN=true do ambiente.)
    -h, --help            HELP=true      Mostra esta ajuda.

    Precedência: flag > variável de ambiente > padrão.

  VARIÁVEIS DE AMBIENTE (alternativa às flags)
    Dentro do container:
      CSV_PATH=tmp/visitas.csv MODE=both ATTRIBUTE_KEY=ultima_visita bundle exec rails runner script/tag_contacts_from_csv.rb

    A partir do host, as variáveis precisam ir com -e (as do host não chegam ao container):
      docker compose exec -e CSV_PATH=tmp/visitas.csv -e MODE=both -e ATTRIBUTE_KEY=ultima_visita \\
        rails bundle exec rails runner script/tag_contacts_from_csv.rb

  FORMATO DO CSV (um único arquivo serve para todos os modos)
    Cabeçalho OBRIGATÓRIO, com nomes fixos (maiúsculas/minúsculas e espaços nas pontas são ignorados).
    A ordem das colunas é livre e colunas extras são ignoradas. Separador ';' ou ',' (detectado no
    cabeçalho). Codificação UTF-8 (BOM aceito).

      telefone;nome;data
      (41) 99999-3501;MARIA DA SILVA;13/03/2026
      4199993502;joão souza;2026-03-13

    telefone  sempre obrigatória. Qualquer formato SEM DDI (o 55 é assumido): 10 ou 11 dígitos, com
              parênteses/traços/espaços. Também aceita já com 55 (12 ou 13 dígitos). Celular antigo de 8
              dígitos recebe o nono dígito. Gravado como +55DD9NNNNNNNN.
    nome      obrigatória com --create-missing, e só é usada para criar contatos novos (o nome de um contato
              existente nunca é alterado). Normalizado para "Primeira Maiúscula" (partículas da/de/do/dos/e
              ficam minúsculas). Nenhum contato é criado sem nome.
    data      obrigatória em mode attribute/both: uma data (Date.parse), gravada como AAAA-MM-DD.
              Em mode label pode estar em branco ou ausente.

    Se o layout estiver inválido (coluna obrigatória ausente, nome de coluna repetido, arquivo vazio ou
    fora de UTF-8), nada é processado: o script mostra o problema e encerra com erro.

  EXEMPLOS
    # Simulação: etiqueta + última visita na conta 2, criando quem não existe e vinculando à inbox 5
    bundle exec rails runner script/tag_contacts_from_csv.rb \\
      --csv tmp/visitas.csv --mode both --label cliente --attribute-key ultima_visita \\
      --account-id 2 --create-missing --inbox-id 5 --dry-run

    # Valendo: o mesmo comando sem --dry-run

    # Só etiqueta em contatos que já existem (CSV só com a coluna telefone)
    bundle exec rails runner script/tag_contacts_from_csv.rb --csv tmp/telefones.csv --label cliente --account-id 2

  COMPORTAMENTO
    - Telefone: busca exata (phone_number IN ...) nas variantes com/sem +, com/sem 55 e com/sem nono dígito.
    - Duplicatas: antes de processar, linhas com o mesmo telefone (após normalizar) são reduzidas a uma;
      a última linha vence. As descartadas vão para linhas_duplicadas.csv.
    - Idempotente: contato que já tem a etiqueta (e o mesmo valor do atributo) é contado como
      "já estava correto" e não é alterado.
    - O atributo SOBRESCREVE o valor existente da chave quando for diferente (mesmo que a data
      anterior seja mais recente). Outros atributos do contato são preservados. Sem backup.
    - Contato novo: criado com nome, telefone, etiqueta e atributo em uma única gravação (e vínculo
      com a inbox, se informada), numa transação por linha; se falhar, nada da linha é gravado.
    - Se a inbox já tiver um vínculo com o mesmo identificador (source_id) de outro contato, o vínculo
      antigo é renomeado (comportamento padrão do ContactInboxBuilder).
    - EVENTOS SILENCIADOS: durante o script, contatos criados/atualizados NÃO disparam eventos
      (webhooks, integrações, atualização ao vivo do dashboard). Agentes só veem as mudanças
      ao recarregar a tela.
    - O atributo é gravado mesmo sem definição na conta; para aparecer na interface, crie um
      atributo personalizado de contato com a mesma chave.

  SAÍDA
    Progresso a cada 50 linhas, resumo geral e por conta. Relatórios gravados em
    tmp/tag_contacts_<timestamp>/ (raiz do app; somem com o container se tmp/ não for volume).
    Têm as colunas telefone;nome;data;linha;motivo (reimportáveis, pois colunas extras são ignoradas);
    só são criados os que tiverem conteúdo:
      telefones_nao_encontrados.csv   (sem --create-missing)
      linhas_invalidas.csv
      linhas_duplicadas.csv
      contatos_criados.csv            (com --dry-run: contatos_a_criar.csv; coluna final = id do contato)
      erros.csv

  ANTES DE RODAR EM PRODUÇÃO
    Confirme o ambiente (echo $RAILS_ENV), use --account-id e --dry-run, e compare o resumo
    do dry run com o da execução real.
HELP

ALLOWED_INBOX_CHANNELS = %w[Channel::Whatsapp Channel::TwilioSms Channel::Sms Channel::Api].freeze
NAME_PARTICLES = %w[da das de do dos e di du].freeze
REPORT_HEADERS = %w[telefone nome data linha motivo].freeze
KNOWN_COLUMNS = %w[telefone nome data].freeze

ImportRow = Struct.new(:line, :phone_raw, :name_raw, :date_raw, :phone, :value, :name, keyword_init: true)

def fail_with(*messages)
  messages.each { |message| puts message }
  exit 1
end

def generate_phone_variants(raw)
  clean = raw.gsub(/\D/, '')
  return [] if clean.blank?

  variants = Set.new
  variants << clean
  variants << "+#{clean}"

  # Se tem 55 (Brasil)
  if clean.start_with?('55')
    sem_55 = clean[2..]
    variants << sem_55
    variants << "+#{sem_55}"

    # Se tem 11 dígitos (DDD + 9 dígitos) ex: 55 83 99999-9999 -> DDD: 83, número: 999999999
    if sem_55.length == 11 && sem_55[2] == '9'
      sem_9 = "#{sem_55[0..1]}#{sem_55[3..]}"
      variants << sem_9
      variants << "+#{sem_9}"
      variants << "55#{sem_9}"
      variants << "+55#{sem_9}"
    # Se tem 10 dígitos (DDD + 8 dígitos) ex: 55 83 9999-9999 -> DDD: 83, número: 99999999
    elsif sem_55.length == 10
      com_9 = "#{sem_55[0..1]}9#{sem_55[2..]}"
      variants << com_9
      variants << "+#{com_9}"
      variants << "55#{com_9}"
      variants << "+55#{com_9}"
    end
  elsif clean.length == 11 && clean[2] == '9'
    # Sem 55, mas com DDD + 9 dígitos
    sem_9 = "#{clean[0..1]}#{clean[3..]}"
    variants << sem_9
    variants << "+#{sem_9}"
    variants << "55#{clean}"
    variants << "+55#{clean}"
    variants << "55#{sem_9}"
    variants << "+55#{sem_9}"
  elsif clean.length == 10
    # Sem 55, mas com DDD + 8 dígitos
    com_9 = "#{clean[0..1]}9#{clean[2..]}"
    variants << com_9
    variants << "+#{com_9}"
    variants << "55#{clean}"
    variants << "+55#{clean}"
    variants << "55#{com_9}"
    variants << "+55#{com_9}"
  end

  variants.to_a
end

# Forma canônica brasileira, só dígitos e com 55 (ex.: 5541999993501), ou nil se o telefone for inválido.
# Reaproveita o normalizador do WhatsApp: celular legado de 8 dígitos ganha o nono dígito.
def canonical_phone(raw)
  digits = raw.to_s.gsub(/\D/, '')
  digits = "55#{digits}" if [10, 11].include?(digits.length)
  return nil unless digits.start_with?('55') && [12, 13].include?(digits.length)

  Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(digits)
end

# "MARIA DA SILVA" / "maria da Silva" -> "Maria da Silva"; "d'avila" -> "D'Avila"; "ana-maria" -> "Ana-Maria"
def normalize_name(raw)
  raw.to_s.squish.downcase.split.each_with_index.map do |word, idx|
    next word if idx.positive? && NAME_PARTICLES.include?(word)

    word.split(/([-'’])/).map(&:capitalize).join
  end.join(' ')
end

def parse_date(raw)
  Date.parse(raw).strftime('%Y-%m-%d')
rescue ArgumentError, TypeError
  nil
end

# Retorna [row, motivo_de_invalidez]; motivo é nil quando a linha é válida.
def parse_row(csv_row, line, need_value)
  row = ImportRow.new(line: line, phone_raw: csv_row['telefone'].to_s.strip,
                      name_raw: csv_row['nome'].to_s.strip, date_raw: csv_row['data'].to_s.strip)
  digits = canonical_phone(row.phone_raw)
  return [row, 'telefone ausente ou inválido'] if digits.nil?

  row.phone = "+#{digits}"
  if need_value
    row.value = parse_date(row.date_raw)
    return [row, 'data ausente ou inválida'] if row.value.nil?
  end
  [row, nil]
end

def report_fields(row)
  [row.phone_raw, row.name_raw, row.date_raw, row.line]
end

def ensure_label(account, label_name)
  account.labels.find_or_create_by!(title: label_name) do |l|
    l.color = '#1f93ff'
  end
end

def apply_contact_change(contact, label_name, attribute_key, attribute_value)
  if label_name
    ensure_label(contact.account, label_name)
    contact.label_list.add(label_name)
  end
  contact.custom_attributes = contact.custom_attributes.merge(attribute_key => attribute_value) if attribute_key
  contact.save!
end

# Contato, etiqueta, atributo e vínculo com a inbox numa única transação: falhou, nada da linha fica gravado.
def create_contact(account, row, label_name, attribute_key, inbox)
  ActiveRecord::Base.transaction do
    contact = account.contacts.new(name: row.name, phone_number: row.phone)
    contact.custom_attributes = { attribute_key => row.value } if attribute_key
    if label_name
      ensure_label(account, label_name)
      contact.label_list.add(label_name)
    end
    contact.save!
    ContactInboxBuilder.new(contact: contact, inbox: inbox).perform if inbox
    contact
  end
end

def write_report(dir, filename, headers, rows)
  return if rows.empty?

  FileUtils.mkdir_p(dir)
  path = File.join(dir, filename)
  File.write(path, CSV.generate(col_sep: ';') { |csv| [headers, *rows].each { |fields| csv << fields } })
  puts "📄 #{path}"
end

if ENV['HELP'] == 'true'
  puts HELP_TEXT
  exit 0
end

options = {
  csv: ENV['CSV_PATH'].presence,
  mode: ENV.fetch('MODE', nil),
  label: ENV.fetch('LABEL', nil),
  attribute_key: ENV.fetch('ATTRIBUTE_KEY', nil),
  account_id: ENV['ACCOUNT_ID']&.to_i,
  create_missing: ENV['CREATE_MISSING'] == 'true',
  inbox_id: ENV['INBOX_ID']&.to_i,
  dry_run: ENV['DRY_RUN'] == 'true'
}

begin
  OptionParser.new do |parser|
    parser.on('--csv PATH') { |value| options[:csv] = value }
    parser.on('--mode MODE') { |value| options[:mode] = value }
    parser.on('--label NAME') { |value| options[:label] = value }
    parser.on('--attribute-key KEY') { |value| options[:attribute_key] = value }
    parser.on('--account-id ID', Integer) { |value| options[:account_id] = value }
    parser.on('--[no-]create-missing') { |value| options[:create_missing] = value }
    parser.on('--inbox-id ID', Integer) { |value| options[:inbox_id] = value }
    parser.on('--[no-]dry-run') { |value| options[:dry_run] = value }
    parser.on('-h', '--help') do
      puts HELP_TEXT
      exit 0
    end
  end.parse!(ARGV)
rescue OptionParser::ParseError => e
  fail_with "❌ #{e.message}. Ajuda: --help"
end

fail_with "❌ Argumentos inesperados: #{ARGV.join(' ')}. Use flags (--csv, --mode, ...). Ajuda: --help" if ARGV.any?

csv_path = options[:csv]
if csv_path.blank? || !File.exist?(csv_path)
  fail_with "❌ CSV não encontrado: #{csv_path.presence || '(--csv/CSV_PATH não informado)'}",
            '   Informe --csv com um caminho existente dentro do container. Ajuda: --help'
end

mode = (options[:mode] || 'label').downcase.strip
fail_with "❌ Modo inválido: '#{mode}'. Use 'label', 'attribute' ou 'both'. Ajuda: --help" unless %w[label attribute both].include?(mode)

label_name = (options[:label] || 'cliente').downcase.strip if %w[label both].include?(mode)
attribute_key = options[:attribute_key]&.strip if %w[attribute both].include?(mode)
if %w[attribute both].include?(mode) && attribute_key.blank?
  fail_with "❌ --attribute-key (ATTRIBUTE_KEY) é obrigatório quando o modo é #{mode}. Ajuda: --help"
end

target_account_id = options[:account_id]
create_missing = options[:create_missing]
dry_run = options[:dry_run]

target_account = nil
inbox = nil
if create_missing
  fail_with '❌ --create-missing exige --account-id (ACCOUNT_ID). Ajuda: --help' unless target_account_id

  target_account = Account.find_by(id: target_account_id)
  fail_with "❌ Conta #{target_account_id} não encontrada." unless target_account

  if options[:inbox_id]
    inbox = target_account.inboxes.find_by(id: options[:inbox_id])
    fail_with "❌ Inbox #{options[:inbox_id]} não encontrada na conta #{target_account_id}." unless inbox
    unless ALLOWED_INBOX_CHANNELS.include?(inbox.channel_type)
      fail_with "❌ Inbox #{inbox.id} é do canal #{inbox.channel_type}; use um canal de telefone: #{ALLOWED_INBOX_CHANNELS.join(', ')}."
    end
  end
elsif options[:inbox_id]
  fail_with '❌ --inbox-id só pode ser usado com --create-missing. Ajuda: --help'
end

# ---- Validação do layout (nada é processado se falhar) ----
content = File.read(csv_path, encoding: 'bom|utf-8')
fail_with '❌ Layout inválido: o arquivo não está em UTF-8. Salve o CSV como UTF-8 e tente de novo.' unless content.valid_encoding?

header_line = content.lines.find { |l| l.strip.present? }
fail_with '❌ Layout inválido: arquivo vazio.' if header_line.nil?

delimiter = header_line.count(';') >= header_line.count(',') ? ';' : ','
begin
  headers = CSV.parse_line(header_line, col_sep: delimiter).map { |h| h.to_s.strip.downcase }
  csv_table = CSV.parse(content, headers: true, col_sep: delimiter, skip_blanks: true, header_converters: ->(h) { h.to_s.strip.downcase })
rescue CSV::MalformedCSVError => e
  fail_with "❌ Layout inválido: CSV malformado (#{e.message})."
end

required_columns = %w[telefone] + (create_missing ? %w[nome] : []) + (attribute_key ? %w[data] : [])
missing_columns = required_columns - headers
repeated_columns = headers.tally.select { |name, count| count > 1 && KNOWN_COLUMNS.include?(name) }.keys
if missing_columns.any? || repeated_columns.any?
  messages = ['❌ Layout inválido. Nada foi processado.']
  messages << "   Colunas obrigatórias ausentes: #{missing_columns.join(', ')}" if missing_columns.any?
  messages << "   Colunas repetidas: #{repeated_columns.join(', ')}" if repeated_columns.any?
  messages << "   Encontradas: #{headers.join(', ')}"
  messages << "   Esperadas neste modo: #{required_columns.join(', ')} (ordem livre). Ajuda: --help"
  fail_with(*messages)
end
fail_with '❌ Layout inválido: o arquivo tem cabeçalho mas nenhuma linha de dados.' if csv_table.empty?

puts '=================================================='
puts '  CHATWOOT - IMPORTAÇÃO EM MASSA PARA CONTATOS'
puts '=================================================='
puts "Arquivo: #{csv_path}"
puts "Modo: #{mode}"
puts "Tag: '#{label_name}'" if label_name
puts "Atributo: '#{attribute_key}'" if attribute_key
puts "Conta: #{target_account_id ? "ID #{target_account_id}" : 'Todas as contas'}"
puts "Criar contatos inexistentes: #{create_missing ? 'SIM' : 'NÃO'}"
puts "Inbox dos contatos criados: #{inbox ? "#{inbox.name} (ID #{inbox.id})" : 'nenhuma'}" if create_missing
puts "Modo Dry Run: #{dry_run ? 'SIM (Apenas simulação)' : 'NÃO (Gravação no banco ativa)'}"
puts '--------------------------------------------------'

stats = {
  total_lines: csv_table.size,
  found_contacts: 0,
  changed: 0,
  unchanged: 0,
  created: 0,
  not_found_lines: 0,
  invalid_lines: 0,
  duplicate_lines: 0,
  error_lines: 0,
  by_account: Hash.new { |h, k| h[k] = { name: '', found: 0, changed: 0, unchanged: 0, created: 0 } }
}

not_found_rows = []
invalid_rows = []
duplicate_rows = []
created_rows = []
error_rows = []

# Validação linha a linha e dedup pelo telefone canônico: a última linha vence.
unique_rows = {}
csv_table.each_with_index do |csv_row, idx|
  row, reason = parse_row(csv_row, idx + 2, attribute_key.present?)

  if reason
    stats[:invalid_lines] += 1
    invalid_rows << (report_fields(row) + [reason])
    next
  end

  if (previous = unique_rows[row.phone])
    stats[:duplicate_lines] += 1
    duplicate_rows << (report_fields(previous) + ["substituída pela linha #{row.line}"])
  end
  unique_rows[row.phone] = row
end

rows_to_process = unique_rows.values
puts "📋 Linhas no arquivo: #{stats[:total_lines]} | inválidas: #{stats[:invalid_lines]} | " \
     "duplicadas descartadas: #{stats[:duplicate_lines]} | a processar: #{rows_to_process.size}"

# Script em massa não notifica ninguém: sem webhooks, integrações nem broadcast ao dashboard.
# Seguro porque `rails runner` é um processo isolado; o servidor e o Sidekiq não são afetados.
Contact.skip_callback(:commit, :after, :dispatch_create_event)
Contact.skip_callback(:commit, :after, :dispatch_update_event)
Contact.skip_callback(:commit, :after, :ip_lookup)

# Base de busca
base_contacts = Contact.all
base_contacts = base_contacts.where(account_id: target_account_id) if target_account_id

rows_to_process.each_with_index do |row, idx|
  matching_contacts = base_contacts.where(phone_number: generate_phone_variants(row.phone)).includes(:account).to_a

  if matching_contacts.any?
    stats[:found_contacts] += matching_contacts.size

    matching_contacts.each do |contact|
      acc_stats = stats[:by_account][contact.account_id]
      acc_stats[:name] = contact.account.name if acc_stats[:name].blank?
      acc_stats[:found] += 1

      label_ok = label_name.nil? || contact.label_list.map(&:downcase).include?(label_name)
      attribute_ok = attribute_key.nil? || contact.custom_attributes[attribute_key] == row.value

      if label_ok && attribute_ok
        stats[:unchanged] += 1
        acc_stats[:unchanged] += 1
      else
        stats[:changed] += 1
        acc_stats[:changed] += 1

        apply_contact_change(contact, label_name, attribute_key, row.value) unless dry_run
      end
    end
  elsif create_missing
    row.name = normalize_name(row.name_raw)

    if row.name.blank?
      stats[:invalid_lines] += 1
      invalid_rows << (report_fields(row) + ['nome ausente (obrigatório para criar o contato)'])
    else
      begin
        contact = dry_run ? nil : create_contact(target_account, row, label_name, attribute_key, inbox)
        acc_stats = stats[:by_account][target_account.id]
        acc_stats[:name] = target_account.name if acc_stats[:name].blank?
        acc_stats[:created] += 1
        stats[:created] += 1
        created_rows << [row.phone, row.name, row.value, row.line, contact&.id]
      rescue StandardError => e
        stats[:error_lines] += 1
        error_rows << (report_fields(row) + ["#{e.class}: #{e.message}"])
      end
    end
  else
    stats[:not_found_lines] += 1
    not_found_rows << (report_fields(row) + ['telefone sem contato na conta'])
  end

  if ((idx + 1) % 50).zero? || (idx + 1) == rows_to_process.size
    print "\r[Progresso] #{idx + 1}/#{rows_to_process.size} linhas analisadas..."
    $stdout.flush
  end
end

puts "\n\n================== RESULTADO =================="
puts "Linhas no arquivo: #{stats[:total_lines]}"
puts "Linhas duplicadas descartadas (a última vence): #{stats[:duplicate_lines]}"
puts "Contatos correspondentes encontrados: #{stats[:found_contacts]}"
puts "Contatos #{dry_run ? 'que seriam alterados' : 'alterados agora'}: #{stats[:changed]}"
puts "Contatos que já estavam corretos: #{stats[:unchanged]}"
puts "Contatos #{dry_run ? 'que seriam criados' : 'criados agora'}: #{stats[:created]}" if create_missing
puts "Telefones sem contato no Chatwoot: #{stats[:not_found_lines]}" unless create_missing
puts "Linhas inválidas (telefone/data/nome/formatação): #{stats[:invalid_lines]}"
puts "Linhas com erro ao criar: #{stats[:error_lines]}" if create_missing
puts '--------------------------------------------------'
puts 'Resumo por Conta:'
stats[:by_account].each do |acc_id, data|
  created = ''
  created = " | #{dry_run ? 'A criar' : 'Criados'}: #{data[:created]}" if create_missing
  puts "  - [#{acc_id}] #{data[:name]}: Encontrados: #{data[:found]} | " \
       "#{dry_run ? 'A alterar' : 'Alterados'}: #{data[:changed]} | Já corretos: #{data[:unchanged]}#{created}"
end
puts '=================================================='

report_dir = Rails.root.join('tmp', "tag_contacts_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}")
write_report(report_dir, 'telefones_nao_encontrados.csv', REPORT_HEADERS, not_found_rows)
write_report(report_dir, 'linhas_invalidas.csv', REPORT_HEADERS, invalid_rows)
write_report(report_dir, 'linhas_duplicadas.csv', REPORT_HEADERS, duplicate_rows)
write_report(report_dir, dry_run ? 'contatos_a_criar.csv' : 'contatos_criados.csv', %w[telefone nome data linha id], created_rows)
write_report(report_dir, 'erros.csv', REPORT_HEADERS, error_rows)

# rubocop:enable Rails/Output, Rails/Exit, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
