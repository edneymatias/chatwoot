# frozen_string_literal: true

class Custom::ScoutV2::Instructions::CommunicationBuilder
  TONE_DIRECTIVES = {
    'friendly' => 'Mantenha um tom amigável, acolhedor e empático na comunicação.',
    'neutral' => 'Mantenha um tom neutro, equilibrado e objetivo na comunicação.',
    'matter_of_fact' => 'Mantenha um tom direto ao ponto, factual e pragmático na comunicação.',
    'professional' => 'Mantenha um tom profissional, polido e formal na comunicação.',
    'humorous' => 'Mantenha um tom bem-humorado, leve e descontraído na comunicação.'
  }.freeze

  RESPONSE_LENGTH_DIRECTIVES = {
    'concise' => 'Seja conciso nas respostas, fornecendo apenas as informações essenciais.',
    'standard' => 'Forneça respostas com extensão padrão, equilibrando clareza e completude.',
    'thorough' => 'Forneça respostas detalhadas e completas, aprofundando as explicações necessárias.'
  }.freeze

  class << self
    def call(scout:)
      new(scout: scout).call
    end
  end

  def initialize(scout:)
    @scout = scout
  end

  def call
    tone_directive = TONE_DIRECTIVES[@scout.tone]
    length_directive = RESPONSE_LENGTH_DIRECTIVES[@scout.response_length]

    <<~SECTION.strip
      [Communication]
      - #{tone_directive}
      - #{length_directive}
      - #{greeting_directive}
    SECTION
  end

  private

  def greeting_directive
    greeting = if @scout.greeting.present?
                 "cumprimente o cliente utilizando a seguinte saudação: \"#{@scout.greeting.squish}\""
               else
                 'cumprimente o cliente de forma educada'
               end
    "Na primeira resposta da conversa, #{greeting}. Não repita a saudação nas respostas seguintes."
  end
end
