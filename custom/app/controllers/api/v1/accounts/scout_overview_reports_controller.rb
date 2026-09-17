# frozen_string_literal: true

class Api::V1::Accounts::ScoutOverviewReportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :set_scout
  before_action :validate_range
  before_action :validate_status, only: [:conversations]

  ALLOWED_STATUSES = %w[all qualified disqualified abandoned in_progress transferred_without_opportunity].freeze

  def index
    builder = Reports::ScoutOverviewBuilder.new(
      account: Current.account,
      scout: @scout,
      range: params[:range],
      timezone_offset: params[:timezone_offset]
    )
    render json: builder.build
  end

  def conversations
    builder = Reports::ScoutOverviewConversationsBuilder.new(
      account: Current.account,
      scout: @scout,
      range: params[:range],
      timezone_offset: params[:timezone_offset],
      status: params[:status],
      page: params[:page],
      per_page: params[:per_page]
    )
    render json: builder.build
  end

  private

  def check_authorization
    authorize :scout, :show?
  end

  def set_scout
    if params[:scout_id].blank?
      render json: { error: 'scout_id is required' }, status: :unprocessable_entity
      return
    end

    @scout = Current.account.scouts.find(params[:scout_id])
  end

  def validate_range
    return if Reports::ScoutOverviewBuilder::ALLOWED_RANGES.include?(params[:range].to_s)

    render json: { error: 'range is invalid or missing' }, status: :unprocessable_entity
  end

  def validate_status
    return if params[:status].blank? || ALLOWED_STATUSES.include?(params[:status].to_s)

    render json: { error: 'status is invalid' }, status: :unprocessable_entity
  end
end
