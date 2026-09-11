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
    it 'flags handoff_needed and captures assignment params without invoking HandoffService' do
      expect(Custom::Scout::HandoffService).not_to receive(:new)

      result = tool.execute(assignee_id: user.id, team_id: team.id, reason: 'Cliente qualificado')
      expect(result).to eq(
        'A transferência será confirmada após sua resposta final. Escreva agora uma mensagem natural de encerramento, sem perguntas.'
      )
      expect(tool.handoff_needed).to be(true)
      expect(tool.handoff_assignee_id).to eq(user.id)
      expect(tool.handoff_team_id).to eq(team.id)
      expect(tool.handoff_reason).to eq('Cliente qualificado')
    end

    it 'returns simulated handoff message when running in playground mode' do
      allow(tool).to receive(:playground?).and_return(true)
      expect(Custom::Scout::HandoffService).not_to receive(:new)

      result = tool.execute(assignee_id: user.id, reason: 'Teste no playground')
      expect(result).to eq('[Simulado] Atendimento transferido para humano (Motivo: Teste no playground).')
      expect(tool.handoff_needed).to be_nil
    end
  end
end
