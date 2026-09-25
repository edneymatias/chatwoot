# frozen_string_literal: true

class Custom::ScoutV2::Router
  Decision = Data.define(:playbook, :confidence)

  def self.call(ctx, catalog)
    new(ctx, catalog).call
  end

  def initialize(ctx, catalog)
    @ctx = ctx
    @catalog = catalog
  end

  def call
    winner = find_matching_playbook
    active = @ctx.active_playbook

    selected = resolve_selected_playbook(winner, active)
    confidence = selected.nil? ? nil : 1.0

    Decision.new(playbook: selected, confidence: confidence)
  end

  private

  def find_matching_playbook
    @catalog.ordered_by_priority.find do |playbook|
      playbook.when_state.present? && Custom::ScoutV2::Predicates::Evaluator.call(playbook.when_state, @ctx)
    end
  end

  def resolve_selected_playbook(winner, active)
    if winner.present? && (active.nil? || winner.name == active.name || winner.priority > active.priority)
      winner
    else
      active
    end
  end
end
