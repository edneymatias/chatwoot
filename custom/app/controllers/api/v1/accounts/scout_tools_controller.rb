# frozen_string_literal: true

class Api::V1::Accounts::ScoutToolsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout_tool, only: %i[show update destroy]

  def index
    @scout_tools = Current.account.scout_tools.order(created_at: :desc)
    render json: @scout_tools.as_json(except: %i[auth_headers])
  end

  def show
    render json: @scout_tool.as_json(except: %i[auth_headers])
  end

  def create
    @scout_tool = Current.account.scout_tools.build(tool_params)

    if @scout_tool.save
      render json: @scout_tool.as_json(except: %i[auth_headers]), status: :created
    else
      render json: { error: @scout_tool.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @scout_tool.update(tool_params)
      render json: @scout_tool.as_json(except: %i[auth_headers])
    else
      render json: { error: @scout_tool.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def destroy
    @scout_tool.destroy!
    head :ok
  end

  private

  def set_scout_tool
    @scout_tool = Current.account.scout_tools.find(params[:id])
  end

  def check_authorization
    super(ScoutTool)
  end

  def tool_params
    permitted = params.permit(:name, :description, :endpoint_url, :http_method, :enabled, :auth_headers)
    if params[:parameter_schema].present?
      permitted[:parameter_schema] = params[:parameter_schema].is_a?(String) ? JSON.parse(params[:parameter_schema]) : params[:parameter_schema]
    end
    permitted
  rescue JSON::ParserError => e
    render json: { error: "Invalid JSON in parameter_schema: #{e.message}" }, status: :unprocessable_entity
    nil
  end
end
