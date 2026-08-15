module Custom
  module AutomationRules
    class OpportunityConditionsFilterService
      def initialize(rule, opportunity, options = {})
        @rule = rule
        @opportunity = opportunity
        @account = opportunity.account
        @options = options
        @conversation = opportunity.origin_conversation
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
        case key
        when 'pipeline_id'
          @opportunity.pipeline_stage&.pipeline_id&.to_s
        when 'pipeline_stage_id'
          @opportunity.pipeline_stage_id&.to_s
        when 'from_pipeline_stage_id'
          extract_from_stage_id
        when 'status'
          @opportunity.status.to_s
        when 'value'
          @opportunity.value
        when 'assignee_id'
          @opportunity.assignee_id&.to_s
        when 'loss_reason'
          @opportunity.custom_attributes&.dig('loss_reason') || @opportunity.try(:loss_reason)
        when 'name', 'contact_name'
          @contact&.name
        when 'email', 'contact_email'
          @contact&.email
        when 'phone_number', 'contact_phone_number'
          @contact&.phone_number
        when 'company_name', 'contact_company_name'
          @contact&.additional_attributes&.dig('company_name')
        when 'country_code', 'contact_country_code'
          @contact&.additional_attributes&.dig('country_code')
        when 'city', 'contact_city'
          @contact&.additional_attributes&.dig('city')
        when 'inbox_id'
          @conversation&.inbox_id&.to_s
        when 'conversation_status'
          @conversation&.status.to_s
        when 'priority', 'conversation_priority'
          @conversation&.priority.to_s
        when 'labels'
          @conversation.present? ? @conversation.tag_list : []
        else
          extract_custom_attribute_value(key)
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

        case operator
        when 'equal_to'
          match_equality(str_val, targets)
        when 'not_equal_to'
          !match_equality(str_val, targets)
        when 'contains'
          str_val.to_s.downcase.include?(targets.first.to_s.downcase)
        when 'does_not_contain'
          !str_val.to_s.downcase.include?(targets.first.to_s.downcase)
        when 'is_present'
          value.present?
        when 'is_not_present'
          value.blank?
        when 'greater_than'
          value.to_f > targets.first.to_f
        when 'less_than'
          value.to_f < targets.first.to_f
        when 'starts_with'
          str_val.to_s.downcase.start_with?(targets.first.to_s.downcase)
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
  end
end
