# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OpportunityActivity, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:opportunity) { Opportunity.create!(account: account, title: 'Deal 1', pipeline_stage: stage, contact: contact) }

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:opportunity) }
    it { is_expected.to belong_to(:actor).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:opportunity_id) }
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:occurred_at) }
  end

  describe '#as_json' do
    it 'serializes activity with user actor' do
      activity = described_class.create!(
        account: account,
        opportunity: opportunity,
        event_type: 'opportunity_created',
        actor: user,
        metadata: {},
        occurred_at: Time.current
      )

      json = activity.as_json
      expect(json['id']).to eq(activity.id)
      expect(json['event_type']).to eq('opportunity_created')
      expect(json['actor']).to eq({ 'id' => user.id, 'type' => 'user', 'name' => user.name })
    end

    it 'serializes activity with system fallback when actor is nil' do
      activity = described_class.create!(
        account: account,
        opportunity: opportunity,
        event_type: 'opportunity_stage_changed',
        actor: nil,
        metadata: { 'from_stage_id' => 1, 'to_stage_id' => 2 },
        occurred_at: Time.current
      )

      json = activity.as_json
      expect(json['actor']).to eq({ 'type' => 'system', 'name' => nil })
      expect(json['metadata']).to eq({ 'from_stage_id' => 1, 'to_stage_id' => 2 })
    end
  end
end
