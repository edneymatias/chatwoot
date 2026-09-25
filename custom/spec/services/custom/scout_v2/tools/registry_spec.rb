# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Tools::Registry do
  let(:account) { create(:account) }
  let(:scout) { Scout.create!(account: account, name: 'Test Scout') }
  let(:conversation) { create(:conversation, account: account) }

  describe '.build' do
    it 'instantiates known tools' do
      tools = described_class.build(['manage_opportunity'], scout: scout, conversation: conversation)

      expect(tools.size).to eq(1)
      expect(tools.first).to be_a(Custom::Scout::Tools::ManageOpportunity)
      expect(tools.first.scout).to eq(scout)
      expect(tools.first.conversation).to eq(conversation)
    end

    it 'raises KeyError when given an unregistered tool name' do
      expect do
        described_class.build(['unknown_tool'], scout: scout, conversation: conversation)
      end.to raise_error(KeyError)
    end

    it 'returns empty array when tool_names is empty' do
      expect(described_class.build([], scout: scout, conversation: conversation)).to eq([])
    end
  end
end
