class Reports::OpportunityFunnelBuilder
  pattr_initialize [:account!, :range]

  def build
    {
      conversion_funnel: conversion_funnel,
      win_rate: win_rate,
      pipeline_value_by_stage: pipeline_value_by_stage,
      avg_time_in_stage: avg_time_in_stage,
      new_opportunities_over_time: new_opportunities_over_time,
      sales_cycle_time: sales_cycle_time,
      performance_by_assignee: performance_by_assignee,
      sales_forecast: sales_forecast
    }
  end

  private

  # FR-005: Opportunities created in the period, per pipeline stage in position order.
  # count_data[i] = % of period-created opportunities that reached labels[i] or any later stage.
  # A percentage-of-count metric — not affected by the value/quantity toggle.
  # won_rate_pct = % of period-created opportunities whose current status is "won".
  def conversion_funnel
    stages = account.pipeline_stages.order(:position)
    base_opps = period_created_opportunities
    total_count = base_opps.count
    return empty_funnel(stages) if stages.empty? || total_count.zero?

    reached = max_stage_positions_reached(base_opps, stages)
    count_data = stages.map { |stage| funnel_pct(reached, stage.position, total_count) }
    counts = stage_reached_counts(reached, stages)
    won_rate_pct = ((base_opps.won.count.to_f / total_count) * 100).round(1)
    { labels: stages.map(&:name), count_data: count_data, counts: counts, won_rate_pct: won_rate_pct }
  end

  # Returns a hash {opp_id => max_position_reached} for all base_opps via stage changes.
  def max_stage_positions_reached(base_opps, stages)
    stage_position_by_id = stages.each_with_object({}) { |s, h| h[s.id] = s.position }
    opp_ids = base_opps.pluck(:id)
    OpportunityStageChange
      .where(account_id: account.id, opportunity_id: opp_ids)
      .pluck(:opportunity_id, :to_stage_id)
      .each_with_object(Hash.new(0)) do |(opp_id, stage_id), h|
      pos = stage_position_by_id[stage_id] || 0
      h[opp_id] = [h[opp_id], pos].max
    end
  end

  # FR-008: Raw opportunity count per stage — number of opps that reached each stage or later.
  def stage_reached_counts(reached, stages)
    stages.map { |stage| reached.count { |_id, max_pos| max_pos >= stage.position } }
  end

  def empty_funnel(stages)
    { labels: stages.map(&:name), count_data: stages.map { 0.0 }, counts: stages.map { 0 }, won_rate_pct: 0.0 }
  end

  def funnel_pct(reached, position, total)
    count_reached = reached.count { |_id, max_pos| max_pos >= position }
    ((count_reached.to_f / total) * 100).round(1)
  end

  # FR-006: Count and summed value of won/lost opportunities with closed_at in the period.
  def win_rate
    base = period_closed_opportunities
    {
      won_count: base.won.count,
      lost_count: base.lost.count,
      won_value: base.won.sum(:value).to_f,
      lost_value: base.lost.sum(:value).to_f
    }
  end

  # FR-007: Count and summed value of currently-open opportunities grouped by stage.
  # Intentionally NOT period-filtered — reads current state regardless of since/until.
  def pipeline_value_by_stage
    stages = account.pipeline_stages.order(:position)
    return { labels: [], count_data: [], value_data: [] } if stages.empty?

    open_scope = account.opportunities.open
    value_by_stage = open_scope.group(:pipeline_stage_id).sum(:value)
    count_by_stage = open_scope.group(:pipeline_stage_id).count
    count_data = stages.map { |s| count_by_stage[s.id] || 0 }
    value_data = stages.map { |s| (value_by_stage[s.id] || 0).to_f }
    { labels: stages.map(&:name), count_data: count_data, value_data: value_data }
  end

  # FR-008: Lifetime average of completed OpportunityStageChange durations per stage.
  # "Completed" = the opp has a subsequent stage change (so we know the exit time).
  # NOT period-filtered — intentional (see data-model.md FR-008).
  def avg_time_in_stage
    stages = account.pipeline_stages.order(:position)
    return { labels: [], data: [] } if stages.empty?

    durations_by_stage = build_stage_durations
    data = stages.map { |s| stage_avg_days(durations_by_stage[s.id]) }
    { labels: stages.map(&:name), data: data }
  end

  # Computes consecutive-interval durations (days) per stage from all stage changes.
  def build_stage_durations
    changes = OpportunityStageChange
              .where(account_id: account.id)
              .order(:opportunity_id, :changed_at)
              .pluck(:opportunity_id, :to_stage_id, :changed_at)
    durations_by_stage = Hash.new { |h, k| h[k] = [] }
    prev_by_opp = {}
    changes.each do |opp_id, to_stage_id, changed_at|
      accumulate_duration(prev_by_opp[opp_id], to_stage_id, changed_at, durations_by_stage)
      prev_by_opp[opp_id] = [to_stage_id, changed_at]
    end
    durations_by_stage
  end

  def accumulate_duration(prev, _to_stage_id, changed_at, durations_by_stage)
    return unless prev

    prev_stage_id, prev_changed_at = prev
    durations_by_stage[prev_stage_id] << ((changed_at - prev_changed_at) / 1.day)
  end

  def stage_avg_days(durations)
    return 0.0 if durations.empty?

    (durations.sum / durations.size).round(2)
  end

  # FR-009: Count and summed value of opportunities created in the period, bucketed by day (no gaps).
  def new_opportunities_over_time
    return { labels: [], count_data: [], value_data: [] } unless range

    start_date = range.begin.to_date
    end_date = (range.end || range.begin).to_date
    all_days = (start_date..end_date).map(&:to_s)
    opps_in_range = account.opportunities.where(created_at: range)
    counts = opps_in_range.group('DATE(created_at)').count.transform_keys(&:to_s)
    values = opps_in_range.group('DATE(created_at)').sum(:value).transform_keys(&:to_s)
    {
      labels: all_days,
      count_data: all_days.map { |day| counts[day] || 0 },
      value_data: all_days.map { |day| (values[day] || 0).to_f }
    }
  end

  # FR-010: Average (closed_at - created_at) in days for won opportunities closed in the period.
  # Returns nil when zero such opportunities exist (to distinguish "no data" from "won instantly").
  def sales_cycle_time
    opps = period_closed_opportunities.won.pluck(:created_at, :closed_at).select { |_, c| c }
    return { average_days: nil } if opps.empty?

    avg = opps.sum { |created, closed| (closed - created) / 1.day } / opps.size
    { average_days: avg.round(2) }
  end

  # FR-011: Per assignee_id — count + summed value of won opportunities closed in the
  # period (won_count/won_value), plus count + summed value of currently-open
  # opportunities (open_count/open_value, current-state, NOT period-filtered, same
  # convention as pipeline_value_by_stage). Ranked descending by won_value.
  # nil assignee → "Unassigned".
  def performance_by_assignee
    won_by_id = assignee_counts_and_values(period_closed_opportunities.won)
    open_by_id = assignee_counts_and_values(account.opportunities.open)
    ids = (won_by_id.keys + open_by_id.keys).uniq.sort_by { |id| -won_by_id.fetch(id, [0, 0.0])[1] }
    name_by_id = User.where(id: ids.compact).pluck(:id, :name).to_h

    ids.map do |id|
      won_count, won_value = won_by_id.fetch(id, [0, 0.0])
      open_count, open_value = open_by_id.fetch(id, [0, 0.0])
      {
        assignee_id: id,
        assignee_name: name_by_id.fetch(id, 'Unassigned'),
        won_count: won_count,
        won_value: won_value,
        open_count: open_count,
        open_value: open_value
      }
    end
  end

  def assignee_counts_and_values(scope)
    scope.group(:assignee_id)
         .pluck(:assignee_id, Arel.sql('COUNT(*) AS count'), Arel.sql('SUM(value) AS total_value'))
         .each_with_object({}) { |(id, count, val), h| h[id] = [count, val.to_f] }
  end

  # FR-001/004/005/005a: probability-weighted forecast of currently-open pipeline
  # value expected to close within 90 days, bucketed 0-30/31-60/61-90 days out.
  # Never period-filtered, never persisted — computed fresh on every call.
  # Reuses build_stage_durations (already computed for avg_time_in_stage).
  def sales_forecast
    Reports::SalesForecastCalculator.new(account: account, durations_by_stage: build_stage_durations).call
  end

  def period_created_opportunities
    base = account.opportunities
    range ? base.where(created_at: range) : base
  end

  def period_closed_opportunities
    base = account.opportunities
    range ? base.where(closed_at: range) : base
  end
end
