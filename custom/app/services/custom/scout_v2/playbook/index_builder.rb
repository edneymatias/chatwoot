# frozen_string_literal: true

class Custom::ScoutV2::Playbook::IndexBuilder
  EMPTY_CATALOG_LINE = 'Nenhum procedimento específico habilitado no catálogo.'

  class << self
    def call(catalog)
      new(catalog).call
    end
  end

  def initialize(catalog)
    @catalog = catalog
  end

  def call
    playbooks = @catalog.playbooks

    if playbooks.blank?
      <<~SECTION.strip
        [Playbook Index]
        #{EMPTY_CATALOG_LINE}
      SECTION
    else
      lines = playbooks.map { |pb| "- #{pb.name}: #{pb.trigger.squish}" }
      <<~SECTION.strip
        [Playbook Index]
        #{lines.join("\n")}
      SECTION
    end
  end
end
