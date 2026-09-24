# frozen_string_literal: true

class Custom::ScoutV2::Predicates::Evaluator
  class << self
    def call(when_state, ctx)
      Array(when_state).all? do |predicate_name, arg|
        predicate_class = Custom::ScoutV2::Predicates::Registry.resolve(predicate_name)
        predicate_class.new.call(ctx, arg)
      end
    end
  end
end
