class Reports::CampaignPerformanceBuilder
  pattr_initialize [:account!, :range]

  UNIDENTIFIED = 'Não identificado'.freeze

  def build
    stages = account.pipeline_stages.order(:position).to_a
    milestone_stage = stages.find(&:campaign_report_milestone?)
    opps = period_campaign_opportunities.to_a

    reached = calculate_stage_reach(milestone_stage, opps, stages)

    {
      summary: build_summary(opps, milestone_stage, reached),
      by_campaign: build_by_campaign(opps, milestone_stage, reached),
      by_adset: build_by_adset(opps, milestone_stage, reached),
      by_ad: build_by_ad(opps, milestone_stage, reached)
    }
  end

  private

  def calculate_stage_reach(milestone_stage, opps, stages)
    return Hash.new(0) unless milestone_stage && opps.any?

    Reports::StageReachCalculator.new(
      account: account,
      opportunity_ids: opps.map(&:id),
      stages: stages
    ).calculate
  end

  def period_campaign_opportunities
    base = account.opportunities
                  .where.not(campaign_source_id: [nil, ''])
                  .where.not(campaign_resolution_status: %w[organic_post not_applicable])
    range ? base.where(created_at: range) : base
  end

  def build_summary(opps, milestone_stage, reached)
    total_leads = opps.size
    summary = {
      leads: total_leads,
      milestone_stage_name: milestone_stage&.name
    }
    summary.merge!(status_metrics(opps, total_leads))
    summary.merge!(distinct_counts(opps))
    summary.merge!(milestone_metrics(opps, milestone_stage, reached, total_leads)) if milestone_stage
    summary
  end

  def status_metrics(opps, total_leads)
    won_count = opps.count { |o| o.status == 'won' }
    lost_count = opps.count { |o| o.status == 'lost' }
    {
      won_count: won_count,
      won_rate_pct: rate_pct(won_count, total_leads),
      lost_count: lost_count,
      lost_rate_pct: rate_pct(lost_count, total_leads)
    }
  end

  def distinct_counts(opps)
    {
      distinct_campaigns: distinct_field_count(opps, :campaign_name),
      distinct_adsets: distinct_field_count(opps, :campaign_adset_name),
      distinct_ads: distinct_field_count(opps, :campaign_ad_name)
    }
  end

  def distinct_field_count(opps, field)
    opps.filter_map { |o| o.public_send(field) }.map(&:strip).reject(&:empty?).uniq.size
  end

  def milestone_metrics(opps, milestone_stage, reached, total_leads)
    count = opps.count { |o| reached[o.id] >= milestone_stage.position }
    {
      milestone_count: count,
      milestone_rate_pct: rate_pct(count, total_leads)
    }
  end

  def build_by_campaign(opps, milestone_stage, reached)
    groups = opps.group_by { |o| o.campaign_name.presence || UNIDENTIFIED }
    rows = groups.map do |name, group_opps|
      row = {
        campaign_name: name,
        leads: group_opps.size,
        won_count: group_opps.count { |o| o.status == 'won' },
        lost_count: group_opps.count { |o| o.status == 'lost' }
      }
      add_milestone_metrics(row, group_opps, milestone_stage, reached)
      row
    end
    sort_by_leads(rows)
  end

  def build_by_adset(opps, milestone_stage, reached)
    groups = opps.group_by { |o| adset_group_key(o) }
    rows = groups.map do |(c_name, a_name), group_opps|
      row = {
        campaign_name: c_name,
        campaign_adset_name: a_name,
        leads: group_opps.size,
        won_count: group_opps.count { |o| o.status == 'won' },
        lost_count: group_opps.count { |o| o.status == 'lost' }
      }
      add_milestone_metrics(row, group_opps, milestone_stage, reached)
      row
    end
    sort_by_leads(rows)
  end

  def adset_group_key(opp)
    [opp.campaign_name.presence || UNIDENTIFIED, opp.campaign_adset_name.presence || UNIDENTIFIED]
  end

  def build_by_ad(opps, milestone_stage, reached)
    groups = opps.group_by { |o| ad_group_key(o) }
    rows = groups.map do |(c_name, a_name, ad_name), group_opps|
      row = {
        campaign_name: c_name,
        campaign_adset_name: a_name,
        campaign_ad_name: ad_name,
        leads: group_opps.size,
        won_count: group_opps.count { |o| o.status == 'won' },
        lost_count: group_opps.count { |o| o.status == 'lost' }
      }
      add_milestone_metrics(row, group_opps, milestone_stage, reached)
      row
    end
    sort_by_leads(rows)
  end

  def ad_group_key(opp)
    [
      opp.campaign_name.presence || UNIDENTIFIED,
      opp.campaign_adset_name.presence || UNIDENTIFIED,
      opp.campaign_ad_name.presence || UNIDENTIFIED
    ]
  end

  def sort_by_leads(rows)
    rows.sort_by { |r| -r[:leads] }
  end

  def add_milestone_metrics(row, group_opps, milestone_stage, reached)
    return unless milestone_stage

    count = group_opps.count { |o| reached[o.id] >= milestone_stage.position }
    row[:milestone_count] = count
    row[:milestone_rate_pct] = rate_pct(count, group_opps.size)
  end

  def rate_pct(count, total)
    return 0.0 if total.zero?

    ((count.to_f / total) * 100).round(1)
  end
end
