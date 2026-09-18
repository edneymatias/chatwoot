# frozen_string_literal: true

class Erp::Younus::Client
  include HTTParty

  base_uri 'https://wfh.ichatr.com.br'
  default_timeout 5

  def initialize(token:, id_empresa:)
    @token = token
    @id_empresa = id_empresa
  end

  def find_by_id(external_id)
    get_request('/webhook/pessoa', { idEmpresa: @id_empresa, idPessoa: external_id })
  end

  def search_by_phone(phone)
    get_request('/webhook/pessoas', { idEmpresa: @id_empresa, nrTelcelpessoa: phone }, mode: :search)
  end

  private

  def get_request(path, query, mode: :single)
    response = self.class.get(
      path,
      query: query,
      headers: {
        'token' => @token,
        'Content-Type' => 'application/json'
      }
    )

    handle_response(response, mode: mode)
  rescue Timeout::Error
    raise Erp::ApiError, 'Connection timed out'
  rescue SocketError, Errno::ECONNREFUSED
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
    body = response.parsed_response
    body = JSON.parse(response.body) if body.is_a?(String)
    body = body.first if body.is_a?(Array)

    return unless body.is_a?(Hash) && body['sucesso']

    dados = body['dados']
    return if dados.blank?

    if mode == :search
      { record: dados.dig(0, 'json'), multiple_matches: dados.length > 1 }
    else
      dados.dig(0, 'json')
    end
  rescue TypeError
    raise Erp::ApiError, 'Malformed response from ERP'
  end
end
