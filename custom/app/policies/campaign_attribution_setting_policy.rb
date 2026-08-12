class CampaignAttributionSettingPolicy < ApplicationPolicy
  def show?
    @user.administrator?
  end

  def update?
    @user.administrator?
  end

  def connect?
    @user.administrator?
  end
end
