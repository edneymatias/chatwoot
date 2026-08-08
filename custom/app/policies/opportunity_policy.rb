class OpportunityPolicy < ApplicationPolicy
  def index?
    @account_user.present?
  end

  def show?
    @account_user.present?
  end

  def create?
    @account_user.present?
  end

  def update?
    @account_user.present?
  end

  def destroy?
    @account_user.present?
  end

  class Scope < Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
