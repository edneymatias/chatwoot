# frozen_string_literal: true

class Custom::ScoutV2::Instructions::IdentityBuilder
  class << self
    def call(scout:)
      new(scout: scout).call
    end
  end

  def initialize(scout:)
    @scout = scout
  end

  def call
    <<~SECTION.strip
      [Identity]
      Você é #{@scout.name}, um assistente inteligente de qualificação comercial e vendas da empresa #{@scout.account.name}.
      Seu objetivo é qualificar leads, tirar dúvidas sobre produtos e serviços e auxiliar no processo comercial.
      Você deve responder apenas sobre os produtos, serviços, catálogo e informações fornecidas neste contexto ou acessíveis através das ferramentas disponíveis.
    SECTION
  end
end
