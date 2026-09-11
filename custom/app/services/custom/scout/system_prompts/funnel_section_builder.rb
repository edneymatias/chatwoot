# frozen_string_literal: true

class Custom::Scout::SystemPrompts::FunnelSectionBuilder
  def initialize(scout:)
    @scout = scout
  end

  def build
    stages = @scout.account&.pipeline_stages&.includes(:required_custom_attribute_definitions)&.order(:position) || []
    global_reqs = @scout.required_custom_attribute_definitions.to_a
    return nil if stages.empty? && global_reqs.empty?

    lines = ['[Funil de Vendas e Qualificação]']
    lines.concat(build_stages_lines(stages)) if stages.any?
    lines.concat(build_global_reqs_lines(global_reqs)) if global_reqs.any?
    lines.concat(build_funnel_guidelines_lines)
    lines.join("\n")
  end

  private

  def build_stages_lines(stages)
    ['Estágios do Funil disponíveis para esta conta:', *stages.map { |stage| format_stage(stage) }]
  end

  def build_global_reqs_lines(global_reqs)
    ["\nRequisitos Globais de Qualificação (obrigatórios para mover para o estágio de qualificação):",
     *global_reqs.map { |definition| format_attribute_definition(definition) }]
  end

  def build_funnel_guidelines_lines
    [
      "\nDiretrizes Operacionais de Funil:",
      '- Ao mover a oportunidade para o estágio qualificado, a transferência (handoff) para a equipe humana é realizada ' \
      'automaticamente. Não execute `handover_to_human` separadamente ao qualificar.',
      '- O estágio de desqualificação representa uma fila de revisão humana, não o fechamento do negócio. Nunca marque a oportunidade ' \
      'como perdida/ganha; se houver motivo de desqualificação, registre-o como nota interna via ferramenta apropriada.',
      '- Compare o resultado observável de cada turno com as descrições dos estágios disponíveis: se o desfecho da conversa corresponder ' \
      'claramente ao critério descrito para um estágio (ex: recusa/adiamento correspondendo à desqualificação, ou confirmação com todos ' \
      'os dados correspondendo à qualificação), mova a oportunidade para esse estágio no próprio turno. Havendo correspondência com mais ' \
      'de um estágio, escolha a descrição mais específica ao desfecho. A transição automática por desfecho é estritamente progressiva: ' \
      'nunca retorne uma oportunidade que já atingiu o estágio qualificado para estágios anteriores ou para desqualificação.',
      '- Suas ferramentas de oportunidade (`manage_opportunity`, `move_opportunity_stage`) são suficientes para registrar qualquer dado ' \
      'de qualificação fornecido pelo lead, incluindo datas, horários e agendamentos. Nunca conclua que falta uma ferramenta de ' \
      'agendamento ou transfira para humano por esse motivo quando o lead já forneceu as informações necessárias.',
      '- Limite suas perguntas de qualificação aos campos configurados acima. Não invente perguntas adicionais fora dos campos ' \
      'configurados para parecer mais completo ou por causa de conteúdo da base de conhecimento — cada pergunta extra custa um ' \
      'turno a mais ao lead e à operação. Se o cliente fornecer informação a mais por conta própria, reconheça brevemente, sem ' \
      'abrir uma nova linha de investigação.'
    ]
  end

  def format_stage(stage)
    lines = ["- ID: #{stage.id} | Nome: #{stage.name}#{stage_role_label(stage)}"]
    lines << "  Descrição do estágio: #{stage.description.strip}" if stage.description.present?
    if stage.required_custom_attribute_definitions.any?
      lines << '  Campos obrigatórios para avançar para este estágio:'
      stage.required_custom_attribute_definitions.each { |defn| lines << "    #{format_attribute_definition(defn)}" }
    end
    lines.join("\n")
  end

  def stage_role_label(stage)
    case stage.id
    when @scout.default_pipeline_stage_id then ' (Estágio Inicial/Padrão)'
    when @scout.qualified_stage_id then ' (Estágio Qualificado)'
    when @scout.unqualified_stage_id then ' (Estágio Desqualificado / Revisão Humana)'
    else ''
    end
  end

  def format_attribute_definition(definition)
    type_info = definition.attribute_display_type
    values_info = ", Valores permitidos: #{Array(definition.attribute_values).join(', ')}" if definition.list? && definition.attribute_values.present?
    base_info = "- #{definition.attribute_display_name} (Chave: #{definition.attribute_key}, Tipo: #{type_info}#{values_info})"
    base_info += "\n    (uso interno; não cite nem exemplifique estes valores)" if definition.list? && definition.attribute_values.present?
    definition.attribute_description.present? ? "#{base_info}\n    Descrição: #{definition.attribute_description.strip}" : base_info
  end
end
