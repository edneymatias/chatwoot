# frozen_string_literal: true

class ScoutAccountConfigPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end
end
