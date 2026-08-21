# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::HandoverToHuman do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:team) { create(:team, account: account) }
  let(:user) { create(:user, account: account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      handover_team: team,
      enabled: true,
      feature_memory: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  before do
    create(:inbox_member, user: user, inbox: inbox)
    create(:team_member, user: user, team: team)
  end

  describe '#execute' do
    it 'transfers conversation to human queue and records handoff' do
      memory_service = instance_double(Custom::Scout::ContactNotesService, generate_and_update_notes: [])
      allow(Custom::Scout::ContactNotesService).to receive(:new).with(scout, conversation).and_return(memory_service)

      result = tool.execute(assignee_id: user.id, reason: 'Cliente qualificado')
      expect(result).to include('successfully')
      expect(tool.handoff_executed).to be(true)

      conversation.reload
      expect(conversation.status).to eq('open')
      expect(conversation.assignee_id).to eq(user.id)
      expect(conversation.team_id).to eq(team.id)
      expect(conversation.messages.where(private: true).last.content).to include('Transferência para atendimento humano')
      expect(memory_service).to have_received(:generate_and_update_notes)
    end
  end
end
