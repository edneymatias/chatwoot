# frozen_string_literal: true

# rubocop:disable Rails/Output, Rails/Exit, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength

# script/tag_contacts_from_csv.rb
#
# Uso:
#   docker compose exec rails bundle exec rails runner script/tag_contacts_from_csv.rb
#
# Variáveis de ambiente ou argumentos:
#   CSV_PATH="/caminho/arquivo.csv"
#   MODE="label" (padrão) ou "attribute"
#   LABEL="cliente" (usado quando MODE=label)
#   ATTRIBUTE_KEY="ultima_visita" (obrigatório quando MODE=attribute)
#   ACCOUNT_ID="2" (opcional: se omitido, processa todas as contas onde o contato existir)
#   DRY_RUN="true" (opcional: simula sem gravar no banco)
#
# Formato do CSV:
#   MODE=label:     uma coluna, um telefone por linha
#   MODE=attribute: duas colunas por linha, telefone e valor (separador ',' ou ';')
#                    ex: "4199993501;2026-03-13" grava custom_attributes[ATTRIBUTE_KEY] = "2026-03-13"

require 'csv'

csv_path = ENV['CSV_PATH'] || ARGV[0]
unless csv_path && File.exist?(csv_path)
  candidates = [
    'tmp/pessoa_202608141542.csv',
    '/app/tmp/pessoa_202608141542.csv',
    '/home/matias/Downloads/pessoa_202608141542.csv'
  ]
  csv_path = candidates.find { |c| File.exist?(c) }
end

mode = (ENV['MODE'] || 'label').downcase.strip
unless %w[label attribute].include?(mode)
  puts "❌ MODE inválido: '#{mode}'. Use 'label' ou 'attribute'."
  exit 1
end

label_name = (ENV['LABEL'] || ARGV[1] || 'cliente').downcase.strip
attribute_key = ENV['ATTRIBUTE_KEY']&.strip
if mode == 'attribute' && attribute_key.blank?
  puts '❌ ATTRIBUTE_KEY é obrigatório quando MODE=attribute.'
  exit 1
end

target_account_id = ENV['ACCOUNT_ID']&.to_i
dry_run = ENV['DRY_RUN'] == 'true' || ARGV.include?('--dry-run')

puts '=================================================='
puts '  CHATWOOT - IMPORTAÇÃO EM MASSA PARA CONTATOS'
puts '=================================================='
puts "Arquivo: #{csv_path}"
puts "Modo: #{mode}"
puts(mode == 'label' ? "Tag: '#{label_name}'" : "Atributo: '#{attribute_key}'")
puts "Conta: #{target_account_id ? "ID #{target_account_id}" : 'Todas as contas'}"
puts "Modo Dry Run: #{dry_run ? 'SIM (Apenas simulação)' : 'NÃO (Gravação no banco ativa)'}"
puts '--------------------------------------------------'

if csv_path.blank? || !File.exist?(csv_path)
  puts "❌ Arquivo não encontrado: #{csv_path.presence || '(nenhum CSV_PATH informado e nenhum candidato padrão existe)'}"
  exit 1
end

# Lê todas as linhas ignorando cabeçalho se houver
lines = File.readlines(csv_path).map(&:strip).reject(&:empty?)
lines.shift if lines.first&.match?(/[a-zA-Z]/) # remove cabeçalho se tiver texto

puts "📋 Total de linhas para processar: #{lines.size}"

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

def parse_attribute_line(raw)
  delimiter = raw.include?(';') ? ';' : ','
  columns = CSV.parse_line(raw, col_sep: delimiter)
  phone_raw = columns&.first&.strip
  value_raw = columns&.second&.strip
  return nil if phone_raw.blank? || value_raw.blank?

  { phone: phone_raw, value: Date.parse(value_raw).strftime('%Y-%m-%d') }
rescue ArgumentError, TypeError
  nil
end

def apply_contact_change(contact, mode, label_name, attribute_key, attribute_value)
  if mode == 'label'
    account = contact.account
    account.labels.find_or_create_by!(title: label_name) do |l|
      l.color = '#1f93ff'
    end
    contact.label_list.add(label_name)
  else
    contact.custom_attributes = contact.custom_attributes.merge(attribute_key => attribute_value)
  end
  contact.save!
