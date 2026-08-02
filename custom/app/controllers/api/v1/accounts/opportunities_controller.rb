class Api::V1::Accounts::OpportunitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @opportunities = policy_scope(Opportunity).includes(:pipeline_stage, :origin_conversation, contact: { avatar_attachment: :blob },
                                                                                               assignee: { avatar_attachment: :blob }).order(created_at: :desc)
    @opportunities = @opportunities.where(pipeline_stage_id: params[:pipeline_stage_id]) if params[:pipeline_stage_id].present?
    @opportunities = @opportunities.page(params[:page]).per(10) if params[:page].present?
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
      :assignee_id,
      :value,
      custom_attributes: {}
    )
  end
end
