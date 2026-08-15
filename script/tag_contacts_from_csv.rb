# frozen_string_literal: true

# script/tag_contacts_from_csv.rb
#
# Uso:
#   docker compose exec rails bundle exec rails runner script/tag_contacts_from_csv.rb
#
# Variáveis de ambiente ou argumentos:
#   CSV_PATH="/caminho/arquivo.csv"
#   LABEL="cliente"
#   ACCOUNT_ID="2" (opcional: se omitido, processa todas as contas onde o contato existir)
#   DRY_RUN="true" (opcional: simula sem gravar no banco)

csv_path = ENV['CSV_PATH'] || ARGV[0]
unless csv_path && File.exist?(csv_path)
  candidates = [
    'tmp/pessoa_202608141542.csv',
    '/app/tmp/pessoa_202608141542.csv',
    '/home/matias/Downloads/pessoa_202608141542.csv'
  ]
  csv_path = candidates.find { |c| File.exist?(c) }
end
label_name = (ENV['LABEL'] || ARGV[1] || 'cliente').downcase.strip
target_account_id = ENV['ACCOUNT_ID']&.to_i
dry_run = ENV['DRY_RUN'] == 'true' || ARGV.include?('--dry-run')

puts '=================================================='
puts '  CHATWOOT - IMPORTAÇÃO DE TAGS PARA CONTATOS'
puts '=================================================='
puts "Arquivo: #{csv_path}"
puts "Tag: '#{label_name}'"
puts "Conta: #{target_account_id ? "ID #{target_account_id}" : 'Todas as contas'}"
puts "Modo Dry Run: #{dry_run ? 'SIM (Apenas simulação)' : 'NÃO (Gravação no banco ativa)'}"
puts '--------------------------------------------------'

unless File.exist?(csv_path)
  puts "❌ Arquivo não encontrado: #{csv_path}"
  exit 1
end

lines = File.readlines(csv_path, chomp: true).map(&:strip).reject(&:blank?)
# Remove cabeçalho se houver
lines.shift if /[a-zA-Z]/.match?(lines.first)

puts "📋 Total de telefones para processar: #{lines.size}"

def generate_phone_variants(raw)
  digits = raw.gsub(/\D/, '')
  return [] if digits.blank?

  variants = []
  variants << "+#{digits}"
  variants << "+55#{digits}"
  variants << digits

  # Se for celular BR com 11 dígitos (DDD + 9 + 8 dígitos)
  if digits.size == 11 && digits.match?(/\A(1[1-9]|[2-9][0-9])9\d{8}\z/)
    ddd = digits[0..1]
    num = digits[3..]
    variants << "+55#{ddd}#{num}" # formato sem o 9 (comum em IDs do WhatsApp)
    variants << "+#{ddd}#{num}"
    variants << "55#{ddd}#{num}"
    variants << "#{ddd}#{num}"
  # Se for celular/fixo BR com 10 dígitos (DDD + 8 dígitos)
  elsif digits.size == 10 && digits.match?(/\A(1[1-9]|[2-9][0-9])\d{8}\z/)
    ddd = digits[0..1]
    num = digits[2..]
    variants << "+55#{ddd}9#{num}" # formato com o 9 adicionado
    variants << "+#{ddd}9#{num}"
    variants << "55#{ddd}9#{num}"
  # Se começar com DDI 55 e tiver 12 dígitos (55 + DDD + 8 dígitos)
  elsif digits.size == 12 && digits.start_with?('55')
    ddd = digits[2..3]
    num = digits[4..]
    variants << "+55#{ddd}9#{num}"
  # Se começar com DDI 55 e tiver 13 dígitos (55 + DDD + 9 dígitos)
  elsif digits.size == 13 && digits.start_with?('55')
    ddd = digits[2..3]
    num = digits[5..]
    variants << "+55#{ddd}#{num}"
  end

  variants.uniq
end

# Garante etiquetas criadas nas contas alvo
accounts_to_prepare = target_account_id ? Account.where(id: target_account_id) : Account.all
labels_by_account = {}

accounts_to_prepare.each do |acc|
  next if dry_run

  lbl = acc.labels.find_or_create_by!(title: label_name) do |l|
    l.color = '#1f93ff'
    l.show_on_sidebar = true
    l.description = 'Importado via ERP'
  end
  labels_by_account[acc.id] = lbl
end

stats = {
  total_lines: lines.size,
  found_contacts: 0,
  already_tagged: 0,
  newly_tagged: 0,
  not_found_lines: 0,
  by_account: Hash.new { |h, k| h[k] = { found: 0, tagged: 0, already: 0 } }
}

not_found_phones = []

lines.each_with_index do |line, idx|
  variants = generate_phone_variants(line)
  if variants.empty?
    not_found_phones << line
    stats[:not_found_lines] += 1
    next
  end

  scope = Contact.where(phone_number: variants)
  scope = scope.where(account_id: target_account_id) if target_account_id

  contacts = scope.to_a

  if contacts.empty?
    not_found_phones << line
    stats[:not_found_lines] += 1
  else
    stats[:found_contacts] += contacts.size

    contacts.each do |contact|
      acc_stats = stats[:by_account][contact.account_id]
      acc_stats[:found] += 1

      if contact.label_list.include?(label_name)
        stats[:already_tagged] += 1
        acc_stats[:already] += 1
      else
        unless dry_run
          contact.label_list.add(label_name)
          contact.save(validate: false)
        end
        stats[:newly_tagged] += 1
        acc_stats[:tagged] += 1
      end
    end
  end

  if ((idx + 1) % 200).zero? || (idx + 1) == lines.size
    print "\r[Progresso] #{idx + 1}/#{lines.size} telefones analisados..."
    $stdout.flush
  end
end

puts "\n\n================== RESULTADO =================="
puts "Linhas no arquivo: #{stats[:total_lines]}"
puts "Contatos correspondentes encontrados: #{stats[:found_contacts]}"
puts "Novos contatos rotulados com '#{label_name}': #{stats[:newly_tagged]}"
puts "Contatos que já tinham a tag '#{label_name}': #{stats[:already_tagged]}"
puts "Telefones sem contato no Chatwoot: #{stats[:not_found_lines]}"
puts '--------------------------------------------------'
puts 'Resumo por Conta:'
stats[:by_account].each do |acc_id, data|
  acc_name = Account.find_by(id: acc_id)&.name || "ID #{acc_id}"
  puts "  • Conta #{acc_id} (#{acc_name}):"
  puts "      - Encontrados: #{data[:found]}"
  puts "      - Marcados agora: #{data[:tagged]}"
  puts "      - Já marcados: #{data[:already]}"
end
puts '=================================================='

not_found_path = File.join(File.dirname(csv_path), "telefones_nao_encontrados_#{Time.now.strftime('%Y%m%d%H%M%S')}.txt")
if not_found_phones.any?
  File.write(not_found_path, not_found_phones.join("\n"))
  puts "📄 Telefones não encontrados salvos em: #{not_found_path}"
end
