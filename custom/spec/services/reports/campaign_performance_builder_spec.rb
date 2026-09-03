require 'rails_helper'

RSpec.describe Reports::CampaignPerformanceBuilder, type: :service do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let!(:stage1) { account.pipeline_stages.create!(name: 'Stage 1', position: 1) }
  let!(:stage2) { account.pipeline_stages.create!(name: 'Stage 2', position: 2, campaign_report_milestone: true) }

  describe '#build' do
    context 'when there are no campaign opportunities' do
      it 'returns zeroed summary with milestone when milestone stage exists' do
        result = described_class.new(account: account).build

        expect(result[:summary]).to eq(
          leads: 0,
          milestone_stage_name: 'Stage 2',
          won_count: 0,
          won_rate_pct: 0.0,
          lost_count: 0,
          lost_rate_pct: 0.0,
          distinct_campaigns: 0,
          distinct_adsets: 0,
          distinct_ads: 0,
          milestone_count: 0,
          milestone_rate_pct: 0.0
        )
      end

      it 'returns empty breakdown arrays' do
        result = described_class.new(account: account).build

        expect(result[:by_campaign]).to eq([])
        expect(result[:by_adset]).to eq([])
        expect(result[:by_ad]).to eq([])
      end

      it 'omits milestone keys when no milestone stage exists' do
        stage2.update!(campaign_report_milestone: false)

        result = described_class.new(account: account).build

        expect(result[:summary]).not_to have_key(:milestone_count)
        expect(result[:summary]).not_to have_key(:milestone_rate_pct)
        expect(result[:summary][:milestone_stage_name]).to be_nil
      end
    end

    context 'with opportunities in various states' do
      before do
        Opportunity.create!(
          account: account, contact: contact, pipeline_stage: stage1,
          title: 'Opp 1', status: :won, campaign_source_id: 'src_1',
          campaign_resolution_status: 'resolved', campaign_name: 'Promo A',
          campaign_adset_name: 'Set 1', campaign_ad_name: 'Ad 1',
          created_at: 2.days.ago
        )
        Opportunity.create!(
          account: account, contact: contact, pipeline_stage: stage2,
          title: 'Opp 2', status: :lost, campaign_source_id: 'src_2',
          campaign_resolution_status: 'resolved', campaign_name: 'Promo A',
          campaign_adset_name: 'Set 1', campaign_ad_name: 'Ad 2',
          created_at: 2.days.ago
        )
        Opportunity.create!(
          account: account, contact: contact, pipeline_stage: stage1,
          title: 'Opp Pending', status: :open, campaign_source_id: 'src_3',
          campaign_resolution_status: 'pending', campaign_name: nil,
          created_at: 2.days.ago
        )
        Opportunity.create!(
          account: account, contact: contact, pipeline_stage: stage2,
          title: 'Opp Organic', status: :won, campaign_source_id: 'src_4',
          campaign_resolution_status: 'organic_post', campaign_name: 'Organic Post',
          created_at: 2.days.ago
        )
        Opportunity.create!(
          account: account, contact: contact, pipeline_stage: stage2,
          title: 'Opp No Campaign', status: :won, campaign_source_id: nil,
          created_at: 2.days.ago
        )
      end

      it 'calculates summary status counts correctly excluding non-campaign leads', :aggregate_failures do
        summary = described_class.new(account: account).build[:summary]

        expect(summary[:leads]).to eq(3)
        expect(summary[:won_count]).to eq(1)
        expect(summary[:won_rate_pct]).to eq(33.3)
        expect(summary[:lost_count]).to eq(1)
        expect(summary[:lost_rate_pct]).to eq(33.3)
      end

      it 'calculates distinct metrics and milestone reach correctly', :aggregate_failures do
        summary = described_class.new(account: account).build[:summary]

        expect(summary[:distinct_campaigns]).to eq(1)
        expect(summary[:distinct_adsets]).to eq(1)
        expect(summary[:distinct_ads]).to eq(2)
        expect(summary[:milestone_count]).to eq(1)
        expect(summary[:milestone_rate_pct]).to eq(33.3)
      end

      it 'filters by date range' do
        range = 1.day.ago..Time.current
        result = described_class.new(account: account, range: range).build

        expect(result[:summary][:leads]).to eq(0)
      end

      it 'generates campaign breakdown grouped and sorted by leads descending', :aggregate_failures do
        by_campaign = described_class.new(account: account).build[:by_campaign]

        expect(by_campaign.map { |r| r[:campaign_name] }).to eq(['Promo A', 'Não identificado'])
        promo = by_campaign.first
        expect(promo[:leads]).to eq(2)
        expect(promo[:won_count]).to eq(1)
        expect(promo[:lost_count]).to eq(1)
        expect(promo[:milestone_count]).to eq(1)
        expect(promo[:milestone_rate_pct]).to eq(50.0)
      end

      it 'populates unidentified campaign breakdown entry correctly', :aggregate_failures do
        unid = described_class.new(account: account).build[:by_campaign].second

        expect(unid[:leads]).to eq(1)
        expect(unid[:won_count]).to eq(0)
        expect(unid[:lost_count]).to eq(0)
        expect(unid[:milestone_count]).to eq(0)
        expect(unid[:milestone_rate_pct]).to eq(0.0)
      end
    end
  end
end
