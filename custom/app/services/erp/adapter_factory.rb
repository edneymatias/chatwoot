# frozen_string_literal: true

class Erp::AdapterFactory
  def self.build(hook)
    case hook.app_id
    when 'younus'
      Erp::Younus::Adapter.new(hook)
    else
      raise ArgumentError, "Unsupported ERP provider: #{hook.app_id}"
    end
  end
end
