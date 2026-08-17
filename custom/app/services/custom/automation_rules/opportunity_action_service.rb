class Custom::AutomationRules::OpportunityActionService
  def initialize(rule, account, opportunity)
    @rule = rule
    @account = account
    @opportunity = opportunity
    @conversation = opportunity.active_conversation || opportunity.origin_conversation
    @contact = opportunity.contact
    Current.executed_by = rule
  end

  def perform
    @rule.actions.each do |action|
      reload_entities
      action = action.with_indifferent_access
      begin
        send(action[:action_name], action[:action_params]) if respond_to?(action[:action_name], true)
      rescue StandardError => e
        ChatwootExceptionTracker.new(e, account: @account).capture_exception
      end
    end
  ensure
    Current.reset
  end

  private

  def reload_entities
    @opportunity.reload if @opportunity.persisted?
    @contact&.reload if @contact&.persisted?
    @conversation&.reload if @conversation&.persisted?
  end

  # Opportunity Actions
  def update_opportunity_stage(params)
    stage_id = params.is_a?(Array) ? params[0] : params
    @opportunity.update!(pipeline_stage_id: stage_id)
  end

  def update_opportunity_assignee(params)
    assignee_id = params.is_a?(Array) ? params[0] : params
    assignee_id = nil if assignee_id.blank? || assignee_id == 'nil'
    @opportunity.update!(assignee_id: assignee_id)
  end

  def update_opportunity_status(params)
    status = params.is_a?(Array) ? params[0] : params
    @opportunity.update!(status: status)
  end

  def update_opportunity_value(params)
    val = params.is_a?(Array) ? params[0] : params
    @opportunity.update!(value: val)
  end

  def update_opportunity_custom_attribute(params)
    key, value = extract_custom_attribute_key_value(params)
    return if key.blank?

    attrs = (@opportunity.custom_attributes || {}).dup
    attrs[key] = value
    @opportunity.update!(custom_attributes: attrs)
  end

  # Contact Actions
  def update_contact_attribute(params)
    return unless @contact

    key, value = extract_custom_attribute_key_value(params)
    return if key.blank?

    if @contact.respond_to?("#{key}=")
      @contact.update!(key => value)
    else
      attrs = (@contact.additional_attributes || {}).dup
      attrs[key] = value
      @contact.update!(additional_attributes: attrs)
    end
  end

  def update_contact_custom_attribute(params)
    return unless @contact

    key, value = extract_custom_attribute_key_value(params)
    return if key.blank?

    attrs = (@contact.custom_attributes || {}).dup
    attrs[key] = value
    @contact.update!(custom_attributes: attrs)
  end

  # Conversation Actions (Safe Fallback if conversation is nil)
  def send_message(message)
    return unless @conversation

    params = { content: message[0], private: false, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_private_note(message)
    return unless @conversation

    params = { content: message[0], private: true, content_attributes: { automation_rule_id: @rule.id } }
    Messages::MessageBuilder.new(nil, @conversation, params).perform
  end

  def add_label(labels)
    return unless @conversation

    @conversation.add_labels(labels[0])
  end

  def remove_label(labels)
    return unless @conversation

    labels_to_remove = labels[0]
    @conversation.remove_labels(labels_to_remove)
  end

  def assign_agent(params)
    return unless @conversation

    agent_id = params[0]
    @conversation.update(assignee_id: agent_id)
  end

  def assign_team(params)
    return unless @conversation

    team_id = params[0]
    @conversation.update(team_id: team_id)
  end

  def remove_assigned_agent(_params = nil)
    return unless @conversation

    @conversation.update(assignee_id: nil)
  end

  def remove_assigned_team(_params = nil)
    return unless @conversation

    @conversation.update(team_id: nil)
  end

  def resolve_conversation(_params = nil)
    return unless @conversation

    @conversation.update(status: :resolved)
  end

  def open_conversation(_params = nil)
    return unless @conversation

    @conversation.update(status: :open)
  end

  def snooze_conversation(_params = nil)
    return unless @conversation

    @conversation.update(status: :snoozed, snoozed_until: 1.day.from_now)
  end

  def pending_conversation(_params = nil)
    return unless @conversation

    @conversation.update(status: :pending)
  end

  def change_priority(params)
    return unless @conversation

    priority = params[0]
    @conversation.update(priority: priority)
  end

  def update_conversation_custom_attribute(params)
    return unless @conversation

    key, value = extract_custom_attribute_key_value(params)
    return if key.blank?

    attrs = (@conversation.custom_attributes || {}).dup
    attrs[key] = value
    @conversation.update!(custom_attributes: attrs)
  end

  def send_webhook_event(webhook_url)
    payload = {
      event: "automation_event.#{@rule.event_name}",
      opportunity: @opportunity.as_json,
      account_id: @account.id
    }
    WebhookJob.perform_later(webhook_url[0], payload)
  end

  def send_email_to_team(params)
    teams = Team.where(id: params[0][:team_ids])
    return if teams.blank? || @conversation.blank?

    teams.each do |team|
      break unless @account.within_email_rate_limit?

      TeamNotifications::AutomationNotificationMailer.conversation_creation(@conversation, team, params[0][:message])&.deliver_now
      @account.increment_email_sent_count
    end
  end

  def extract_custom_attribute_key_value(params)
    if params.is_a?(Array) && params[0].is_a?(Hash)
      [params[0]['attribute_key'] || params[0][:attribute_key], params[0]['attribute_value'] || params[0][:attribute_value]]
    elsif params.is_a?(Hash)
      [params['attribute_key'] || params[:attribute_key], params['attribute_value'] || params[:attribute_value]]
    elsif params.is_a?(Array)
      [params[0], params[1]]
    end
  end
end
