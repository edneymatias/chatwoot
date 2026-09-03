# frozen_string_literal: true

class Api::V1::Accounts::Opportunities::ActivitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity
  before_action :check_authorization

  CONVERSATION_EVENT_TYPES = %w[
    conversation_opened
    conversation_transferred_in
    conversation_transferred_out
    conversation_detached
  ].freeze

  def index
    @activities = @opportunity.activities.includes(:actor).order(occurred_at: :desc)
    render json: enrich_activities(@activities)
  end

  private

  def enrich_activities(activities)
    conv_ids = activities.filter_map do |a|
      a.metadata&.dig('conversation_id') if CONVERSATION_EVENT_TYPES.include?(a.event_type)
    end.uniq

    conversations_by_id = Current.account.conversations.where(id: conv_ids).index_by(&:id)

    activities.map do |activity|
      data = activity.as_json
      enrich_single_activity(data, activity, conversations_by_id)
    end
  end

  def enrich_single_activity(data, activity, conversations_by_id)
    return data unless CONVERSATION_EVENT_TYPES.include?(activity.event_type)

    conv_id = activity.metadata&.dig('conversation_id')
    conversation = conversations_by_id[conv_id]

    if conversation
      data['conversation_status'] = conversation.status
      data['conversation_viewable'] = ConversationPolicy.new(pundit_user, conversation).show?
    else
      data['conversation_status'] = nil
      data['conversation_viewable'] = false
    end

    data
  end

  def fetch_opportunity
    @opportunity = Current.account.opportunities.find(params[:opportunity_id])
  end

  def check_authorization
    authorize(@opportunity, :show?)
  end
end
