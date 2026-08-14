class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @opportunities = policy_scope(Opportunity)
                     .includes(:pipeline_stage, :origin_conversation,
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
    @opportunity = Current.account.opportunities.build(resolve_origin_conversation_id(opportunity_create_params))
    if @opportunity.save
      render json: @opportunity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @opportunity.update(resolve_origin_conversation_id(opportunity_update_params))
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

  private

  def fetch_opportunity
    @opportunity = Current.account.opportunities.find(params[:id])
  end

  # The frontend only knows conversations by their per-account `display_id`
  # (the conversation JSON exposes it as `id`), so `origin_conversation_id`
  # arrives as a display_id here and must be resolved to the real
  # conversation primary key before it's persisted on the `origin_conversation_id` column.
  def resolve_origin_conversation_id(permitted_params)
    return permitted_params unless permitted_params.key?(:origin_conversation_id)
    return permitted_params if permitted_params[:origin_conversation_id].blank?

    conversation = Current.account.conversations.find_by(display_id: permitted_params[:origin_conversation_id])
    permitted_params[:origin_conversation_id] = conversation&.id
    permitted_params
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
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end
end
