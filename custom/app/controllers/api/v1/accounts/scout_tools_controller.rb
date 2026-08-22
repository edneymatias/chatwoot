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

  def test
    tp = test_params
    executor = Custom::Scout::Tools::HttpRequestExecutor.new(
      endpoint_url: tp[:endpoint_url],
      http_method: tp[:http_method] || 'POST',
      auth_headers: tp[:auth_headers],
      response_template: tp[:response_template],
      payload: tp[:payload]
    )
    result = executor.execute

    render json: {
      success: result.success?,
      status: result.status,
      raw_body: result.truncated_raw_body(500),
      formatted_response: result.formatted_response,
      error: result.error
    }
  end

  private

  def set_scout_tool
    @scout_tool = Current.account.scout_tools.find(params[:id])
  end

  def check_authorization
    super(ScoutTool)
  end

  def tool_params
    src = params[:scout_tool].presence || params
    permitted = src.permit(:name, :description, :endpoint_url, :http_method, :enabled, :response_template).to_h

    schema = src[:parameter_schema] || src[:parameters_schema]
    permitted[:parameter_schema] = parse_nested_param(schema) if schema.present?

    headers = src[:auth_headers] || src[:headers]
    permitted[:auth_headers] = parse_nested_param(headers) if headers.present?

    permitted
  end

  def test_params
    src = params[:scout_tool].presence || params
    base = src.permit(:endpoint_url, :http_method, :response_template).to_h

    payload = src[:payload]
    payload = parse_nested_param(payload) if payload.present?

    headers = src[:auth_headers] || src[:headers]
    headers = parse_nested_param(headers) if headers.present?

    base.merge(
      auth_headers: headers,
      payload: payload
    )
  end

  def parse_nested_param(val)
    if val.is_a?(String)
      val.start_with?('{', '[') ? JSON.parse(val) : val
    elsif val.respond_to?(:to_unsafe_h)
      val.to_unsafe_h
    elsif val.is_a?(Hash)
      val.to_h
    else
      val
    end
  rescue JSON::ParserError
    val
  end
end
