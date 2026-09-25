# frozen_string_literal: true

class Custom::ScoutV2::Playbook::PendingFieldsFormatter
  def self.call(account_id:, pending_keys:)
    return nil if pending_keys.blank?

    defs_by_key = CustomAttributeDefinition.where(
      account_id: account_id,
      attribute_model: :opportunity_attribute,
      attribute_key: pending_keys
    ).index_by(&:attribute_key)

    lines = pending_keys.map do |key|
      defn = defs_by_key[key]
      label = defn&.attribute_display_name.presence || key
      desc = defn&.attribute_description.presence
      "- #{label} (chave: #{key})#{desc ? ": #{desc}" : ''}"
    end

    "Campos pendentes para esta oportunidade:\n#{lines.join("\n")}"
  end
end
