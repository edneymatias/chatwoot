# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::HandoffService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending) }
  let(:team) { create(:team, account: account) }
  let(:other_team) { create(:team, account: account) }
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
  let(:service) { described_class.new(scout: scout, conversation: conversation) }

  before do
    create(:inbox_member, user: user, inbox: inbox)
    create(:team_member, user: user, team: team)
  end

  describe '#perform' do
    it 'transfers conversation, sets team and assignee, creates private note, and triggers memory when enabled' do
      memory_service = instance_double(Custom::Scout::ContactNotesService, generate_and_update_notes: [])
      allow(Custom::Scout::ContactNotesService).to receive(:new).with(scout, conversation).and_return(memory_service)

      result = service.perform(assignee_id: user.id, reason: 'Qualified lead')
      expect(result).to eq('Conversation transferred to human queue successfully.')

      conversation.reload
      expect(conversation.status).to eq('open')
      expect(conversation.assignee_id).to eq(user.id)
      expect(conversation.team_id).to eq(team.id)
      expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
      expect(conversation.messages.where(private: true).last.content).to include('Transferência para atendimento humano: Qualified lead')
      expect(memory_service).to have_received(:generate_and_update_notes)
    end

    it 'creates public transfer message before bot_handoff! is called' do
      allow(conversation).to receive(:bot_handoff!).and_wrap_original do |original_method, *args|
        expect(conversation.messages.where(private: false, message_type: :outgoing).last&.content).to eq(I18n.t('conversations.scout.handoff'))
        original_method.call(*args)
      end

      service.perform(reason: 'Qualified lead')
      expect(conversation.reload.status).to eq('open')
    end

    it 'uses explicit team_id when passed over scout handover_team_id' do
      service.perform(team_id: other_team.id)
      conversation.reload
      expect(conversation.team_id).to eq(other_team.id)
    end

    it 'sends public handoff notice and a private note with a default reason when reason is blank' do
      expect do
        service.perform
      end.to change { conversation.messages.where(private: false, message_type: :outgoing).count }.by(1)
         .and(change { conversation.messages.where(private: true).count }.by(1))

      expect(conversation.messages.where(private: false, message_type: :outgoing).last.content).to eq(I18n.t('conversations.scout.handoff'))
      expect(conversation.messages.where(private: true).last.content).to include('motivo não informado pelo modelo')
    end

    it 'sends the public handoff notice in the conversation language when set, over the account locale' do
      conversation.update!(additional_attributes: { 'conversation_language' => 'pt_BR' })
      account.update!(locale: :en)

      service.perform

      expect(conversation.messages.where(private: false, message_type: :outgoing).last.content)
        .to eq(I18n.t('conversations.scout.handoff', locale: 'pt_BR'))
    end

    context 'when scout feature_memory is false' do
      before { scout.update!(feature_memory: false) }

      it 'does not invoke ContactNotesService' do
        allow(Custom::Scout::ContactNotesService).to receive(:new)
        service.perform
        expect(Custom::Scout::ContactNotesService).not_to have_received(:new)
      end
    end

    context 'when conversation is not pending' do
      before { conversation.update!(status: :open) }

      it 'does not call bot_handoff! or send public notice but still updates assignments' do
        allow(conversation).to receive(:bot_handoff!)
        expect do
          service.perform(assignee_id: user.id)
        end.not_to(change { conversation.messages.where(private: false, message_type: :outgoing).count })

        expect(conversation).not_to have_received(:bot_handoff!)
        expect(conversation.reload.assignee_id).to eq(user.id)
      end
    end
  end
end
