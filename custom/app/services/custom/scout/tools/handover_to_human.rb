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
    @handoff_executed = true
    if playground?
      return "[Simulado] Atendimento transferido para humano#{reason.present? ? " (Motivo: #{reason})" : ''}."
    end

    Custom::Scout::HandoffService.new(
      scout: scout,
      conversation: conversation
    ).perform(
      assignee_id: assignee_id,
      team_id: team_id,
      reason: reason
    )
  end
end
