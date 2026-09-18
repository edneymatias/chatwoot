# frozen_string_literal: true

class Erp::BaseAdapter
  def initialize(hook)
    @hook = hook
    @settings = hook.settings || {}
  end

  def self.erp_name
    raise NotImplementedError, "#{name} must implement self.erp_name"
  end

  def test_connection
    raise NotImplementedError, "#{self.class.name} must implement #test_connection"
  end

  def fetch_data(contact)
    return { status: 'not_found' } if contact.blank? || contact.phone_number.blank?

    cached_id = get_external_id(contact)
    cached_record = fetch_from_cache(contact, cached_id)
    return { status: 'found', data: cached_record, multiple_matches: false } if cached_record.present?

    fallback_phone_search(contact, cached_id)
  end

  def external_id_key
    "#{self.class.erp_name.downcase}_id"
  end

  def get_external_id(contact)
    return unless contact.respond_to?(:additional_attributes)

    contact.additional_attributes&.dig('external', external_id_key)
  end

  def store_external_id(contact, external_id)
    return unless contact.respond_to?(:additional_attributes)

    attrs = (contact.additional_attributes || {}).deep_dup
    attrs['external'] ||= {}
    attrs['external'][external_id_key] = external_id
    contact.additional_attributes = attrs
    contact.save!
  end

  def clear_external_id(contact)
    return unless contact.respond_to?(:additional_attributes)

    attrs = (contact.additional_attributes || {}).deep_dup
    return unless attrs['external']&.key?(external_id_key)

    attrs['external'].delete(external_id_key)
    contact.additional_attributes = attrs
    contact.save!
  end

  def phone_matches?(contact, erp_data)
    return false if contact.blank? || erp_data.blank?

    contact_phone = contact.phone_number.to_s
    erp_phone = phone_from(erp_data).to_s
    contact_digits = contact_phone.gsub(/\D/, '')
    erp_digits = erp_phone.gsub(/\D/, '')

    return false if contact_digits.blank? || erp_digits.blank?
    return true if contact_digits == erp_digits
    return true if contact_digits.start_with?('55') && contact_digits.delete_prefix('55') == erp_digits
    return true if erp_digits.start_with?('55') && erp_digits.delete_prefix('55') == contact_digits

    false
  end

  private

  def fetch_from_cache(contact, cached_id)
    return if cached_id.blank?

    record = find_by_id(cached_id)
    record if record.present? && phone_matches?(contact, record)
  end

  def fallback_phone_search(contact, cached_id)
    search_phone = sanitize_phone_for_search(contact.phone_number)
    search_result = search_by_phone(search_phone)

    if search_result.present? && search_result[:record].present?
      first_record = search_result[:record]
      sync_resolved_id(contact, cached_id, external_id_from(first_record))
      return { status: 'found', data: first_record, multiple_matches: search_result[:multiple_matches] || false }
    end

    clear_external_id(contact) if cached_id.present?
    { status: 'not_found' }
  end

  def sync_resolved_id(contact, cached_id, resolved_id)
    return if resolved_id.blank? || resolved_id.to_s == cached_id.to_s

    clear_external_id(contact) if cached_id.present?
    store_external_id(contact, resolved_id)
  end

  def sanitize_phone_for_search(phone)
    digits = phone.to_s.gsub(/\D/, '')
    digits = digits.delete_prefix('55') if digits.start_with?('55') && digits.length.between?(12, 13)
    digits
  end
end
