class Api::V1::Accounts::OpportunityFunnelReportsController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard
  include DateRangeHelper

  before_action :check_authorization

  def index
    report = Reports::OpportunityFunnelBuilder.new(account: Current.account, range: range).build
    render json: report
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
