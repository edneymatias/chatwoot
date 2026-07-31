require 'rails_helper'

RSpec.describe Opportunity, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:contact_id) }
    it { is_expected.to validate_presence_of(:pipeline_stage_id) }
    it { is_expected.to validate_presence_of(:title) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:pipeline_stage) }
    it { is_expected.to belong_to(:origin_conversation).class_name('Conversation').optional }
    it { is_expected.to belong_to(:assignee).class_name('User').optional }
  end

  describe 'pipeline_stage_belongs_to_account' do
    let(:account1) { create(:account) }
    let(:account2) { create(:account) }
    let(:stage1) { account1.pipeline_stages.create!(name: 'Stage 1') }
    let(:stage2) { account2.pipeline_stages.create!(name: 'Stage 2') }
    let(:contact) { create(:contact, account: account1) }

    it 'is valid when pipeline_stage belongs to the same account' do
      opp = Opportunity.new(account: account1, contact: contact, pipeline_stage: stage1, title: 'Opp')
      expect(opp).to be_valid
    end

    it 'is invalid when pipeline_stage belongs to a different account' do
      opp = Opportunity.new(account: account1, contact: contact, pipeline_stage: stage2, title: 'Opp')
      expect(opp).not_to be_valid
      expect(opp.errors[:pipeline_stage]).to include('must belong to the same account')
    end
  end

  describe 'broadcasts' do
    let(:account) { create(:account) }
    let(:pipeline_stage) { account.pipeline_stages.create!(name: 'Stage 1') }
    let(:contact) { create(:contact, account: account) }
    let(:assignee) { create(:user, account: account) }

    it 'broadcasts opportunity_updated on create' do
      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including(
          id: anything,
          pipeline_stage_id: pipeline_stage.id,
          status: 'open',
          contact_id: contact.id,
          assignee_id: assignee.id,
          updated_at: anything,
          account_id: account.id
        )
      )

      Opportunity.create!(
        account: account,
        pipeline_stage: pipeline_stage,
        contact: contact,
        assignee: assignee,
        title: 'New Opp',
        status: 'open'
      )
    end

    it 'broadcasts opportunity_updated on update' do
      opp = Opportunity.create!(
        account: account,
        pipeline_stage: pipeline_stage,
        contact: contact,
        assignee: assignee,
        title: 'New Opp',
        status: 'open'
      )

      new_stage = account.pipeline_stages.create!(name: 'Stage 2')

      expect(ActionCableBroadcastJob).to receive(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including(
          id: opp.id,
          pipeline_stage_id: new_stage.id,
          status: 'won',
          contact_id: contact.id,
          assignee_id: assignee.id,
          updated_at: anything,
          account_id: account.id
        )
      )

      opp.update!(pipeline_stage: new_stage, status: 'won')
    end
  end
end
