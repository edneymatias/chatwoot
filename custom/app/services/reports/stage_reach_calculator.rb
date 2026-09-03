class Reports::StageReachCalculator
  pattr_initialize [:account!, :opportunity_ids!, :stages!]

  def calculate
    ids = normalized_opportunity_ids
    return Hash.new(0) if ids.empty? || stages.empty?

    calculate_reach(ids)
  end

  private

  def normalized_opportunity_ids
    opportunity_ids.is_a?(ActiveRecord::Relation) ? opportunity_ids.pluck(:id) : Array(opportunity_ids)
  end

  def stage_position_by_id
    @stage_position_by_id ||= stages.each_with_object({}) { |s, h| h[s.id] = s.position }
  end

  def calculate_reach(ids)
    OpportunityStageChange
      .where(account_id: account.id, opportunity_id: ids)
      .pluck(:opportunity_id, :to_stage_id)
      .each_with_object(Hash.new(0)) do |(opp_id, stage_id), h|
      pos = stage_position_by_id[stage_id] || 0
      h[opp_id] = [h[opp_id], pos].max
    end
  end
end
