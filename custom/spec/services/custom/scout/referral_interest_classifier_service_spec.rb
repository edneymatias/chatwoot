# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ReferralInterestClassifierService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:interest_attribute) do
    create(
      :custom_attribute_definition,
      account: account,
      attribute_key: 'interesse',
      attribute_display_type: :list,
      attribute_model: :opportunity_attribute,
      attribute_values: %w[Implante Clareamento Ortodontia]
    )
  end
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Qualifier',
      enabled: true,
      interest_attribute_definition: interest_attribute
    )
  end
  let(:service) { described_class.new(scout: scout, conversation: conversation) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Triage', position: 1) }
  let(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      title: 'Opportunity Test',
      campaign_name: 'Campanha Implantes 2026',
      campaign_headline: 'Implante Dentário com Condições Especiais',
      campaign_body: 'Recupere seu sorriso com implantes de alta precisão.'
    )
  end

  let(:fake_chat) { instance_double(RubyLLM::Chat) }
  let(:fake_response) do
    instance_double(
      RubyLLM::Message,
      content: { 'interest' => 'Implante' }.to_json
    )
  end

  before do
    allow(scout).to receive(:llm_chat).with(temperature: 0.0).and_return(fake_chat)
    allow(fake_chat).to receive(:with_schema).and_return(fake_chat)
    allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
    allow(fake_chat).to receive(:ask).and_return(fake_response)
  end

  describe 'Custom::Scout::ReferralInterestClassifierSchema' do
    it 'creates a dynamic schema subclass constrained to given options or null' do
      schema_class = Custom::Scout::ReferralInterestClassifierSchema.for_options(%w[Implante Clareamento])
      json_schema = schema_class.new.to_json_schema

      expect(json_schema[:name]).to eq('ReferralInterestClassifierSchema')
      interest_prop = json_schema[:schema][:properties][:interest]
      expect(interest_prop[:anyOf]).to contain_exactly(
        { type: 'string', enum: %w[Implante Clareamento] },
        { type: 'null' }
      )
    end
  end

  describe '#classify' do
    it 'classifies interest using ad content and returns matched option' do
      expect(fake_chat).to receive(:ask) do |prompt|
        expect(prompt).to include('Campanha Implantes 2026')
        expect(prompt).to include('Implante Dentário com Condições Especiais')
        fake_response
      end

      result = service.classify(opportunity: opportunity)
      expect(result).to eq('Implante')
    end

    it 'returns nil when LLM returns null for ambiguous content' do
      null_response = instance_double(RubyLLM::Message, content: { 'interest' => nil }.to_json)
      allow(fake_chat).to receive(:ask).and_return(null_response)

      result = service.classify(opportunity: opportunity)
      expect(result).to be_nil
    end

    it 'returns nil when LLM returns an option outside configured attribute_values' do
      unexpected_response = instance_double(RubyLLM::Message, content: { 'interest' => 'OutroInvalido' }.to_json)
      allow(fake_chat).to receive(:ask).and_return(unexpected_response)

      result = service.classify(opportunity: opportunity)
      expect(result).to be_nil
    end

    it 'returns nil without calling LLM when opportunity has no ad content' do
      plain_opportunity = Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Plain Opp')
      expect(fake_chat).not_to receive(:ask)

      result = service.classify(opportunity: plain_opportunity)
      expect(result).to be_nil
    end

    it 'returns nil without calling LLM when scout has no interest_attribute_definition' do
      scout.update!(interest_attribute_definition: nil)
      expect(fake_chat).not_to receive(:ask)

      result = service.classify(opportunity: opportunity)
      expect(result).to be_nil
    end

    it 'silently returns nil and captures exception on LLM error' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError.new('API timeout'))
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect(tracker).to receive(:capture_exception)
      expect(service.classify(opportunity: opportunity)).to be_nil
    end
  end
end
