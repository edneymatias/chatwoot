# frozen_string_literal: true

class ScoutConversationState < ApplicationRecord
  self.table_name = 'ichatr_scout_conversation_states'

  belongs_to :account
  belongs_to :conversation

  enum :activation_reason, { state: 0, trigger: 1, transition: 2 }, scopes: false

  validates :account_id, presence: true
  validates :conversation_id, presence: true, uniqueness: true
  validates :transition_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.for_conversation(conversation)
    find_or_initialize_by(conversation_id: conversation.id) do |state|
      state.account_id = conversation.account_id
    end
  end

  def record_state_activation!(playbook_name)
    update!(
      active_playbook: playbook_name,
      activated_at: Time.current,
      activation_reason: :state
    )
    self
  end

  def record_trigger_activation!(playbook_name)
    update!(
      active_playbook: playbook_name,
      activated_at: Time.current,
      activation_reason: :trigger
    )
    self
  end

  def record_transition!(target_playbook_name, turn_transition_count:, completed: nil)
    if turn_transition_count >= 2
      update!(handoff_limit_reached_at: Time.current)
      false
    else
      update!(
        active_playbook: target_playbook_name,
        activated_at: Time.current,
        activation_reason: :transition,
        transition_count: transition_count + 1,
        completed_playbooks: updated_completed_playbooks(completed)
      )
      true
    end
  end

  def record_terminal_exit!(exit_name, completed: nil)
    update!(
      active_playbook: nil,
      activated_at: nil,
      activation_reason: nil,
      last_exit: exit_name,
      completed_playbooks: updated_completed_playbooks(completed)
    )
    self
  end

  def record_unsatisfied_items!(record)
    update!(unsatisfied_flags: record)
    self
  end

  def remember_customer!(id:, name:)
    update!(capability_state: capability_state.merge(
      'customer' => {
        'id' => id.to_s,
        'name' => name
      }
    ))
    self
  end

  def remember_slots!(slots)
    current_slots = capability_state['offered_slots'] || {}
    update!(capability_state: capability_state.merge(
      'offered_slots' => current_slots.merge(slots.transform_keys(&:to_s))
    ))
    self
  end

  def remember_booking!(appointment_id:, starts_at:)
    update!(capability_state: capability_state.merge(
      'booking' => {
        'appointment_id' => appointment_id.to_s,
        'starts_at' => starts_at
      }
    ))
    self
  end

  private

  def updated_completed_playbooks(completed)
    return completed_playbooks if completed.blank?

    (completed_playbooks + [completed.to_s]).uniq
  end
end
