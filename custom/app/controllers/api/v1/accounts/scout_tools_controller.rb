# frozen_string_literal: true

class Api::V1::Accounts::ScoutToolsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout_tool, only: %i[show update destroy]

  def index
    @scout_tools = Current.account.scout_tools.order(created_at: :desc)
    render json: @scout_tools
  end

  def show
    render json: @scout_tool
  end

  def create
    @scout_tool = Current.account.scout_tools.build(tool_params)

    if @scout_tool.save
      render json: @scout_tool, status: :created
    else
      render json: { error: @scout_tool.errors.full_messages.join(', ') }, status: :unprocessable_entity
    end
  end

  def update
    if @scout_tool.update(tool_params)
      render json: @scout_tool
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
      truncated: result.truncated?(500),
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

    schema = extract_schema_param
    permitted[:parameter_schema] = schema.blank? ? {} : parse_nested_param(schema) if schema.present?

    headers = extract_headers_param
    permitted[:auth_headers] = headers.blank? ? nil : parse_nested_param(headers) if headers.present?

    permitted
  end

  def test_params
    headers = extract_headers_param
    payload = extract_payload_param

    {
      endpoint_url: params[:endpoint_url].presence || params.dig(:scout_tool, :endpoint_url),
      http_method: params[:http_method].presence || params.dig(:scout_tool, :http_method) || 'POST',
      response_template: params[:response_template].presence || params.dig(:scout_tool, :response_template),
      auth_headers: headers.present? ? parse_nested_param(headers) : nil,
      payload: payload.present? ? parse_nested_param(payload) : {}
    }
  end

  def extract_schema_param
    params[:parameter_schema] || params[:parameters_schema] ||
      params.dig(:scout_tool, :parameter_schema) || params.dig(:scout_tool, :parameters_schema)
  end

  def extract_headers_param
    params[:auth_headers] || params[:headers] ||
      params.dig(:scout_tool, :auth_headers) || params.dig(:scout_tool, :headers)
  end

  def extract_payload_param
    params[:payload].presence || params.dig(:scout_tool, :payload)
  end

  def parse_nested_param(val)
    if val.is_a?(String)
      val.strip.start_with?('{', '[') ? JSON.parse(val) : val
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
