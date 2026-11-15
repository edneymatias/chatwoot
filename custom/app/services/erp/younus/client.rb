# frozen_string_literal: true

class Erp::Younus::Client
  include HTTParty

  base_uri 'https://wfh.ichatr.com.br'
  default_timeout 5

  TRANSPORT_ERRORS = [
    SocketError,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EHOSTUNREACH,
    Errno::ETIMEDOUT,
    Errno::ENETUNREACH,
    HTTParty::Error,
    EOFError,
    OpenSSL::SSL::SSLError
  ].freeze

  def initialize(token:, id_empresa:, settings: {})
    @token = token
    @id_empresa = id_empresa
    @settings = (settings || {}).transform_keys(&:to_s)
  end

  def find_by_id(external_id)
    get_request('/webhook/api/v1/empresas/pessoas', { idEmpresa: @id_empresa, idPessoa: external_id })
  end

  def search_by_phone(phone)
    get_request('/webhook/api/v1/empresas/pessoas/pesquisar', { idEmpresa: @id_empresa, nrTelcelpessoa: phone }, mode: :search)
  end

  def find_person(phone)
    get_request(
      '/webhook/api/v1/empresas/pessoas/pesquisar',
      { idEmpresa: setting_int('id_empresa', default: @id_empresa), nrTelcelpessoa: phone },
      mode: :search
    )
  end

  def create_person(name, phone)
    payload = {
      nmPessoa: name,
      idEmpresa: setting_int('id_empresa', default: @id_empresa),
      idUsuario: setting_int('id_usuario'),
      idConvenio: setting_int('id_convenio'),
      nrConvenio: @settings['nr_convenio'].to_s,
      idOrigempessoa: setting_int('id_origem_pessoa'),
      nrTelcelpessoa: phone
    }

    post_request('/webhook/api/v1/empresas/pessoas', payload)
  end

  def free_slots(date)
    query = {
      data: date.to_s,
      idAgenda: setting_int('id_agenda'),
      idEmpresa: setting_int('id_empresa', default: @id_empresa),
      idServico: setting_int('id_servico')
    }

    get_request('/webhook/api/v1/empresas/agendas/horarios-livres', query, mode: :slots)
  end

  def create_appointment(person_id:, title:, starts_at:, notes:)
    obs = notes.present? ? "Agendado por Scout: #{notes}" : 'Agendado por Scout'
    clean_title = title.to_s[0...100]

    payload = {
      idAgenda: setting_int('id_agenda'),
      idPessoa: Integer(person_id.to_s, 10),
      nmTitulo: clean_title,
      idEmpresa: setting_int('id_empresa', default: @id_empresa),
      idServico: setting_int('id_servico'),
      idUsuario: setting_int('id_usuario'),
      idConvenio: setting_int('id_convenio'),
      dtIniAgenda: starts_at,
      observacoes: obs
    }

    post_request('/webhook/api/v1/empresas/agendas/agendamentos', payload)
  end

  private

  def setting_int(key, default: nil)
    val = @settings[key] || default
    Integer(val.to_s, 10)
  end

  def headers
    {
      'token' => @token,
      'Content-Type' => 'application/json'
    }
  end

  def get_request(path, query, mode: :single)
    with_transport_error_handling do
      response = self.class.get(
        path,
        query: query,
        headers: headers
      )

      handle_response(response, mode: mode)
    end
  end

  def post_request(path, payload)
    with_transport_error_handling do
      response = self.class.post(
        path,
        body: payload.to_json,
        headers: headers
      )

      handle_response(response, mode: :write)
    end
  end

  def with_transport_error_handling
    yield
  rescue Timeout::Error
    raise Erp::ApiError, 'Connection timed out'
  rescue *TRANSPORT_ERRORS
    raise Erp::ApiError, 'Network error'
  rescue JSON::ParserError
    raise Erp::ApiError, 'Malformed response from ERP'
  end

  def handle_response(response, mode: :single)
    case response.code
    when 200
      parse_success_response(response, mode: mode)
    when 401, 403
      raise Erp::AuthenticationError, 'Invalid credentials'
    when 500..599
      raise Erp::ApiError, "ERP service error: #{response.code}"
    else
      raise Erp::ApiError, "Unexpected response: #{response.code}"
    end
  end

  def parse_success_response(response, mode: :single)
    body = coerce_response_body(response)
    return unless body

    if mode == :write
      handle_write_response(body)
    else
      handle_read_response(body, mode)
    end
  rescue TypeError
    raise Erp::ApiError, 'Malformed response from ERP'
  end

  def coerce_response_body(response)
    body = response.parsed_response
    body = JSON.parse(response.body) if body.is_a?(String)
    body = body.first if body.is_a?(Array)
    body.is_a?(Hash) ? body : nil
  end

  def handle_write_response(body)
    raise Erp::ApiError, (body['mensagem'] || 'Declined by ERP') unless body['sucesso']

    extract_single_record(body['dados'])
  end

  def handle_read_response(body, mode)
    raise Erp::ApiError, (body['mensagem'] || 'Declined by ERP') if mode == :slots && !body['sucesso']
    return unless body['sucesso']

    case mode
    when :slots
      body['dados'] || []
    when :search
      extract_search_response(body['dados'])
    else
      extract_single_record(body['dados'])
    end
  end

  def extract_search_response(dados)
    return if dados.blank?

    if dados.is_a?(Array)
      record = dados.dig(0, 'json') || dados.first
      { record: record, multiple_matches: dados.length > 1 }
    elsif dados.is_a?(Hash)
      { record: dados, multiple_matches: false }
    end
  end

  def extract_single_record(dados)
    return if dados.blank?

    if dados.is_a?(Array)
      dados.dig(0, 'json') || dados.first
    elsif dados.is_a?(Hash)
      dados
    end
  end
end
