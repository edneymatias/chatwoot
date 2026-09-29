# frozen_string_literal: true

class Custom::ScoutV2::Predicates::PlaybookNotCompleted
  def call(ctx, arg = nil)
    return true if arg.blank?

    ctx.completed_playbooks.map(&:to_s).exclude?(arg.to_s)
  end
end