end

stats = {
  total_lines: lines.size,
  found_contacts: 0,
  changed: 0,
  unchanged: 0,
  not_found_lines: 0,
  invalid_lines: 0,
  by_account: Hash.new { |h, k| h[k] = { name: '', found: 0, changed: 0, unchanged: 0 } }
}

not_found_numbers = []
invalid_rows = []

# Base de busca
base_contacts = Contact.all
base_contacts = base_contacts.where(account_id: target_account_id) if target_account_id

lines.each_with_index do |line, idx|
  phone_raw = line
  attribute_value = nil

  if mode == 'attribute'
    parsed = parse_attribute_line(line)
    if parsed.nil?
      stats[:invalid_lines] += 1
      invalid_rows << line
      phone_raw = nil
    else
      phone_raw = parsed[:phone]
      attribute_value = parsed[:value]
    end
  end

  if phone_raw.present?
    variants = generate_phone_variants(phone_raw)
    matching_contacts = base_contacts.where(phone_number: variants)

    if matching_contacts.empty?
      stats[:not_found_lines] += 1
      not_found_numbers << line
    else
      stats[:found_contacts] += matching_contacts.size

      matching_contacts.each do |contact|
        acc_stats = stats[:by_account][contact.account_id]
        acc_stats[:name] = contact.account.name if acc_stats[:name].blank?
        acc_stats[:found] += 1

        unchanged = if mode == 'label'
                      contact.label_list.map(&:downcase).include?(label_name)
                    else
                      contact.custom_attributes[attribute_key] == attribute_value
                    end

        if unchanged
          stats[:unchanged] += 1
          acc_stats[:unchanged] += 1
        else
          stats[:changed] += 1
          acc_stats[:changed] += 1

          apply_contact_change(contact, mode, label_name, attribute_key, attribute_value) unless dry_run
        end
      end
    end
  end

  if ((idx + 1) % 50).zero? || (idx + 1) == lines.size
    print "\r[Progresso] #{idx + 1}/#{lines.size} linhas analisadas..."
    $stdout.flush
  end
end

puts "\n\n================== RESULTADO =================="
puts "Linhas no arquivo: #{stats[:total_lines]}"
puts "Contatos correspondentes encontrados: #{stats[:found_contacts]}"
if mode == 'label'
  puts "Novos contatos rotulados com '#{label_name}': #{stats[:changed]}"
  puts "Contatos que já tinham a tag '#{label_name}': #{stats[:unchanged]}"
else
  puts "Contatos com '#{attribute_key}' atualizado: #{stats[:changed]}"
  puts "Contatos que já tinham o mesmo valor: #{stats[:unchanged]}"
end
puts "Telefones sem contato no Chatwoot: #{stats[:not_found_lines]}"
puts "Linhas inválidas (data/formatação): #{stats[:invalid_lines]}" if mode == 'attribute'
puts '--------------------------------------------------'
puts 'Resumo por Conta:'
stats[:by_account].each do |acc_id, data|
  acc_name = data[:name]
  puts "  • Conta #{acc_id} (#{acc_name}):"
  puts "      - Encontrados: #{data[:found]}"
  puts "      - Atualizados agora: #{data[:changed]}"
  puts "      - Já estavam corretos: #{data[:unchanged]}"
end
puts '=================================================='

if not_found_numbers.any?
  not_found_path = File.join(File.dirname(csv_path), "telefones_nao_encontrados_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}.txt")
  File.write(not_found_path, not_found_numbers.join("\n"))
  puts "📄 Telefones não encontrados salvos em: #{not_found_path}"
end

if invalid_rows.any?
  invalid_path = File.join(File.dirname(csv_path), "linhas_invalidas_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}.txt")
  File.write(invalid_path, invalid_rows.join("\n"))
  puts "📄 Linhas inválidas salvas em: #{invalid_path}"
end

# rubocop:enable Rails/Output, Rails/Exit, Metrics/AbcSize, Metrics/MethodLength, Metrics/BlockLength
