class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity, only: %i[show update destroy link_conversation]
  before_action :check_authorization

  def index
    @opportunities = policy_scope(Opportunity)
                     .includes(:pipeline_stage, :origin_conversation, :active_conversation,
                               opportunity_conversations: { conversation: :inbox },
                               contact: { avatar_attachment: :blob }, assignee: { avatar_attachment: :blob })

    @opportunities = OpportunitiesFilter.new(@opportunities, params).perform
    if params[:page].present?
      @opportunities = @opportunities.page(params[:page]).per(15)
      render json: {
        meta: {
          count: @opportunities.total_count,
          current_page: @opportunities.current_page
        },
        payload: @opportunities
      }
    else
      render json: @opportunities
    end
  end

  def show
    render json: @opportunity
  end

  def create
    @opportunity = Current.account.opportunities.build(resolve_conversation_ids(opportunity_create_params))
    if @opportunity.save
      render json: @opportunity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @opportunity.update(resolve_conversation_ids(opportunity_update_params))
      render json: @opportunity
    elsif @opportunity.missing_required_fields.present?
      render json: {
        error: @opportunity.errors.full_messages.join(', '),
        missing_required_fields: @opportunity.missing_required_fields
      }, status: :unprocessable_entity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    if @opportunity.destroy
      head :ok
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def link_conversation
    conversation = resolve_conversation_by_id(params[:conversation_id])
    return render json: { error: 'Conversation not found' }, status: :not_found unless conversation
    return render json: { error: 'Cannot link a closed conversation as active' }, status: :unprocessable_entity unless conversation.open?

    existing_opp = find_conflicting_opportunity(conversation)
    if existing_opp.present? && !ActiveModel::Type::Boolean.new.cast(params[:force_transfer])
      return render json: {
        error: 'Conversation already active on another opportunity',
        active_on_opportunity: { id: existing_opp.id, title: existing_opp.title }
      }, status: :conflict
    end

    existing_opp&.detach_active_conversation! if existing_opp.present?
    @opportunity.attach_conversation!(conversation, set_active: true)

    render json: @opportunity
  end

  private

  def fetch_opportunity
    @opportunity = Current.account.opportunities.find(params[:id])
  end

  def resolve_conversation_by_id(identifier)
    return nil if identifier.blank?

    Current.account.conversations.find_by(display_id: identifier) ||
      Current.account.conversations.find_by(id: identifier)
  end

  def find_conflicting_opportunity(conversation)
    Opportunity.where(account_id: Current.account.id, active_conversation_id: conversation.id)
               .where.not(id: @opportunity.id)
               .first
  end

  def resolve_conversation_ids(permitted_params)
    resolve_origin_conversation_id(permitted_params)
    resolve_active_conversation_id(permitted_params)
    permitted_params
  end

  def resolve_origin_conversation_id(permitted_params)
    return unless permitted_params.key?(:origin_conversation_id)
    return if permitted_params[:origin_conversation_id].blank?

    conversation = Current.account.conversations.find_by(display_id: permitted_params[:origin_conversation_id]) ||
                   Current.account.conversations.find_by(id: permitted_params[:origin_conversation_id])
    permitted_params[:origin_conversation_id] = conversation&.id
  end

  def resolve_active_conversation_id(permitted_params)
    return unless permitted_params.key?(:active_conversation_id)
    return if permitted_params[:active_conversation_id].blank?

    conversation = Current.account.conversations.find_by(display_id: permitted_params[:active_conversation_id]) ||
                   Current.account.conversations.find_by(id: permitted_params[:active_conversation_id])
    permitted_params[:active_conversation_id] = conversation&.id
  end

  def check_authorization
    authorize(@opportunity || Opportunity)
  end

  def opportunity_create_params
    params.require(:opportunity).permit(
      :title,
      :contact_id,
      :pipeline_stage_id,
      :status,
      :origin_conversation_id,
      :active_conversation_id,
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end

  def opportunity_update_params
    params.require(:opportunity).permit(
      :title,
      :contact_id,
      :pipeline_stage_id,
      :status,
      :origin_conversation_id,
      :active_conversation_id,
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end
end
