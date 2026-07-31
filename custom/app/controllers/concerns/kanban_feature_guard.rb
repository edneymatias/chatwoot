module Concerns::KanbanFeatureGuard
  extend ActiveSupport::Concern

  included do
    before_action :check_kanban_feature
  end

  private

  def check_kanban_feature
    return unless Current.account

    return if Current.account.feature_enabled?('opportunities')

    render json: { error: 'Opportunities feature not enabled' }, status: :forbidden
  end
end
