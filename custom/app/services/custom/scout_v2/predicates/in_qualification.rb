# frozen_string_literal: true

class Custom::ScoutV2::Predicates::InQualification
  def initialize
    @opportunity_open = Custom::ScoutV2::Predicates::OpportunityOpen.new
    @pending_required_fields = Custom::ScoutV2::Predicates::PendingRequiredFields.new
  end

  def call(ctx, _arg = nil)
    ctx.opportunity.nil? || (@opportunity_open.call(ctx) && @pending_required_fields.call(ctx))
  end
end
