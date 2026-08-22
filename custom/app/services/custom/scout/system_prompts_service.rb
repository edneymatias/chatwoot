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
    parts << out_of_office_notice if @inbox&.out_of_office?

    return nil if parts.empty?

    parts.join("\n\n")
  end

  def knowledge_tool_instruction
    '[Base de Conhecimento: Você tem acesso à ferramenta \'search_knowledge_base\' para buscar informações ' \
      'comerciais, políticas, produtos e dúvidas frequentes. Consulte-a sempre que necessário.]'
  end

  def out_of_office_notice
    '[AVISO DE EXPEDIENTE: A equipe humana está fora do horário de atendimento. ' \
      'Prossiga com a qualificação normalmente e informe o lead se oportuno.]'
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
