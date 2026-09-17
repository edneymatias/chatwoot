# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Reports::ScoutOverviewBuilder do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_widget, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: channel) }
  let(:stage_qualified) { PipelineStage.create!(account: account, name: 'Qualified', position: 1) }
  let(:stage_unqualified) { PipelineStage.create!(account: account, name: 'Unqualified', position: 2) }
  let(:stage_rescue) { PipelineStage.create!(account: account, name: 'Rescue', position: 3) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Lead Qualifier',
      enabled: true,
      qualified_stage_id: stage_qualified.id,
      unqualified_stage_id: stage_unqualified.id,
      rescue_stage_id: stage_rescue.id
    )
  end

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
  end

  describe '#build' do
    context 'when total_handled is 0 (U10, U13)' do
      let(:builder) { described_class.new(account: account, scout: scout, range: 'last_month') }

      it 'returns zero total_handled and nil rates and avg_messages' do
        summary = builder.build[:summary]

        expect(summary[:total_handled]).to eq(0)
        expect(summary[:qualification_rate]).to be_nil
        expect(summary[:disqualification_rate]).to be_nil
        expect(summary[:abandonment_rate]).to be_nil
        expect(summary[:avg_messages_per_conversation]).to be_nil
      end

      it 'ensures nil rate values are non-Float to prevent Float::NAN serialization' do
        summary = builder.build[:summary]

        expect(summary[:qualification_rate]).not_to be_a(Float)
        expect(summary[:disqualification_rate]).not_to be_a(Float)
        expect(summary[:abandonment_rate]).not_to be_a(Float)
      end

      it 'hardens compute_rate to return nil when total is zero to prevent division by zero NaN' do
        expect(builder.send(:compute_rate, 0, 0)).to be_nil
      end
    end

    context 'when scout is disabled (enabled: false) (U45)' do
      let(:contact) { create(:contact, account: account) }
      let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
      let(:conv) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
      let(:builder) { described_class.new(account: account, scout: scout, range: '7') }

      before do
        scout.update!(enabled: false)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Historical Opp',
          pipeline_stage: stage_qualified,
          origin_conversation: conv,
          created_at: 1.day.ago
        )
      end

      it 'retains historical opportunity data and returns valid report payload' do
        result = builder.build
        expect(result[:summary][:total_handled]).to eq(1)
        expect(result[:summary][:qualification_rate]).to eq(100.0)
      end
    end

    context 'when outcome stages point to the same stage (U46)' do
      let(:contact) { create(:contact, account: account) }
      let(:overlapping_inbox) { create(:inbox, account: account, channel: channel) }
      let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: overlapping_inbox) }
      let(:conv) { create(:conversation, account: account, inbox: overlapping_inbox, contact: contact, contact_inbox: contact_inbox) }
      let(:overlapping_scout) do
        Scout.create!(
          account: account,
          name: 'Overlapping Scout',
          enabled: true,
          qualified_stage_id: stage_qualified.id,
          unqualified_stage_id: stage_qualified.id,
          rescue_stage_id: stage_qualified.id
        )
      end
      let(:builder) { described_class.new(account: account, scout: overlapping_scout, range: '7') }

      before do
        ScoutInbox.create!(scout: overlapping_scout, inbox: overlapping_inbox)
        Opportunity.create!(
          account: account,
          contact: contact,
          title: 'Overlapping Opp',
          pipeline_stage: stage_qualified,
          origin_conversation: conv,
          created_at: 1.day.ago
        )
      end

      it 'counts opportunities in each configured role independently without crashing' do
        result = builder.build
        summary = result[:summary]
        expect(summary[:total_handled]).to eq(1)
        expect(summary[:qualification_rate]).to eq(100.0)
        expect(summary[:disqualification_rate]).to eq(100.0)
        expect(summary[:abandonment_rate]).to eq(100.0)
      end
    end
  end
end
