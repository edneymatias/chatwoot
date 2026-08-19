# frozen_string_literal: true

class Custom::Scout::Tools::HandoverToHuman < Custom::Scout::Tools::BaseTool
  description 'Transfers the conversation to a human agent or team and stops AI responses'

  param :assignee_id, type: :integer, desc: 'ID of the specific human agent to assign', required: false
  param :team_id, type: :integer, desc: 'ID of the team to assign', required: false
  param :reason, type: :string, desc: 'Explanation of why the conversation is being transferred to a human', required: false

  attr_reader :handoff_executed

  def name
    'handover_to_human'
  end

  def execute(assignee_id: nil, team_id: nil, reason: nil)
    assign_team_and_user(assignee_id, team_id)
    perform_handoff
    create_transfer_note(reason) if reason.present?
    generate_contact_memory if scout.feature_memory?

    @handoff_executed = true
    'Conversation transferred to human queue successfully.'
  end

  private

  def assign_team_and_user(assignee_id, team_id)
    resolved_team_id = team_id.presence || scout.handover_team_id
    conversation.team_id = resolved_team_id if resolved_team_id.present?
    conversation.assignee_id = assignee_id if assignee_id.present?
    conversation.save!
  end

  def perform_handoff
    status = Conversation.uncached { Conversation.where(id: conversation.id).pick(:status) }
    conversation.bot_handoff! if status == 'pending' || status == Conversation.statuses[:pending]
  end

  def create_transfer_note(reason)
    Messages::MessageBuilder.new(
      nil,
      conversation,
      { content: "📋 Transferência para atendimento humano: #{reason}", private: true }
    ).perform
  end

  def generate_contact_memory
    Custom::Scout::ContactNotesService.new(scout, conversation).generate_and_update_notes
  end
end
