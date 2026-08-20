# frozen_string_literal: true

class Api::V1::Accounts::ScoutsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout, only: %i[show update destroy sync_required_attributes]

  def index
    @scouts = Current.account.scouts.includes(:inboxes, :required_custom_attribute_definitions).order(created_at: :desc)
    render json: @scouts.as_json(include_associations)
  end

  def show
    render json: @scout.as_json(include_associations)
  end

  def create
    @scout = Current.account.scouts.build(scout_params)
    if @scout.save
      sync_attributes if params[:scout][:required_custom_attribute_definition_ids].present?
      render json: @scout.as_json(include_associations), status: :created
    else
      render json: { error: @scout.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @scout.update(scout_params)
      sync_attributes if params[:scout][:required_custom_attribute_definition_ids].present?
      render json: @scout.as_json(include_associations)
    else
      render json: { error: @scout.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @scout.destroy!
    head :no_content
  end

  def sync_required_attributes
    attribute_ids = Array(params[:custom_attribute_definition_ids]).map(&:to_i)
    @scout.sync_required_attribute_ids!(attribute_ids)
    render json: @scout.as_json(include_associations)
  end

  private

  def set_scout
    @scout = Current.account.scouts.find(params[:id])
  end

  def check_authorization
    super(Scout)
  end

  def scout_params
    allowed = %i[
      name persona debounce_delay_seconds responses_quota enabled
      default_pipeline_stage_id qualified_stage_id unqualified_stage_id handover_team_id
    ]

    allowed += %i[provider model_name api_key_override] if current_user.administrator?

    params.require(:scout).permit(*allowed, required_custom_attribute_definition_ids: [])
  end

  def sync_attributes
    attribute_ids = Array(params[:scout][:required_custom_attribute_definition_ids]).map(&:to_i)
    @scout.sync_required_attribute_ids!(attribute_ids)
  end

  def include_associations
    {
      include: {
        inboxes: { only: %i[id name channel_type] },
        required_custom_attribute_definitions: {
          only: %i[id attribute_key attribute_display_name attribute_display_type attribute_model]
        }
      },
      except: %i[api_key_override]
    }
  end
end
