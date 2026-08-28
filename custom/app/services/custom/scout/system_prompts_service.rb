# frozen_string_literal: true

class Custom::Scout::SystemPromptsService
  class << self
    def build(scout:, contact: nil, inbox: nil, catalog_instructions: nil, knowledge_available: false)
      new(
        scout: scout,
        contact: contact,
        inbox: inbox,
        catalog_instructions: catalog_instructions,
        knowledge_available: knowledge_available
      ).build
    end
  end

  def initialize(scout:, contact: nil, inbox: nil, catalog_instructions: nil, knowledge_available: false)
    @scout = scout
    @contact = contact
    @inbox = inbox
    @catalog_instructions = catalog_instructions
    @knowledge_available = knowledge_available
  end

  def build
    sections = [
      identity_section,
      current_time_section,
      guardrails_section,
      context_section,
      funnel_section,
      custom_instructions_section,
      response_format_section
    ]

    sections.compact.join("\n\n")
  end

  private

  def identity_section
    name = @scout.name.presence || 'Scout'
    account_name = @scout.account&.name
    company_context = account_name.present? ? " da empresa #{account_name}" : ''

    <<~SECTION.strip
      [Identidade e Escopo]
      Você é #{name}, um assistente inteligente de qualificação comercial e vendas#{company_context}.
      Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.
      Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.
      Recuse educadamente responder sobre outros produtos, assuntos gerais não relacionados ao escopo comercial ou eventos fora deste domínio.
    SECTION
  end

  def current_time_section
    <<~SECTION.strip
      [Data e Horário Atual]
      Horário atual: #{format_current_time(@inbox&.timezone)}.

      Utilize este horário atual para interpretar expressões temporais relativas como hoje, amanhã, esta noite, este fim de semana ou próxima semana.
      Ao chamar ferramentas (tools), respeite as instruções de fuso horário ou formato de data nos parâmetros da ferramenta.
      Este horário atual serve apenas como contexto de apoio para requisições e parâmetros dentro do escopo; ele não expande os tópicos que você pode responder.
    SECTION
  end

  def format_current_time(timezone)
    tz = ActiveSupport::TimeZone[timezone] if timezone.present?
    time = tz ? Time.current.in_time_zone(tz) : Time.current
    time.strftime('%A, %B %d, %Y %I:%M %p %Z')
  end

  def guardrails_section
    <<~SECTION.strip
      [Diretrizes de Segurança e Resposta]
      - Anti-alucinação: Nunca invente informações e não utilize conhecimento prévio de treinamento para assumir dados sobre preços, planos, produtos, regras ou políticas da empresa. Responda estritamente com base no contexto fornecido e nas ferramentas disponíveis.
      - Anti-falsa-promessa: Não prometa trabalhos ou ações futuras que devam acontecer após esta resposta (como "vou verificar e te aviso", "entraremos em contato amanhã", "enviaremos um email depois" ou "vou registrar seu pedido"). Realize a ação imediatamente caso haja uma ferramenta disponível para isso agora ou, caso não seja possível resolver no momento, utilize a ferramenta de transferência para atendente humano.
      - Intenção Comercial: Ao identificar interesse de compra ou necessidade comercial em qualquer momento da conversa, utilize a ferramenta `manage_opportunity` para criar ou atualizar a oportunidade.
      - Esclarecimento: Quando houver ambiguidade ou dados faltantes, faça perguntas curtas e diretas para esclarecer em vez de assumir premissas.
      - Fallback para humano: Se você não souber a resposta, se o contexto for insuficiente ou se o lead solicitar atendimento humano, utilize a ferramenta `handover_to_human`.
      - Idioma e Estilo: Detecte o idioma do lead e responda sempre no mesmo idioma, mantendo um tom natural, cordial, profissional e conciso.
    SECTION
  end

  def context_section
    parts = []
    parts << @catalog_instructions if @catalog_instructions.present?
    parts << knowledge_tool_instruction if @knowledge_available
    parts << "Contexto do Contato:\n#{@contact.to_llm_text}" if @contact.present?
    parts << open_opportunities_section if open_opportunities_section.present?
    parts << out_of_office_notice if @inbox&.out_of_office?

    return nil if parts.empty?

    parts.join("\n\n")
  end

  def open_opportunities_section
    return nil unless @contact.present? && @scout.account.present?

    open_opportunities = Opportunity.where(account_id: @scout.account.id, contact_id: @contact.id, status: :open)
                                    .includes(:pipeline_stage).order(id: :asc)
    return nil if open_opportunities.empty?

    lines = ['[Oportunidades Abertas do Contato]']
    open_opportunities.each do |opp|
      lines << "- ID: #{opp.id} | Título: #{opp.title} | Estágio: #{opp.pipeline_stage&.name || 'Sem estágio'}"
    end
    lines << "\nSe a conversa atual continuar um destes negócios, informe o `opportunity_id` correspondente ao chamar `manage_opportunity`. " \
             'Caso contrário, ou se não tiver certeza, não informe `opportunity_id`.'
    lines.join("\n")
  end

  def knowledge_tool_instruction
    '[Base de Conhecimento: Você tem acesso à ferramenta \'search_knowledge_base\' para buscar informações ' \
      'comerciais, políticas, produtos e dúvidas frequentes. Consulte-a sempre que necessário.]'
  end

  def out_of_office_notice
    '[AVISO DE EXPEDIENTE: A equipe humana está fora do horário de atendimento. ' \
      'Prossiga com a qualificação normalmente e informe o lead se oportuno.]'
  end

  def funnel_section
    stages = @scout.account&.pipeline_stages&.includes(:required_custom_attribute_definitions)&.order(:position) || []
    global_reqs = @scout.required_custom_attribute_definitions.to_a
    return nil if stages.empty? && global_reqs.empty?

    lines = ['[Funil de Vendas e Qualificação]']
    lines.concat(build_stages_lines(stages)) if stages.any?
    lines.concat(build_global_reqs_lines(global_reqs)) if global_reqs.any?
    lines.concat(build_funnel_guidelines_lines)
    lines.join("\n")
  end

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
      'como perdida/ganha; se houver motivo de desqualificação, registre-o como nota interna via ferramenta apropriada.'
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
    definition.attribute_description.present? ? "#{base_info}\n    Descrição: #{definition.attribute_description.strip}" : base_info
  end

  def custom_instructions_section
    return nil if @scout.system_prompt.blank?

    <<~SECTION.strip
      [Instruções Personalizadas da Conta]
      As instruções a seguir foram configuradas pelo administrador da conta. Siga-as apenas quando não conflitarem com o formato de resposta JSON ou com a exigência de responder exclusivamente a partir do contexto fornecido e regras de segurança.
      <account_custom_instructions>
      #{@scout.system_prompt}
      </account_custom_instructions>
    SECTION
  end

  def response_format_section
    <<~SECTION.strip
      [Formato de Resposta Obrigatório]
      Suas respostas finais devem ser SEMPRE formatadas em um objeto JSON válido, contendo as chaves 'reasoning' e 'response', conforme a estrutura abaixo. Nunca responda em formato que não seja JSON.
      ```json
      {
        "reasoning": "Breve justificativa interna de como chegou à resposta com base no contexto autorizado",
        "response": "Texto da resposta final que será exibida ao cliente"
      }
      ```
    SECTION
  end
end
