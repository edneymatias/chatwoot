class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @opportunities = policy_scope(Opportunity).includes(:contact, :pipeline_stage, :assignee)
    render json: @opportunities
  end

  def show
    render json: @opportunity
  end

  def create
    @opportunity = Current.account.opportunities.build(opportunity_create_params)
    if @opportunity.save
      render json: @opportunity
    else
      render json: { error: @opportunity.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @opportunity.update(opportunity_update_params)
      render json: @opportunity
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
      :assignee_id
    )
  end

  def opportunity_update_params
    params.require(:opportunity).permit(
      :title,
      :contact_id,
      :pipeline_stage_id,
      :status,
      :assignee_id
    )
  end
end
