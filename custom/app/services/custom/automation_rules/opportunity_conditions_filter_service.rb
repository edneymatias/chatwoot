# frozen_string_literal: true

class Custom::AutomationRules::OpportunityConditionsFilterService
  def initialize(rule, opportunity, options = {})
    @rule = rule
    @opportunity = opportunity
    @account = opportunity.account
    @options = options
    @conversation = opportunity.active_conversation || opportunity.origin_conversation
    @contact = opportunity.contact
  end

  def perform
    return false unless rule_valid?
    return true if @rule.conditions.blank?

    evaluate_conditions
  rescue StandardError => e
    Rails.logger.error "Error in OpportunityConditionsFilterService: #{e.message}"
    false
  end

  private

  def rule_valid?
    return true if @rule.conditions.blank?

    @rule.conditions.all? do |condition|
      valid_query_operator?(condition)
    end
  end

  def valid_query_operator?(condition)
    query_operator = condition['query_operator']
    return true if query_operator.blank?

    %w[AND OR].include?(query_operator.to_s.upcase)
  end

  def evaluate_conditions
    result = nil

    @rule.conditions.each_with_index do |condition, index|
      condition_match = evaluate_single_condition(condition.with_indifferent_access)
      query_operator = condition['query_operator']&.downcase || 'and'

      result = if index.zero?
                 condition_match
               elsif query_operator == 'or'
                 result || condition_match
               else
                 result && condition_match
               end
    end

    result || false
  end

  def evaluate_single_condition(condition)
    key = condition[:attribute_key].to_s
    operator = condition[:filter_operator].to_s
    values = condition[:values]

    value = extract_attribute_value(key)
    match_operator(value, operator, values)
  end

  def extract_attribute_value(key)
    extract_opportunity_attr(key) ||
      extract_contact_attr(key) ||
      extract_conversation_attr(key) ||
      extract_custom_attribute_value(key)
  end

  def extract_opportunity_attr(key)
    extract_pipeline_attr(key) || extract_deal_attr(key)
  end

  def extract_pipeline_attr(key)
    case key
    when 'pipeline_id' then @opportunity.pipeline_stage&.pipeline_id&.to_s
    when 'pipeline_stage_id' then @opportunity.pipeline_stage_id&.to_s
    when 'from_pipeline_stage_id' then extract_from_stage_id
    end
  end

  def extract_deal_attr(key)
    case key
    when 'status' then @opportunity.status.to_s
    when 'value' then @opportunity.value
    when 'assignee_id' then @opportunity.assignee_id&.to_s
    when 'loss_reason'
      @opportunity.custom_attributes&.dig('loss_reason') || @opportunity.try(:loss_reason)
    end
  end

  def extract_contact_attr(key)
    return nil unless @contact

    case key
    when 'name', 'contact_name' then @contact.name
    when 'email', 'contact_email' then @contact.email
    when 'phone_number', 'contact_phone_number' then @contact.phone_number
    when 'company_name', 'contact_company_name' then @contact.additional_attributes&.dig('company_name')
    when 'country_code', 'contact_country_code' then @contact.additional_attributes&.dig('country_code')
    when 'city', 'contact_city' then @contact.additional_attributes&.dig('city')
    end
  end

  def extract_conversation_attr(key)
    return nil unless @conversation

    case key
    when 'inbox_id' then @conversation.inbox_id&.to_s
    when 'conversation_status' then @conversation.status.to_s
    when 'priority', 'conversation_priority' then @conversation.priority.to_s
    when 'labels' then @conversation.tag_list
    end
  end

  def extract_from_stage_id
    from_id = @options[:from_pipeline_stage_id] || @options.dig(:changed_attributes, 'pipeline_stage_id', 0)
    from_id&.to_s
  end

  def extract_custom_attribute_value(key)
    if @opportunity.custom_attributes&.key?(key)
      @opportunity.custom_attributes[key]
    elsif @contact&.custom_attributes&.key?(key)
      @contact.custom_attributes[key]
    elsif @conversation&.custom_attributes&.key?(key)
      @conversation.custom_attributes[key]
    end
  end

  def match_operator(value, operator, target_values)
    targets = Array(target_values).map(&:to_s)
    str_val = value.is_a?(Array) ? value.map(&:to_s) : value.to_s

    match_equality_ops(value, str_val, operator, targets) ||
      match_text_ops(str_val, operator, targets) ||
      match_numeric_ops(value, operator, targets)
  end

  def match_equality_ops(value, str_val, operator, targets)
    case operator
    when 'equal_to' then match_equality(str_val, targets)
    when 'not_equal_to' then !match_equality(str_val, targets)
    when 'is_present' then value.present?
    when 'is_not_present' then value.blank?
    end
  end

  def match_text_ops(str_val, operator, targets)
    case operator
    when 'contains'
      str_val.to_s.downcase.include?(targets.first.to_s.downcase)
    when 'does_not_contain'
      str_val.to_s.downcase.exclude?(targets.first.to_s.downcase)
    when 'starts_with'
      str_val.to_s.downcase.start_with?(targets.first.to_s.downcase)
    end
  end

  def match_numeric_ops(value, operator, targets)
    case operator
    when 'greater_than'
      value.to_f > targets.first.to_f
    when 'less_than'
      value.to_f < targets.first.to_f
    else
      false
    end
  end

  def match_equality(actual, targets)
    if actual.is_a?(Array)
      targets.any? { |t| actual.include?(t) }
    else
      targets.include?(actual)
    end
  end
end
