module Custom
  module AutomationRuleListener
    def opportunity_created(event)
      process_opportunity_event(event, 'opportunity_created')
    end

    def opportunity_updated(event)
      process_opportunity_event(event, 'opportunity_updated')
    end

    def opportunity_stage_changed(event)
      process_opportunity_event(event, 'opportunity_stage_changed')
    end

    def opportunity_won(event)
      process_opportunity_event(event, 'opportunity_won')
    end

    def opportunity_lost(event)
      process_opportunity_event(event, 'opportunity_lost')
    end

    def opportunity_reopened(event)
      process_opportunity_event(event, 'opportunity_reopened')
    end

    private

    def process_opportunity_event(event, event_name)
      return if performed_by_automation?(event)

      opportunity = event.data[:opportunity]
      return if opportunity.blank?

      account = opportunity.account
      return unless rule_present?(event_name, account)

      changed_attributes = event.data[:changed_attributes]
      from_pipeline_stage_id = event.data[:from_pipeline_stage_id]

      rules = current_account_rules(event_name, account)

      rules.each do |rule|
        options = { changed_attributes: changed_attributes, from_pipeline_stage_id: from_pipeline_stage_id }
        conditions_match = Custom::AutomationRules::OpportunityConditionsFilterService.new(rule, opportunity, options).perform
        Custom::AutomationRules::OpportunityActionService.new(rule, account, opportunity).perform if conditions_match.present?
      end
    end
  end
end
