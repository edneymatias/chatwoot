# frozen_string_literal: true

class Api::V1::Accounts::Opportunities::ActivitiesController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard

  before_action :fetch_opportunity
  before_action :check_authorization

  def index
    @activities = @opportunity.activities.includes(:actor).order(occurred_at: :desc)
    render json: @activities
  end

  private

  def fetch_opportunity
    @opportunity = Current.account.opportunities.find(params[:opportunity_id])
  end

  def check_authorization
    authorize(@opportunity, :show?)
  end
end
