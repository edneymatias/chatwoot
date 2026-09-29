# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutConversationState, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

  describe 'validations and associations' do
    subject(:state) { described_class.new(account: account, conversation: conversation) }

    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:conversation) }
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:conversation_id) }

    it 'validates uniqueness of conversation_id' do
      described_class.create!(account: account, conversation: conversation)
      duplicate = described_class.new(account: account, conversation: conversation)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:conversation_id]).to be_present
    end

    it 'validates transition_count is non-negative integer' do
      state.transition_count = -1
      expect(state).not_to be_valid

      state.transition_count = 0
      expect(state).to be_valid
    end
  end

  describe '.for_conversation' do
    it 'returns existing persisted record if one exists' do
      existing = described_class.create!(account: account, conversation: conversation, active_playbook: 'qualificacao')

      found = described_class.for_conversation(conversation)
      expect(found).to eq(existing)
      expect(found).to be_persisted
    end

    it 'initializes new unsaved record with account_id and defaults when none exists' do
      state = described_class.for_conversation(conversation)

      expect(state).not_to be_persisted
      expect(state.conversation_id).to eq(conversation.id)
      expect(state.account_id).to eq(account.id)
      expect(state.active_playbook).to be_nil
      expect(state.transition_count).to eq(0)
      expect(state.last_exit).to be_nil
    end
  end

  describe '#record_state_activation!' do
    let(:state) { described_class.create!(account: account, conversation: conversation) }

    it 'sets active_playbook, activated_at, and activation_reason = :state' do
      freeze_time do
        state.record_state_activation!('qualificacao')

        state.reload
        expect(state.active_playbook).to eq('qualificacao')
        expect(state.activated_at).to eq(Time.current)
        expect(state.activation_reason).to eq('state')
        expect(state.state?).to be true
      end
    end

    it 'preserves existing last_exit' do
      state.update!(last_exit: 'agendado')

      state.record_state_activation!('qualificacao')
      state.reload

      expect(state.last_exit).to eq('agendado')
    end

    it 'leaves transition_count and handoff_limit_reached_at untouched' do
      state.update!(transition_count: 3, handoff_limit_reached_at: 1.day.ago)
      limit_timestamp = state.handoff_limit_reached_at

      state.record_state_activation!('qualificacao')
      state.reload

      expect(state.transition_count).to eq(3)
      expect(state.handoff_limit_reached_at).to be_within(1.second).of(limit_timestamp)
    end

    it 'persists an unsaved record when called from .for_conversation' do
      unsaved_state = described_class.for_conversation(conversation)
      expect(unsaved_state).not_to be_persisted

      unsaved_state.record_state_activation!('qualificacao')
      expect(unsaved_state).to be_persisted
      expect(unsaved_state.active_playbook).to eq('qualificacao')
    end
  end

  describe '#record_trigger_activation!' do
    let(:state) { described_class.create!(account: account, conversation: conversation) }

    it 'sets active_playbook, activated_at, and activation_reason = :trigger' do
      freeze_time do
        result = state.record_trigger_activation!('duvida_comercial')

        expect(result).to eq(state)
        state.reload
        expect(state.active_playbook).to eq('duvida_comercial')
        expect(state.activated_at).to eq(Time.current)
        expect(state.activation_reason).to eq('trigger')
        expect(state.trigger?).to be true
      end
    end

    it 'persists an unsaved record when called from .for_conversation' do
      unsaved_state = described_class.for_conversation(conversation)
      expect(unsaved_state).not_to be_persisted

      unsaved_state.record_trigger_activation!('duvida_comercial')
      expect(unsaved_state).to be_persisted
      expect(unsaved_state.active_playbook).to eq('duvida_comercial')
      expect(unsaved_state.trigger?).to be true
    end
  end

  describe '#record_transition!' do
    let(:state) { described_class.create!(account: account, conversation: conversation) }

    context 'when turn_transition_count is under the cap (< 2)' do
      it 'performs the handoff for first transition (turn count 0)' do
        freeze_time do
          result = state.record_transition!('passo_2', turn_transition_count: 0)

          expect(result).to be true
          state.reload
          expect(state.active_playbook).to eq('passo_2')
          expect(state.activated_at).to eq(Time.current)
          expect(state.activation_reason).to eq('transition')
          expect(state.transition?).to be true
          expect(state.transition_count).to eq(1)
          expect(state.handoff_limit_reached_at).to be_nil
        end
      end

      it 'performs the handoff for second transition (turn count 1)' do
        state.update!(transition_count: 1, active_playbook: 'passo_2')

        result = state.record_transition!('passo_3', turn_transition_count: 1)

        expect(result).to be true
        state.reload
        expect(state.active_playbook).to eq('passo_3')
        expect(state.transition_count).to eq(2)
        expect(state.handoff_limit_reached_at).to be_nil
      end

      it 'leaves last_exit untouched' do
        state.update!(last_exit: 'prior_exit')

        state.record_transition!('passo_2', turn_transition_count: 0)
        state.reload

        expect(state.last_exit).to eq('prior_exit')
      end

      it 'adds completed to completed_playbooks in the same write with set semantics and keeps order' do
        state.update!(completed_playbooks: ['identificacao'])

        state.record_transition!('passo_2', turn_transition_count: 0, completed: 'qualificacao')
        state.reload

        expect(state.completed_playbooks).to eq(%w[identificacao qualificacao])
        expect(state.active_playbook).to eq('passo_2')
        expect(state.transition_count).to eq(1)

        state.record_transition!('passo_3', turn_transition_count: 1, completed: 'qualificacao')
        state.reload
        expect(state.completed_playbooks).to eq(%w[identificacao qualificacao])
      end

      it 'adds nothing to completed_playbooks when completed is nil' do
        state.update!(completed_playbooks: ['identificacao'])

        state.record_transition!('passo_2', turn_transition_count: 0, completed: nil)
        state.reload

        expect(state.completed_playbooks).to eq(['identificacao'])
      end
    end

    context 'when turn_transition_count reaches the cap (>= 2)' do
      it 'refuses third transition (turn count 2) and records handoff_limit_reached_at' do
        state.update!(active_playbook: 'passo_3', transition_count: 2)

        freeze_time do
          result = state.record_transition!('passo_4', turn_transition_count: 2)

          expect(result).to be false
          state.reload
          expect(state.active_playbook).to eq('passo_3')
          expect(state.transition_count).to eq(2)
          expect(state.handoff_limit_reached_at).to eq(Time.current)
        end
      end

      it 'refuses any count >= 2 and updates handoff_limit_reached_at' do
        state.update!(active_playbook: 'passo_3', transition_count: 5)

        freeze_time do
          result = state.record_transition!('passo_4', turn_transition_count: 3)

          expect(result).to be false
          state.reload
          expect(state.active_playbook).to eq('passo_3')
          expect(state.handoff_limit_reached_at).to eq(Time.current)
        end
      end

      it 'ignores completed: when transition is refused at cap' do
        state.update!(active_playbook: 'passo_3', transition_count: 2, completed_playbooks: ['identificacao'])

        result = state.record_transition!('passo_4', turn_transition_count: 2, completed: 'qualificacao')

        expect(result).to be false
        state.reload
        expect(state.completed_playbooks).to eq(['identificacao'])
      end
    end

    context 'with retry isolation' do
      it 'allows transition on fresh turn attempt (turn count 0) when cumulative count is high and preserves limit marker' do
        state.update!(active_playbook: 'passo_2', transition_count: 5, handoff_limit_reached_at: 1.day.ago)
        limit_marker = state.handoff_limit_reached_at

        result = state.record_transition!('passo_3', turn_transition_count: 0)

        expect(result).to be true
        state.reload
        expect(state.active_playbook).to eq('passo_3')
        expect(state.transition_count).to eq(6)
        expect(state.handoff_limit_reached_at).to be_within(1.second).of(limit_marker)
      end
    end
  end

  describe '#record_terminal_exit!' do
    let(:state) do
      described_class.create!(
        account: account,
        conversation: conversation,
        active_playbook: 'qualificacao',
        activated_at: 1.hour.ago,
        activation_reason: :state,
        last_exit: 'old_exit'
      )
    end

    it 'clears active playbook, activated_at, activation_reason and records last_exit' do
      state.record_terminal_exit!('agendado')
      state.reload

      expect(state.active_playbook).to be_nil
      expect(state.activated_at).to be_nil
      expect(state.activation_reason).to be_nil
      expect(state.last_exit).to eq('agendado')
    end

    it 'preserves last_exit when subsequently reactivated' do
      state.record_terminal_exit!('agendado')
      state.reload
      expect(state.last_exit).to eq('agendado')

      state.record_state_activation!('novo_playbook')
      state.reload

      expect(state.active_playbook).to eq('novo_playbook')
      expect(state.last_exit).to eq('agendado')
    end

    it 'adds completed to completed_playbooks in the same write with set semantics' do
      state.update!(completed_playbooks: ['identificacao'])

      state.record_terminal_exit!('agendado', completed: 'qualificacao')
      state.reload

      expect(state.completed_playbooks).to eq(%w[identificacao qualificacao])
      expect(state.active_playbook).to be_nil
      expect(state.last_exit).to eq('agendado')

      state.record_terminal_exit!('outro', completed: 'qualificacao')
      state.reload
      expect(state.completed_playbooks).to eq(%w[identificacao qualificacao])
    end

    it 'adds nothing to completed_playbooks when completed is nil' do
      state.update!(completed_playbooks: ['identificacao'])

      state.record_terminal_exit!('agendado', completed: nil)
      state.reload

      expect(state.completed_playbooks).to eq(['identificacao'])
    end
  end

  describe '#record_unsatisfied_items!' do
    let(:state) { described_class.create!(account: account, conversation: conversation) }

    it 'overwrites unsatisfied_flags with the given record' do
      record = {
        'procedure' => 'agendamento',
        'pending_fields' => [],
        'unmet_requires' => %w[scheduling customer_registry],
        'unmet_needs' => ['politica_reagendamento']
      }

      result = state.record_unsatisfied_items!(record)

      expect(result).to eq(state)
      state.reload
      expect(state.unsatisfied_flags).to eq(record)
    end

    it 'persists an unsaved record when called from .for_conversation' do
      unsaved_state = described_class.for_conversation(conversation)
      expect(unsaved_state).not_to be_persisted

      record = {
        'procedure' => nil,
        'pending_fields' => [],
        'unmet_requires' => [],
        'unmet_needs' => []
      }

      unsaved_state.record_unsatisfied_items!(record)
      expect(unsaved_state).to be_persisted
      expect(unsaved_state.unsatisfied_flags).to eq(record)
    end
  end
end
