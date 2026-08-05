class Api::V1::Accounts::OpportunityAttributeReportsController < Api::V1::Accounts::BaseController
  include Concerns::KanbanFeatureGuard
  include DateRangeHelper

  before_action :check_authorization

  def index
    definition = Current.account.custom_attribute_definitions.find_by(id: params[:custom_attribute_definition_id])

    unless definition && definition.attribute_model == 'opportunity_attribute' && definition.attribute_display_type == 'list'
      render json: { error: 'Invalid or missing list-type opportunity custom attribute' }, status: :unprocessable_entity
      return
    end

    report = Reports::OpportunityAttributeSummaryBuilder.new(account: Current.account, definition: definition, range: range).build
    render json: report
  end

  private

  def check_authorization
    authorize :report, :view?
  end
end
