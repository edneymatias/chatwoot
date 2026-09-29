# frozen_string_literal: true

class Custom::ScoutV2::Playbook::ContactGapsFormatter
  NAME_WARNING = 'o nome registrado é um identificador gerado pelo sistema — não o use para se dirigir ao cliente'

  def self.call(contact:)
    return nil if contact.nil?

    missing = []
    missing << "- nome (#{NAME_WARNING})" if Custom::Scout::ContactIdentityService.placeholder_name?(contact)
    missing << '- telefone' if contact.phone_number.blank?

    return nil if missing.empty?

    "Dados de contato faltando:\n#{missing.join("\n")}"
  end
end
