# frozen_string_literal: true

class Erp::Younus::Adapter < Erp::BaseAdapter
  def self.erp_name
    'Younus'
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
    val&.to_s
  end

  private

  def client
    @client ||= Erp::Younus::Client.new(
      token: @settings['token'],
      id_empresa: @settings['id_empresa']
    )
  end
end
