# frozen_string_literal: true

class Custom::Scout::SystemPromptsService
  class << self
    def build(scout:, contact: nil, inbox: nil, catalog_instructions: nil, knowledge_available: false)
      new(scout: scout, contact: contact, inbox: inbox, catalog_instructions: catalog_instructions, knowledge_available: knowledge_available).build
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
      handoff_closing_reminder_section,
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
      - Confirmação de ação: Sempre que executar com sucesso uma ferramenta de registro ou atualização (ex: `manage_opportunity`, `update_contact`), reconheça o que aconteceu usando escuta ativa — técnica comum em vendas consultivas de refletir de volta, com suas próprias palavras, apenas a informação nova desta mensagem do cliente, antes de prosseguir com novas perguntas. Nunca execute uma ação e siga direto para a próxima pergunta sem reconhecer o que o cliente disse. Nunca repita ou resuma de novo, em turnos seguintes, dados que você já reconheceu anteriormente na mesma conversa — mesmo que continuem registrados, reafirmá-los de novo soa repetitivo e inseguro. Use linguagem natural e humana, sem expor identificadores internos (como IDs numéricos), nomes técnicos de atributos ou jargões de log de sistema. Nunca diga que "abriu um atendimento", "abriu uma oportunidade" ou "registrou um chamado" — narrar a ação de bastidores em si soa como um sistema, não como uma pessoa; reflita apenas o que é relevante para o cliente (ex: cliente expressa interesse em algo específico → reconheça esse interesse nominalmente e com entusiasmo, nunca com frases de log como "Perfeito, anotei que seu interesse é em X.").
      - Intenção Comercial: Ao identificar interesse de compra ou necessidade comercial em qualquer momento da conversa, utilize a ferramenta `manage_opportunity` para criar ou atualizar a oportunidade.
      - Esclarecimento: Quando houver ambiguidade ou dados faltantes, faça perguntas curtas e diretas para esclarecer em vez de assumir premissas. Ao solicitar um dado que possua lista de opções predefinidas, formule uma pergunta totalmente aberta (ex: "Como você nos encontrou?"), sem mencionar, exemplificar ou sugerir nenhum dos valores configurados na pergunta — nem mesmo entre parênteses como exemplo — mapeando a resposta livre do lead internamente para o valor correspondente.
      - Ritmo e condução da conversa: Faça no máximo uma pergunta por resposta para não sobrecarregar o lead. Sempre que compartilhar informações relevantes, encerre a resposta com uma pergunta ou próximo passo objetivo para manter a conversa em movimento, exceto quando o lead tiver sinalizado pausa ou encerramento.
      - Respeito ao ritmo do lead: Quando o lead sinalizar que quer pausar ou encerrar a conversa por ora (ex: "vou ver e te aviso", "depois eu volto", "obrigado"), não reintroduza perguntas de qualificação pendentes nesse turno. Apenas confirme educadamente, deixe a porta aberta para o retorno e encerre o turno.
      - Fallback para humano: Se você não souber a resposta, se o contexto for insuficiente ou se o lead solicitar atendimento humano, utilize a ferramenta `handover_to_human`. Sempre que um turno terminar em transferência (por chamada de ferramenta ou qualificação), sua resposta final deve ser uma mensagem natural de encerramento, confirmando o que foi registrado e explicando que um atendente continuará o atendimento — nunca faça perguntas ao transferir.
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
    Custom::Scout::SystemPrompts::FunnelSectionBuilder.new(scout: @scout).build
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

  # Repeats the "Fallback para humano" no-question rule right before the response format
  # instructions, closest to where the model actually writes its final turn text — a static
  # system-prompt bullet read many messages earlier is not salient enough on its own (see
  # OpportunityStageTransitionService::NO_QUESTION_CLOSING_INSTRUCTION for the companion
  # just-in-time reinforcement delivered via the tool result itself).
  def handoff_closing_reminder_section
    <<~SECTION.strip
      [Lembrete de Encerramento]
      Se este turno terminar em transferência para humano — por ter chamado `handover_to_human` ou porque a oportunidade acabou de ser movida para o estágio qualificado — sua resposta final não pode conter nenhuma pergunta ao cliente, mesmo que pareça natural continuar perguntando algo.
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
