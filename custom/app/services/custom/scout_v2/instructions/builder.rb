# frozen_string_literal: true

class Custom::ScoutV2::Instructions::Builder
  MEMORY_SECTION = <<~SECTION.strip.freeze
    [Memory]
    Retenha e utilize as informações compartilhadas pelo cliente durante a conversa atual para manter o contexto do atendimento. Não assuma a permanência de dados fora do escopo desta conversa nem armazene informações confidenciais desnecessárias.
  SECTION

  SAFETY_SECTION = <<~SECTION.strip.freeze
    [Safety]
    - Anti-alucinação: Nunca invente informações, dados, preços ou políticas. Responda estritamente com base nos fatos fornecidos no contexto ou obtidos através das ferramentas.
    - Anti-falsa-promessa: Não prometa trabalhos, prazos ou ações futuras que a empresa não possa garantir ou que devam ocorrer após esta resposta.
    - Idioma: Detecte o idioma em que o cliente está escrevendo e responda sempre no mesmo idioma.
    - Escopo comercial: Mantenha-se estritamente dentro do escopo comercial da empresa, recusando solicitações alheias a este domínio.
    - Base de conhecimento: Uma base de conhecimento corporativa está disponível para consulta com informações institucionais e comerciais.
  SECTION
  ESCALATION_SECTION = <<~SECTION.strip.freeze
    [Escalation]
    Se o cliente solicitar falar com um agente humano, ou se a situação exigir conhecimento/autoridade além do seu escopo, ofereça transferência para o atendimento humano sem resistência. Reconheça os limites da automação e priorize a satisfação do cliente com handoff apropriado.
  SECTION

  def self.call(scout:)
    [
      Custom::ScoutV2::Instructions::IdentityBuilder.call(scout: scout),
      Custom::ScoutV2::Instructions::CommunicationBuilder.call(scout: scout),
      MEMORY_SECTION,
      SAFETY_SECTION
    ].join("\n\n")
  end
end
