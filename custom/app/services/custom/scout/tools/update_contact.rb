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

    phone_issue, normalized_phone = resolve_phone(phone)
    coerced_custom_attributes = custom_attributes.present? ? coerce_hash_param(custom_attributes) : nil
    field_labels = build_field_labels(name: name, email: email, phone: normalized_phone, custom_attributes: coerced_custom_attributes)

    updated_contact = identify_contact(target_contact, name, email, normalized_phone, coerced_custom_attributes)
    return validation_failure_message(updated_contact.errors) if updated_contact.errors.present?

    if updated_contact.id != target_contact.id
      # Core's ContactMergeAction reassigns conversations to the winning contact via a bulk
      # `.update` on the Conversation relation — it does not (and can't, from outside) refresh the
      # in-memory `@conversation` object every other tool in this same turn shares a reference to.
      # Without this, a later tool call this turn (e.g. manage_opportunity) would still see the
      # pre-merge, now-deleted contact via the stale cached association.
      @conversation&.reload
      create_merge_note(target_contact, updated_contact)
    end

    "Contact updated successfully.#{scoped_confirmation_reminder(field_labels)}#{phone_issue_note(phone_issue)}"
  end

  private

  # Surfaces the merge for human review — the agent who eventually picks up this conversation has
  # no other way to know its contact record just absorbed a different one mid-conversation (e.g. a
  # lead messaging again from a new device, matched by phone/email — see conversation #63).
  def create_merge_note(mergee_contact, base_contact)
    Messages::MessageBuilder.new(
      nil, @conversation,
      { content: "🔗 Contato mesclado automaticamente: registro anterior (\"#{mergee_contact.name}\", ID #{mergee_contact.id}) " \
                 "foi consolidado no contato ID #{base_contact.id} — telefone ou email já estava cadastrado. Histórico de " \
                 'conversas e oportunidades anteriores foi preservado.',
        private: true }
    ).perform
  end

  # Reuses Chatwoot's own contact-identification/merge flow (the same one the website widget's
  # `setUser`/prechat identify calls already go through — see app/actions/contact_identify_action.rb)
  # instead of writing our own duplicate-contact handling. If the given phone/email/identifier
  # already belongs to a different contact in this account (e.g. the same lead messaging again from
  # a different device/browser — conversation #63), it transparently merges this conversation onto
  # that existing contact rather than crashing on a uniqueness violation or silently refusing to
  # save. `ActiveRecord::RecordInvalid` can still surface from ContactIdentifyAction's own `save!`
  # for anything neither it nor our phone normalization anticipated — rescued as a last resort so
  # the tool call never crashes the turn.
  def identify_contact(target_contact, name, email, normalized_phone, coerced_custom_attributes)
    ContactIdentifyAction.new(
      contact: target_contact,
      params: { name: name, email: email, phone_number: normalized_phone, custom_attributes: coerced_custom_attributes }
    ).perform
  rescue ActiveRecord::RecordInvalid => e
    e.record
  end

  def validation_failure_message(errors)
    "Não foi possível salvar os dados informados: #{errors.full_messages.to_sentence}. " \
      'Peça ao cliente para confirmar ou corrigir essas informações.'
  end

  def build_field_labels(name:, email:, phone:, custom_attributes:)
    labels = []
    labels << 'Nome' if name.present?
    labels << 'Email' if email.present?
    labels << 'Telefone' if phone.present?
    labels.concat(custom_attribute_labels(custom_attributes.keys, attribute_model: :contact_attribute)) if custom_attributes.present?
    labels
  end

  # Prevents the crash observed in production (conversation #61): a customer typing a raw local
  # number (e.g. "999220122", no DDD/country code) fails Contact's E.164 format validation, which
  # ContactIdentifyAction does not normalize either. Brazil convention: callers often omit the DDD
  # when it matches the business's own city — so an account-configured default_area_code fills that
  # gap instead of guessing or crashing.
  def resolve_phone(phone)
    return [nil, nil] if phone.blank?

    normalized = normalize_phone_number(phone)
    return [:unparseable, nil] if normalized.blank?

    [nil, normalized]
  end

  def normalize_phone_number(raw_phone)
    stripped = raw_phone.to_s.strip
    return "+#{stripped.delete_prefix('+').gsub(/\D/, '')}" if stripped.start_with?('+')

    digits = stripped.gsub(/\D/, '')
    case digits.length
    when 10..11
      "#{@scout.default_country_code}#{digits}"
    when 8..9
      return nil if @scout.default_area_code.blank?

      "#{@scout.default_country_code}#{@scout.default_area_code}#{digits}"
    end
  end

  def phone_issue_note(issue)
    return '' unless issue == :unparseable

    ' Não foi possível registrar o telefone informado — o formato não foi reconhecido como um ' \
      'número de telefone válido com DDD. Peça ao cliente o telefone completo, com DDD.'
  end
end
