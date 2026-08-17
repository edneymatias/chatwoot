# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::OpportunityActivityListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:stage1) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:stage2) { PipelineStage.create!(account: account, name: 'Stage 2') }
  let(:opportunity) { Opportunity.create!(account: account, title: 'Deal 1', pipeline_stage: stage1, contact: contact) }

  describe '#opportunity_created' do
    it 'creates an opportunity_created activity' do
      event = Events::Base.new('opportunity_created', Time.zone.now, { opportunity: opportunity, performed_by: user })
      expect do
        listener.opportunity_created(event)
      end.to change(OpportunityActivity, :count).by(1)

      activity = OpportunityActivity.last
      expect(activity.event_type).to eq('opportunity_created')
      expect(activity.actor).to eq(user)
    end
  end

  describe '#opportunity_stage_changed' do
    it 'creates an opportunity_stage_changed activity with stage ids' do
      opportunity.update!(pipeline_stage: stage2)
      event = Events::Base.new(
        'opportunity_stage_changed',
        Time.zone.now,
        { opportunity: opportunity, from_pipeline_stage_id: stage1.id, performed_by: user }
      )
      expect do
        listener.opportunity_stage_changed(event)
      end.to change(OpportunityActivity, :count).by(1)

      activity = OpportunityActivity.last
      expect(activity.event_type).to eq('opportunity_stage_changed')
      expect(activity.metadata['from_stage_id']).to eq(stage1.id)
      expect(activity.metadata['to_stage_id']).to eq(stage2.id)
    end
  end

  describe '#opportunity_won and #opportunity_lost' do
    it 'creates won and lost activities' do
      won_event = Events::Base.new(
        'opportunity_won',
        Time.zone.now,
        { opportunity: opportunity, from_pipeline_stage_id: stage1.id, performed_by: user }
      )
      lost_event = Events::Base.new(
        'opportunity_lost',
        Time.zone.now,
        { opportunity: opportunity, from_pipeline_stage_id: stage1.id, performed_by: user }
      )

      listener.opportunity_won(won_event)
      expect(OpportunityActivity.last.event_type).to eq('opportunity_won')

      listener.opportunity_lost(lost_event)
      expect(OpportunityActivity.last.event_type).to eq('opportunity_lost')
    end
  end
end
