# frozen_string_literal: true

class Erp::Younus::Adapter < Erp::BaseAdapter
  def self.erp_name
    'Younus'
  end

  def self.capability_settings
    {
      'scheduling' => %w[token id_empresa id_agenda id_servico id_usuario id_convenio],
      'customer_registry' => %w[token id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa]
    }.freeze
  end

  def test_connection
    client.search_by_phone('0')

    true
  end

  def find_by_id(external_id)
    client.find_by_id(external_id) # rubocop:disable Rails/DynamicFindBy
  end

  def search_by_phone(phone)
    client.search_by_phone(phone)
  end

  def phone_from(data)
    return unless data.is_a?(Hash)

    data['nr_telcelpessoa'] || data['nrTelcelpessoa'] || data['telefone']
  end

  def external_id_from(data)
    return unless data.is_a?(Hash)

    val = data['cd_pessoa'] || data['idPessoa']
    return if val.blank?

    str = val.to_s
    return unless str.match?(/\A\d+\z/)

    str
  end

  def find_person(phone:)
    res = client.find_person(phone)
    return { status: :not_found, person: nil } if res.nil? || res[:record].nil?

    if res[:multiple_matches]
      { status: :ambiguous, person: nil }
    else
      record = res[:record]
      id = external_id_from(record)
      name = record['nm_pessoa'] || record['nmPessoa']
      { status: :found, person: { id: id, name: name } }
    end
  end

  def create_person(name:, phone:)
    res = client.create_person(name, phone) || {}
    id = external_id_from(res)
    nm = res['nm_pessoa'] || res['nmPessoa'] || name
    { id: id, name: nm }
  end

  def list_free_slots(date:)
    raw_slots = client.free_slots(date) || []
    slots = raw_slots.filter_map do |slot_str|
      normalize_slot(slot_str)
    end
    slots.sort_by { |s| s[:starts_at].to_s }
  end

  def create_appointment(person_id:, person_name:, starts_at:, notes:)
    res = client.create_appointment(
      person_id: person_id,
      title: person_name,
      starts_at: starts_at,
      notes: notes
    ) || {}

    app_id = res['idMvtoagenda']&.to_s || res['id_mvtoagenda']&.to_s ||
             res['idAgendamento']&.to_s || res['id_agendamento']&.to_s
    { appointment_id: app_id, starts_at: starts_at }
  end

  IDENTIFIER_KEYS = %w[id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa id_agenda id_servico].freeze

  OPERATION_IDENTIFIER_KEYS = {
    'find_by_phone' => %w[id_empresa],
    'create' => %w[id_empresa id_usuario id_convenio nr_convenio id_origem_pessoa],
    'list_slots' => %w[id_empresa id_agenda id_servico],
    'book' => %w[id_empresa id_agenda id_servico id_usuario id_convenio]
  }.freeze

  def operation_identifier_keys(operation_name)
    OPERATION_IDENTIFIER_KEYS[operation_name.to_s] || []
  end

  def client_kwargs
    args = { token: @settings['token'], id_empresa: @settings['id_empresa'] }
    has_extra_settings = @settings.keys.any? { |k| %w[token id_empresa].exclude?(k) }
    args[:settings] = @settings.slice(*IDENTIFIER_KEYS) if has_extra_settings
    args
  end

  private

  def normalize_slot(slot_str)
    return nil if slot_str.blank?
    return normalize_hash_slot(slot_str) if slot_str.is_a?(Hash)

    iso = parse_slot_iso(slot_str.to_s.strip)
    return nil unless iso

    { slot_id: iso, starts_at: iso }
  end

  def normalize_hash_slot(hash)
    s_id = (hash['slot_id'] || hash[:slot_id])&.to_s
    s_at = (hash['starts_at'] || hash[:starts_at])&.to_s
    { slot_id: s_id, starts_at: s_at }
  end

  def parse_slot_iso(str)
    if str.match?(/\A\d{4}-\d{2}-\d{2} \d{2}:\d{2}\z/)
      "#{str.tr(' ', 'T')}:00-03:00"
    elsif str.match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      str.include?('-03:00') ? str : "#{str[0..18]}-03:00"
    else
      fallback_parse_slot_time(str)
    end
  end

  def fallback_parse_slot_time(str)
    time = begin
      Time.zone.parse(str)
    rescue StandardError
      nil
    end
    time&.strftime('%Y-%m-%dT%H:%M:%S-03:00')
  end

  def client
    @client ||= Erp::Younus::Client.new(**client_kwargs)
  end
end
