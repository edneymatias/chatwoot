# frozen_string_literal: true

class Custom::Scout::Tools::HandoverToHuman < Custom::Scout::Tools::BaseTool
  description 'Transfers the conversation to a human agent or team and stops AI responses'

  param :assignee_id, type: :integer, desc: 'ID of the specific human agent to assign', required: false
  param :team_id, type: :integer, desc: 'ID of the team to assign', required: false
  param :reason, type: :string, desc: 'Explanation of why the conversation is being transferred to a human', required: false

  attr_reader :handoff_needed, :handoff_assignee_id, :handoff_team_id, :handoff_reason

  def name
    'handover_to_human'
  end

  def execute(assignee_id: nil, team_id: nil, reason: nil)
    if playground?
      return "[Simulado] Atendimento transferido para humano#{reason.present? ? " (Motivo: #{reason})" : ''}."
    end

    @handoff_needed = true
    @handoff_assignee_id = assignee_id
    @handoff_team_id = team_id
    @handoff_reason = reason

    'A transferência será confirmada após sua resposta final. Escreva agora uma mensagem natural de encerramento, sem perguntas.'
  end
end
