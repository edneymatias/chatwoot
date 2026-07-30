class OpportunityPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def show?
    administrator? || assignee? || conversation_access?
  end

  def create?
    @account_user.present?
  end

  def update?
    administrator? || assignee? || conversation_access?
  end

  def destroy?
    administrator? || assignee? || conversation_access?
  end

  private

  def administrator?
    @account_user.administrator?
  end

  def assignee?
    record.assignee_id == user.id
  end

  def conversation_access?
    return false if record.origin_conversation.blank?

    Pundit.policy!(user_context, record.origin_conversation).show?
  end

  class Scope < Scope
    def resolve
      return scope.where(account_id: account.id) if @account_user.administrator?

      inbox_ids = user.inboxes.where(account_id: account.id).select(:id)
      team_ids = user.teams.where(account_id: account.id).select(:id)

      scope.where(account_id: account.id)
           .left_outer_joins(:origin_conversation)
           .where(
             'matias_opportunities.assignee_id = :user_id OR ' \
             'conversations.inbox_id IN (:inbox_ids) OR ' \
             'conversations.team_id IN (:team_ids)',
             user_id: user.id,
             inbox_ids: inbox_ids,
             team_ids: team_ids
           )
    end
  end
end
