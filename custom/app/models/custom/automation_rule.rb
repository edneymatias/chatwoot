module Custom::AutomationRule
  def actions_attributes
    super + %w[create_opportunity]
  end
end
