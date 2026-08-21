# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Scout, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Lead Qualified') }
  let(:team) { create(:team, account: account) }
  let(:valid_attributes) do
    {
      account: account,
      name: 'Sales Qualifier',
      persona: 'You qualify incoming leads according to BANT criteria.',
      default_pipeline_stage: stage,
      qualified_stage: stage,
      unqualified_stage: stage,
      handover_team: team,
      debounce_delay_seconds: 5,
      responses_quota: -1,
      responses_consumed: 0,
      enabled: true,
      feature_memory: true
    }
  end

  describe 'associations' do
    it 'belongs to account' do
      scout = described_class.new(valid_attributes)
      expect(scout.account).to eq(account)
    end

    it 'belongs to pipeline stages and handover team optionally' do
      scout = described_class.new(valid_attributes.merge(
                                    default_pipeline_stage: nil,
                                    qualified_stage: nil,
                                    unqualified_stage: nil,
                                    handover_team: nil
                                  ))
      expect(scout).to be_valid
    end

    it 'cascade-deletes associated ScoutInbox records on destroy' do
      scout = described_class.create!(valid_attributes)
      scout_inbox = ScoutInbox.create!(scout: scout, inbox: inbox)

      expect { scout.destroy! }.to change { ScoutInbox.exists?(scout_inbox.id) }.from(true).to(false)
    end
  end

  describe 'system_prompt alias' do
    it 'aliases system_prompt to persona' do
      scout = described_class.new(system_prompt: 'Custom Prompt')
      expect(scout.persona).to eq('Custom Prompt')
      expect(scout.system_prompt).to eq('Custom Prompt')
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(described_class.new(valid_attributes)).to be_valid
    end

    it 'validates presence of account' do
      scout = described_class.new(valid_attributes.merge(account: nil))
      expect(scout).not_to be_valid
      expect(scout.errors[:account]).to be_present
    end

    it 'validates presence of name' do
      scout = described_class.new(valid_attributes.merge(name: nil))
      expect(scout).not_to be_valid
      expect(scout.errors[:name]).to include("can't be blank")
    end

    it 'validates debounce_delay_seconds numericality' do
      expect(described_class.new(valid_attributes.merge(debounce_delay_seconds: 0))).not_to be_valid
      expect(described_class.new(valid_attributes.merge(debounce_delay_seconds: -1))).not_to be_valid
      expect(described_class.new(valid_attributes.merge(debounce_delay_seconds: 5))).to be_valid
    end

    it 'validates responses_quota numericality' do
      expect(described_class.new(valid_attributes.merge(responses_quota: -2))).not_to be_valid
      expect(described_class.new(valid_attributes.merge(responses_quota: -1))).to be_valid
      expect(described_class.new(valid_attributes.merge(responses_quota: 0))).to be_valid
    end

    it 'validates responses_consumed numericality' do
      expect(described_class.new(valid_attributes.merge(responses_consumed: -1))).not_to be_valid
      expect(described_class.new(valid_attributes.merge(responses_consumed: 0))).to be_valid
    end
  end

  describe '#quota_available?' do
    it 'returns true for unlimited quota (-1) regardless of responses_consumed' do
      scout = described_class.new(responses_quota: -1, responses_consumed: 10_000)
      expect(scout.quota_available?).to be(true)
    end

    it 'returns true when responses_consumed is strictly less than responses_quota' do
      scout = described_class.new(responses_quota: 100, responses_consumed: 99)
      expect(scout.quota_available?).to be(true)
    end

    it 'returns false when responses_consumed equals responses_quota' do
      scout = described_class.new(responses_quota: 100, responses_consumed: 100)
      expect(scout.quota_available?).to be(false)
    end

    it 'returns false when responses_consumed exceeds responses_quota' do
      scout = described_class.new(responses_quota: 100, responses_consumed: 105)
      expect(scout.quota_available?).to be(false)
    end

    it 'returns false when responses_quota is 0' do
      scout = described_class.new(responses_quota: 0, responses_consumed: 0)
      expect(scout.quota_available?).to be(false)
    end
  end

  describe '#llm_chat' do
    it 'resolves chat client using account ScoutAccountConfig' do
      ScoutAccountConfig.create!(
        account: account,
        provider: :gemini,
        model_name: 'gemini-2.0-flash',
        api_key: 'custom-gemini-key'
      )
      scout = described_class.new(valid_attributes)

      chat = scout.llm_chat
      expect(chat).to be_a(RubyLLM::Chat)
      expect(chat.model.id).to eq('gemini-2.0-flash')
    end

    it 'raises error when ScoutAccountConfig is not present' do
      scout = described_class.new(valid_attributes)

      expect { scout.llm_chat }.to raise_error(/Configuração de LLM não encontrada/)
    end
  end
end
