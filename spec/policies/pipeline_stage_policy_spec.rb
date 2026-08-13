require 'rails_helper'

RSpec.describe PipelineStagePolicy do
  subject(:policy) { described_class.new(user_context, PipelineStage.new) }

  let(:user_context) { { user: user, account: account, account_user: account_user } }
  let(:account) { create(:account) }

  context 'when administrator' do
    let(:user) { create(:user, account: account, role: :administrator) }
    let(:account_user) { user.account_users.first }

    it 'permits all actions' do
      [:index?, :show?, :create?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end
  end

  context 'when agent' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:account_user) { user.account_users.first }

    it 'permits index and show' do
      [:index?, :show?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end

    it 'forbids create, update, destroy' do
      [:create?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_falsey
      end
    end
  end
end
