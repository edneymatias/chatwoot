# frozen_string_literal: true

class Custom::ScoutV2::Predicates::Base
  def call(_ctx, _arg = nil)
    raise NotImplementedError, "#{self.class.name} must implement #call(ctx, arg = nil)"
  end
end
