# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Tools::Registry do
  let(:account) { create(:account) }
  let(:scout) { Scout.create!(account: account, name: 'Test Scout') }
  let(:conversation) { create(:conversation, account: account) }

  describe 'TOOL_CLASSES' do
    it 'maps exactly manage_opportunity to v2 subclass and update_contact, omitting stage-change and transfer tools' do
      expect(described_class::TOOL_CLASSES.keys).to contain_exactly('manage_opportunity', 'update_contact')
      expect(described_class::TOOL_CLASSES['manage_opportunity']).to eq(Custom::ScoutV2::Tools::ManageOpportunity)
      expect(described_class::TOOL_CLASSES['update_contact']).to eq(Custom::Scout::Tools::UpdateContact)
      expect(described_class::TOOL_CLASSES).not_to have_key('move_opportunity_stage')
      expect(described_class::TOOL_CLASSES).not_to have_key('handover_to_human')
      expect(described_class::TOOL_CLASSES).not_to have_key('call_custom_api')
    end
  end

  describe '.build' do
    it 'instantiates known tools' do
      tools = described_class.build(%w[manage_opportunity update_contact], scout: scout, conversation: conversation)

      expect(tools.size).to eq(2)
      expect(tools.first).to be_a(Custom::ScoutV2::Tools::ManageOpportunity)
      expect(tools.last).to be_a(Custom::Scout::Tools::UpdateContact)
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
