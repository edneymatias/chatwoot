# frozen_string_literal: true

class Custom::ScoutV2::Predicates::ContactHasPhone
  def call(ctx, _arg = nil)
    ctx.contact&.phone_number.present?
  end
end
