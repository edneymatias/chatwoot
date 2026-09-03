# frozen_string_literal: true

require 'rails_helper'

RSpec.describe OpportunitiesFilter do
  let(:account) { create(:account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let(:contact1) { create(:contact, account: account, name: 'Alice Smith') }
  let(:contact2) { create(:contact, account: account, name: 'Bob Jones') }

  let!(:opp1) do
    Opportunity.create!(
      account: account,
      contact: contact1,
      pipeline_stage: stage,
      title: 'Enterprise Software Deal',
      value: 5000,
      campaign_name: 'Black Friday 2026',
      campaign_adset_name: 'Tech Enthusiasts',
      campaign_ad_name: 'Discount 20 Percent',
      campaign_platform: 'facebook',
      status: :open
    )
  end

  let!(:opp2) do
    Opportunity.create!(
      account: account,
      contact: contact2,
      pipeline_stage: stage,
      title: 'Small Business Consulting',
      value: 1500,
      campaign_name: 'Summer Promo',
      campaign_adset_name: 'Entrepreneurs',
      campaign_ad_name: 'Free Consultation',
      campaign_platform: 'instagram',
      status: :won
    )
  end

  describe '#perform with free-text search (q)' do
    it 'matches by opportunity title' do
      filter = described_class.new(account.opportunities, { q: 'software' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'matches by contact name' do
      filter = described_class.new(account.opportunities, { q: 'alice' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'matches by campaign_name case-insensitively' do
      filter = described_class.new(account.opportunities, { q: 'black friday' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'matches by campaign_adset_name' do
      filter = described_class.new(account.opportunities, { q: 'enthusiasts' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'matches by campaign_ad_name' do
      filter = described_class.new(account.opportunities, { q: 'discount' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'matches by campaign_platform' do
      filter = described_class.new(account.opportunities, { q: 'facebook' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'returns empty when search term has no match' do
      filter = described_class.new(account.opportunities, { q: 'nonexistent' })
      expect(filter.perform).to be_empty
    end

    it 'has the trigram GIN index on title and campaign columns' do
      index = Opportunity.connection.indexes(:ichatr_opportunities).find do |i|
        i.name == 'index_ichatr_opportunities_on_title_and_campaign_trgm'
      end

      expect(index).not_to be_nil
      expect(index.using).to eq(:gin)
      expect(index.columns).to eq(%w[title campaign_name campaign_adset_name campaign_ad_name])
    end
  end

  describe '#perform with status filter' do
    it 'defaults to open status' do
      filter = described_class.new(account.opportunities, {})
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'filters by won status' do
      filter = described_class.new(account.opportunities, { status: 'won' })
      expect(filter.perform).to contain_exactly(opp2)
    end

    it 'returns all statuses when status=all' do
      filter = described_class.new(account.opportunities, { status: 'all' })
      expect(filter.perform).to contain_exactly(opp1, opp2)
    end
  end

  describe '#perform with payload standard column filters' do
    it 'filters with contains operator' do
      payload = [
        {
          'attribute_key' => 'campaign_name',
          'filter_operator' => 'contains',
          'values' => ['friday']
        }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp1)
    end

    it 'filters with does_not_contain operator' do
      payload = [
        {
          'attribute_key' => 'campaign_name',
          'filter_operator' => 'does_not_contain',
          'values' => ['friday']
        }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp2)
    end

    it 'filters by platform equality' do
      payload = [
        {
          'attribute_key' => 'campaign_platform',
          'filter_operator' => 'equal_to',
          'values' => ['instagram']
        }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp2)
    end

    it 'filters by date comparison (created_at is_greater_than)' do
      payload = [
        {
          'attribute_key' => 'created_at',
          'filter_operator' => 'is_greater_than',
          'values' => [1.day.ago.to_s]
        }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp1, opp2)
    end
  end

  describe '#perform with campaign_platform "no platform" sentinel' do
    let!(:opp3) do
      Opportunity.create!(
        account: account,
        contact: contact1,
        pipeline_stage: stage,
        title: 'Referral Signup',
        value: 800,
        campaign_platform: nil,
        status: :open
      )
    end

    it 'filters to organic/internal opportunities with the "none" sentinel' do
      payload = [
        { 'attribute_key' => 'campaign_platform', 'filter_operator' => 'equal_to', 'values' => ['none'] }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp3)
    end

    it 'combines a real platform with the "none" sentinel in a multi-select filter' do
      payload = [
        { 'attribute_key' => 'campaign_platform', 'filter_operator' => 'equal_to', 'values' => %w[facebook none] }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp1, opp3)
    end

    it 'excludes organic/internal opportunities with not_equal_to "none"' do
      payload = [
        { 'attribute_key' => 'campaign_platform', 'filter_operator' => 'not_equal_to', 'values' => ['none'] }
      ].to_json

      filter = described_class.new(account.opportunities, { payload: payload, status: 'all' })
      expect(filter.perform).to contain_exactly(opp1, opp2)
    end
  end
end
