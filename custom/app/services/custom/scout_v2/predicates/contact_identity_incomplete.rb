# frozen_string_literal: true

class Custom::ScoutV2::Predicates::ContactIdentityIncomplete
  def call(ctx, _arg = nil)
    contact = ctx.contact
    return true if contact.nil?

    Custom::Scout::ContactIdentityService.placeholder_name?(contact) || contact.phone_number.blank?
  end
end
