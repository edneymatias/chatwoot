# frozen_string_literal: true

class Reports::ScoutOverviewBuilder
  include TimezoneHelper

  ALLOWED_RANGES = %w[7 30 this_month last_month].freeze

  pattr_initialize [:account!, :scout!, :range!, :timezone_offset]

  def build
    {
      summary: summary_metrics,
      pipeline_stage_distribution: pipeline_stage_distribution,
      interest_by_stage: interest_by_stage
    }
  end

  private

  def scout_handled_scope
    @scout_handled_scope ||= account.opportunities
                                    .joins(origin_conversation: :inbox)
                                    .where(inboxes: { id: scout.inboxes.select(:id) })
  end

  def period_scope
    @period_scope ||= scout_handled_scope.where(created_at: resolved_range)
  end

  def resolved_range
    @resolved_range ||= begin
      offset = Float(timezone_offset, exception: false) if timezone_offset.present?
      tz_name = timezone_name_from_offset(offset) if offset
      tz_name ||= Time.zone.name

      now = Time.current.in_time_zone(tz_name)
      case range.to_s
      when 'this_month'
        now.all_month
      when 'last_month'
        (now - 1.month).all_month
      when '30'
        (now - 30.days)..now
      else
        (now - 7.days)..now
      end
    end
  end

  def summary_metrics
    total_handled = period_scope.count
    return empty_summary_metrics if total_handled.zero?

    stage_counts = period_scope.group(:pipeline_stage_id).count
    rates = outcome_rates(stage_counts, total_handled)

    {
      total_handled: total_handled,
      qualification_rate: rates[:qual_rate],
      disqualification_rate: rates[:disqual_rate],
      abandonment_rate: rates[:ab_rate],
      avg_messages_per_conversation: compute_avg_messages
    }
  end

  def empty_summary_metrics
    {
      total_handled: 0,
      qualification_rate: nil,
      disqualification_rate: nil,
      abandonment_rate: nil,
      avg_messages_per_conversation: nil
    }
  end

  def outcome_rates(stage_counts, total_handled)
    {
      qual_rate: stage_rate(scout.qualified_stage_id, stage_counts, total_handled),
      disqual_rate: stage_rate(scout.unqualified_stage_id, stage_counts, total_handled),
      ab_rate: stage_rate(scout.rescue_stage_id, stage_counts, total_handled)
    }
  end

  def stage_rate(stage_id, stage_counts, total_handled)
    compute_rate(stage_counts[stage_id], total_handled) if stage_id.present?
  end

  def compute_rate(count, total)
    return nil if total.to_i.zero?

    ((count || 0).to_f / total * 100).round(2)
  end

  def compute_avg_messages
    conv_ids = period_scope.where.not(origin_conversation_id: nil).pluck(:origin_conversation_id).compact.uniq
    return nil if conv_ids.empty?

    counts = account.messages
                    .unscope(:order)
                    .where(conversation_id: conv_ids)
                    .where(message_type: %i[incoming outgoing])
                    .group(:conversation_id)
                    .count

    total_msgs = counts.values.sum
    (total_msgs.to_f / conv_ids.size).round(1)
  end

  def pipeline_stage_distribution
    counts = period_scope.group(:pipeline_stage_id).count
    account.pipeline_stages.order(:position).map do |stage|
      {
        stage_id: stage.id,
        stage_name: stage.name,
        stage_position: stage.position,
        count: counts[stage.id] || 0
      }
    end
  end

  def interest_by_stage
    defn = scout.interest_attribute_definition
    return { configured: false } if defn.blank?

    {
      configured: true,
      attribute_name: defn.attribute_display_name,
      data: interest_stage_data(defn.attribute_key)
    }
  end

  def interest_stage_data(attr_key)
    stage_breakdowns = build_interest_breakdowns(attr_key)
    account.pipeline_stages.order(:position).map do |stage|
      {
        stage_id: stage.id,
        stage_name: stage.name,
        breakdown: stage_breakdowns[stage.id]
      }
    end
  end

  def build_interest_breakdowns(attr_key)
    opp_table = Opportunity.table_name
    rows = period_scope.group("#{opp_table}.pipeline_stage_id", Arel.sql("#{opp_table}.custom_attributes ->> '#{attr_key}'")).count
    rows.each_with_object(Hash.new { |h, k| h[k] = {} }) do |((st_id, val), cnt), breakdowns|
      breakdowns[st_id][val.nil? ? 'null' : val] = cnt
    end
  end
end
