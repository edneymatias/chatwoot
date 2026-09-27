# frozen_string_literal: true

class Custom::ScoutV2::Instructions::IdentityBuilder
  DEFAULT_PURPOSE = 'Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.'
  DEFAULT_SCOPE = (
    'Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ' \
      'ou acessíveis através das ferramentas disponíveis.'
  )

  class << self
    def call(scout:)
      new(scout: scout).call
    end
  end

  def initialize(scout:)
    @scout = scout
  end

  def call
    lines = ['[Identity]']
    lines << intro_statement
    lines << purpose_statement
    lines << scope_statement
    lines.join("\n")
  end

  private

  def intro_statement
    if @scout.role.present?
      "Você é #{@scout.name}, assistente da empresa #{@scout.account.name}."
    else
      "Você é #{@scout.name}, um assistente inteligente de qualificação comercial e vendas da empresa #{@scout.account.name}."
    end
  end

  def purpose_statement
    @scout.role.presence || DEFAULT_PURPOSE
  end

  def scope_statement
    @scout.scope.presence || DEFAULT_SCOPE
  end
end
