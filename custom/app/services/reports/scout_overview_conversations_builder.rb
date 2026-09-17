# frozen_string_literal: true

class Reports::ScoutOverviewConversationsBuilder
  include TimezoneHelper

  ALLOWED_RANGES = %w[7 30 this_month last_month].freeze
  ALLOWED_STATUSES = %w[all qualified disqualified abandoned in_progress transferred_without_opportunity].freeze

  pattr_initialize [:account!, :scout!, :range!, :timezone_offset, :status, :page, :per_page]

  def build
    {
      conversations: formatted_conversations,
      status_counts: calculated_status_counts,
      pagination: pagination_metadata
    }
  end

  private

  def current_page
    [page.to_i, 1].max
  end

  def current_per_page
    return 25 if per_page.blank?

    per_page.to_i.clamp(1, 100)
  end

  def resolved_range
    @resolved_range ||= begin
      offset = Float(timezone_offset, exception: false) if timezone_offset.present?
      tz_name = timezone_name_from_offset(offset) if offset
      tz_name ||= Time.zone.name

      now = Time.current.in_time_zone(tz_name)
      case range.to_s
      when 'this_month' then now.all_month
      when 'last_month' then (now - 1.month).all_month
      when '30' then (now - 30.days)..now
      else (now - 7.days)..now
      end
    end
  end

  def scout_handled_scope
    @scout_handled_scope ||= account.conversations
                                    .where(inbox_id: scout.inboxes.select(:id))
                                    .where(created_at: resolved_range)
  end

  def status_case_sql
    <<~SQL.squish
      CASE
        WHEN latest_opp.id IS NOT NULL THEN
          CASE
            WHEN latest_opp.pipeline_stage_id = #{scout.qualified_stage_id.to_i} THEN 'qualified'
            WHEN latest_opp.pipeline_stage_id = #{scout.unqualified_stage_id.to_i} THEN 'disqualified'
            WHEN latest_opp.pipeline_stage_id = #{scout.rescue_stage_id.to_i} THEN 'abandoned'
            ELSE 'in_progress'
          END
        WHEN conversations.status = 2 THEN 'in_progress'
        ELSE 'transferred_without_opportunity'
      END AS outcome_status
    SQL
  end

  def lateral_join_sql
    <<~SQL.squish
      LEFT JOIN LATERAL (
        SELECT opp.id, opp.title, opp.pipeline_stage_id
        FROM ichatr_opportunities opp
        JOIN ichatr_opportunity_conversations oc ON oc.opportunity_id = opp.id
        WHERE oc.conversation_id = conversations.id
        ORDER BY opp.updated_at DESC
        LIMIT 1
      ) latest_opp ON true
    SQL
  end

  def lateral_joined_scope
    @lateral_joined_scope ||= scout_handled_scope
                              .joins(lateral_join_sql)
                              .select(
                                'conversations.*',
                                'latest_opp.id AS opp_id',
                                'latest_opp.title AS opp_title',
                                'latest_opp.pipeline_stage_id AS opp_stage_id',
                                status_case_sql
                              )
  end

  def all_classified_conversations
    @all_classified_conversations ||= lateral_joined_scope.to_a
  end

  def calculated_status_counts
    @calculated_status_counts ||= begin
      counts = ALLOWED_STATUSES.index_with(0)
      counts['all'] = all_classified_conversations.size

      all_classified_conversations.each do |c|
        st = c.attributes['outcome_status'].to_s
        counts[st] += 1 if counts.key?(st)
      end

      counts
    end
  end

  def active_status_filter
    st = status.to_s
    ALLOWED_STATUSES.include?(st) ? st : 'all'
  end

  def filtered_conversations
    @filtered_conversations ||= begin
      records = all_classified_conversations.sort_by(&:created_at).reverse
      if active_status_filter == 'all'
        records
      else
        records.select { |c| c.attributes['outcome_status'].to_s == active_status_filter }
      end
    end
  end

  def paginated_conversations
    offset = (current_page - 1) * current_per_page
    filtered_conversations.slice(offset, current_per_page) || []
  end

  def page_messages_metrics
    conv_ids = paginated_conversations.map(&:id)
    return {} if conv_ids.empty?

    Message.reorder(nil)
           .where(conversation_id: conv_ids, message_type: [0, 1])
           .group(:conversation_id)
           .pluck(Arel.sql('conversation_id'), Arel.sql('COUNT(*)'), Arel.sql('MIN(created_at)'), Arel.sql('MAX(created_at)'))
           .each_with_object({}) do |(cid, count, first_at, last_at), hash|
             duration = count > 1 && first_at && last_at ? (last_at - first_at).to_i : nil
             hash[cid] = { count: count, duration: duration }
           end
  end

  def formatted_conversations
    metrics = page_messages_metrics
    paginated_conversations.map { |c| format_conversation(c, metrics[c.id]) }
  end

  def format_conversation(conv, metric)
    m = metric || { count: 0, duration: nil }
    {
      id: conv.id,
      display_id: conv.display_id,
      contact: format_contact(conv.contact),
      inbox: format_inbox(conv.inbox),
      start_at: conv.created_at.to_i,
      duration_seconds: m[:duration],
      messages_count: m[:count],
      status: conv.attributes['outcome_status'],
      opportunity: format_opportunity(conv)
    }
  end

  def format_contact(contact)
    {
      id: contact&.id,
      name: contact&.name,
      identifier: contact&.identifier,
      email: contact&.email,
      phone_number: contact&.phone_number,
      thumbnail: contact&.avatar_url
    }
  end

  def format_inbox(inbox)
    {
      id: inbox&.id,
      name: inbox&.name,
      channel_type: inbox&.channel_type
    }
  end

  def format_opportunity(conv)
    return if conv.attributes['opp_id'].blank?

    {
      id: conv.attributes['opp_id'],
      title: conv.attributes['opp_title'],
      stage_id: conv.attributes['opp_stage_id']
    }
  end

  def pagination_metadata
    total = filtered_conversations.size
    total_pages = [((total.to_f / current_per_page).ceil), 1].max

    {
      current_page: current_page,
      total_count: total,
      per_page: current_per_page,
      total_pages: total_pages
    }
  end
end
