# frozen_string_literal: true

class Custom::ScoutV2::Predicates::OpportunityInStage
  ROLES = %w[qualified unqualified initial].freeze

  def call(ctx, arg = nil)
    return false if arg.blank? || ROLES.exclude?(arg.to_s)

    ctx.opportunity_stage_role.to_s == arg.to_s
  end
end
