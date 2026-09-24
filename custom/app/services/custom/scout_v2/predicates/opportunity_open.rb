# frozen_string_literal: true

class Custom::ScoutV2::Predicates::OpportunityOpen < Custom::ScoutV2::Predicates::Base
  def call(ctx, _arg = nil)
    ctx.opportunity&.status.to_s == 'open'
  end
end
