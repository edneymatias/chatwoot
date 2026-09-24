# frozen_string_literal: true

class Custom::ScoutV2::Predicates::PendingRequiredFields < Custom::ScoutV2::Predicates::Base
  def call(ctx, _arg = nil)
    ctx.pending_fields.present?
  end
end
