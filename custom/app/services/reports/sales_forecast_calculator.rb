class Reports::SalesForecastCalculator
  pattr_initialize [:account!, :durations_by_stage!]

  # FR-006/data-model: sufficiency gate + probability-weighted bucketing of
  # currently-open pipeline value, expected to close within 90 days.
  def call
    stages = account.pipeline_stages.order(:position)
    win_probabilities = stage_win_probabilities(stages)
    return { status: 'insufficient_data' } unless forecast_sufficient?(stages, win_probabilities)

    build_forecast(stages, win_probabilities)
  end

  private

  def build_forecast(stages, win_probabilities)
    stage_by_id = stages.index_by(&:id)
    open_opps = account.opportunities.open.pluck(:id, :value, :pipeline_stage_id)
    buckets = %w[day_0 1_30 31_60 61_90].index_with { { count: 0, weighted_value: 0.0 } }

    open_opps.each do |_id, value, pipeline_stage_id|
      stage = stage_by_id[pipeline_stage_id]
      accumulate_forecast_bucket(buckets, stage, value, stages, win_probabilities) if stage
    end

    {
      status: 'ok',
      total_weighted_value: buckets.values.sum { |b| b[:weighted_value] },
      buckets: buckets
    }
  end

  # Lifetime, whole-account win probability per stage — won / (won + lost) among
  # opportunities that reached the stage or later. Reached population only grows
  # as position decreases, so probabilities are accumulated in one descending pass.
  def stage_win_probabilities(stages)
    return {} if stages.empty?

    reached = max_stage_positions_reached(stages)
    status_by_id = account.opportunities.where(id: reached.keys).pluck(:id, :status).to_h
    counts_by_position = won_lost_counts_by_position(reached, status_by_id)
    accumulate_win_probabilities(stages, counts_by_position)
  end

  def max_stage_positions_reached(stages)
    stage_position_by_id = stages.each_with_object({}) { |s, h| h[s.id] = s.position }
    OpportunityStageChange
      .where(account_id: account.id)
      .pluck(:opportunity_id, :to_stage_id)
      .each_with_object(Hash.new(0)) do |(opp_id, stage_id), h|
      pos = stage_position_by_id[stage_id] || 0
      h[opp_id] = [h[opp_id], pos].max
    end
  end

  def won_lost_counts_by_position(reached, status_by_id)
    counts = Hash.new { |h, k| h[k] = [0, 0] }
    reached.each do |opp_id, pos|
      case status_by_id[opp_id]
      when 'won' then counts[pos][0] += 1
      when 'lost' then counts[pos][1] += 1
      end
    end
    counts
  end

  def accumulate_win_probabilities(stages, counts_by_position)
    won = lost = 0
    stages.sort_by { |s| -s.position }.each_with_object({}) do |stage, probs|
      w, l = counts_by_position[stage.position]
      won += w
      lost += l
      probs[stage.id] = won.to_f / (won + lost) if (won + lost).positive?
    end
  end

  # data-model.md Sufficiency gate: every pipeline stage needs a win-probability entry
  # and the account needs at least one lifetime won and one lifetime lost opportunity.
  def forecast_sufficient?(stages, win_probabilities)
    return false if stages.empty?
    return false unless stages.all? { |s| win_probabilities.key?(s.id) }

    account.opportunities.won.exists? && account.opportunities.lost.exists?
  end

  # Sum of average stage duration for the opportunity's current stage and every
  # stage at or after its position in pipeline order (reuses build_stage_durations).
  def expected_close_offset_days(stage, stages)
    stages.select { |s| s.position >= stage.position }
          .sum { |s| stage_avg_days(durations_by_stage[s.id]) }
  end

  def stage_avg_days(durations)
    return 0.0 if durations.blank?

    (durations.sum / durations.size).round(2)
  end

  def forecast_bucket_key(offset_days)
    return 'day_0' if offset_days <= 0
    return '1_30' if offset_days <= 30
    return '31_60' if offset_days <= 60
    return '61_90' if offset_days <= 90

    nil
  end

  def accumulate_forecast_bucket(buckets, stage, value, stages, win_probabilities)
    bucket_key = forecast_bucket_key(expected_close_offset_days(stage, stages))
    return unless bucket_key

    buckets[bucket_key][:count] += 1
    buckets[bucket_key][:weighted_value] += value.to_f * win_probabilities[stage.id]
  end
end
