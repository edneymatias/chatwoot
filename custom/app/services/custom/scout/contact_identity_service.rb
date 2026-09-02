# frozen_string_literal: true

class Custom::Scout::ContactIdentityService
  PLACEHOLDER_NAME_PATTERN = /\A[a-z]+-[a-z]+-\d{1,3}\z/

  def self.placeholder_name?(contact)
    return false if contact.nil? || contact.name.blank?

    contact.name.to_s.match?(PLACEHOLDER_NAME_PATTERN)
  end
end
