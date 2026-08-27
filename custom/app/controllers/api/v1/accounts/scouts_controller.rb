# frozen_string_literal: true

class Api::V1::Accounts::ScoutsController < Api::V1::Accounts::BaseController
  wrap_parameters :scout, include: Scout.column_names + %w[required_custom_attribute_definition_ids]

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
    account_config = ScoutAccountConfig.find_by(account_id: Current.account.id)
    if account_config.blank? || account_config.api_key.blank?
      render json: { error: 'Configuração de LLM da conta obrigatória antes de criar Scouts.' }, status: :unprocessable_entity
      return
    end

    @scout = Current.account.scouts.build(scout_params.except(:required_custom_attribute_definition_ids))
    if @scout.save
      sync_attributes if sync_attributes_requested?
      render json: @scout.reload.as_json(include_associations), status: :created
    else
      render json: { error: @scout.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @scout.update(scout_params.except(:required_custom_attribute_definition_ids))
      sync_attributes if sync_attributes_requested?
      render json: @scout.reload.as_json(include_associations)
    else
      render json: { error: @scout.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @scout.destroy!
    head :no_content
  end

  def sync_required_attributes
    attribute_ids = Array(params[:custom_attribute_definition_ids])
    @scout.sync_required_attribute_ids!(attribute_ids)
    render json: @scout.reload.as_json(include_associations)
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

    scout_source = params.key?(:scout) ? params.require(:scout) : params
    scout_source.permit(*allowed, required_custom_attribute_definition_ids: [])
  end

  def sync_attributes_requested?
    params.key?(:required_custom_attribute_definition_ids) ||
      params[:scout]&.key?(:required_custom_attribute_definition_ids)
  end

  def sync_attributes
    raw_ids = if params.key?(:required_custom_attribute_definition_ids)
                params[:required_custom_attribute_definition_ids]
              else
                params.dig(:scout, :required_custom_attribute_definition_ids)
              end
    @scout.sync_required_attribute_ids!(raw_ids)
  end

  def include_associations
    {
      include: {
        inboxes: { only: %i[id name channel_type] },
        required_custom_attribute_definitions: {
          only: %i[id attribute_key attribute_display_name attribute_display_type attribute_model]
        }
      }
    }
  end
end
