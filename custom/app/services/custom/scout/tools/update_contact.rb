# frozen_string_literal: true

class Custom::Scout::Tools::UpdateContact < Custom::Scout::Tools::BaseTool
  description 'Updates the contact profile information (name, email, phone number, and custom attributes)'

  param :name, type: :string, desc: 'Contact full or preferred name', required: false
  param :email, type: :string, desc: 'Contact email address', required: false
  param :phone, type: :string, desc: 'Contact phone number', required: false
  param :custom_attributes, type: :hash, desc: 'Key-value map of contact attributes to update or merge', required: false

  def name
    'update_contact'
  end

  def execute(name: nil, email: nil, phone: nil, custom_attributes: nil)
    if playground?
      payload = { name: name, email: email, phone: phone, custom_attributes: custom_attributes }.compact
      return "[Simulado] Contato atualizado: #{payload.to_json}"
    end

    target_contact = contact
    return 'No contact associated with this conversation.' if target_contact.blank?

    field_labels = apply_updates(target_contact, name: name, email: email, phone: phone, custom_attributes: custom_attributes)

    target_contact.save!
    "Contact updated successfully.#{scoped_confirmation_reminder(field_labels)}"
  end

  private

  def apply_updates(target_contact, name:, email:, phone:, custom_attributes:)
    field_labels = []
    if name.present?
      target_contact.name = name
      field_labels << 'Nome'
    end
    if email.present?
      target_contact.email = email
      field_labels << 'Email'
    end
    if phone.present?
      target_contact.phone_number = phone
      field_labels << 'Telefone'
    end
    field_labels.concat(apply_custom_attributes(target_contact, custom_attributes))
  end

  def apply_custom_attributes(target_contact, custom_attributes)
    return [] if custom_attributes.blank?

    coerced_attributes = coerce_hash_param(custom_attributes)
    return [] if coerced_attributes.blank?

    target_contact.custom_attributes = (target_contact.custom_attributes || {}).merge(coerced_attributes)
    custom_attribute_labels(coerced_attributes.keys, attribute_model: :contact_attribute)
  end
end
