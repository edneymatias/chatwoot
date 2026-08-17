require 'rails_helper'

RSpec.describe OpportunityConversation, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:opportunity_id) }
    it { is_expected.to validate_presence_of(:conversation_id) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:opportunity).class_name('Opportunity') }
    it { is_expected.to belong_to(:conversation).class_name('Conversation') }
  end

  describe 'uniqueness' do
    let(:account) { create(:account) }
    let(:contact) { create(:contact, account: account) }
    let(:pipeline_stage) { account.pipeline_stages.create!(name: 'Stage 1') }
    let(:conversation) { create(:conversation, account: account, contact: contact) }
    let(:opportunity) do
      Opportunity.create!(
        account: account,
        contact: contact,
        pipeline_stage: pipeline_stage,
        title: 'Deal 1'
      )
    end

    it 'enforces unique conversation_id scoped to opportunity_id' do
      described_class.create!(
        account: account,
        opportunity: opportunity,
        conversation: conversation
      )

      duplicate = described_class.new(
        account: account,
        opportunity: opportunity,
        conversation: conversation
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end
  end
end
