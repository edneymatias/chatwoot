require 'rails_helper'

RSpec.describe OpportunityPolicy do
  subject(:policy) { described_class.new(user_context, opportunity) }

  let(:user_context) { { user: user, account: account, account_user: account_user } }
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { account.pipeline_stages.create!(name: 'Test Stage') }
  let(:opportunity) do
    Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'My Opp', assignee: assignee,
                        origin_conversation: origin_conversation)
  end
  let(:assignee) { nil }
  let(:origin_conversation) { nil }

  context 'when administrator' do
    let(:user) { create(:user, account: account, role: :administrator) }
    let(:account_user) { user.account_users.first }

    it 'permits all actions' do
      [:index?, :show?, :create?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end
  end

  context 'when assignee agent' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:account_user) { user.account_users.first }
    let(:assignee) { user }

    it 'permits show, update, destroy' do
      [:show?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end

    it 'permits index and create' do
      # For index/create, the policy is usually initialized with the Opportunity class, not an instance.
      # But since our policy allows index and create when account_user is present, it will pass here.
      expect(policy).to be_index
      expect(policy).to be_create
    end
  end

  context 'when agent with conversation access' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:account_user) { user.account_users.first }
    let(:inbox) { create(:inbox, account: account) }
    let(:origin_conversation) { create(:conversation, account: account, inbox: inbox) }

    before do
      create(:inbox_member, user: user, inbox: inbox)
    end

    it 'permits show, update, destroy' do
      [:show?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end
  end

  context 'when unrelated agent' do
    let(:user) { create(:user, account: account, role: :agent) }
    let(:account_user) { user.account_users.first }
    let(:inbox) { create(:inbox, account: account) }
    let(:origin_conversation) { create(:conversation, account: account, inbox: inbox) }

    it 'permits show, update, destroy' do
      [:show?, :update?, :destroy?].each do |action|
        expect(policy.public_send(action)).to be_truthy
      end
    end
  end
end
