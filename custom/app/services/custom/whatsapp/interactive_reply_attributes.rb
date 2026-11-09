# frozen_string_literal: true

# Keeps the machine-readable id of button/list replies and template quick replies alongside the
# visible title (chatwoot/chatwoot#12030), so webhooks and automations can rely on the id instead
# of matching on button text. Included by Custom::Whatsapp::IncomingMessageBaseService, so it sits
# ahead of Whatsapp::IncomingMessageBaseService in the ancestor chain.
module Custom::Whatsapp::InteractiveReplyAttributes
  private

  def message_content_attributes(message)
    interactive_reply = whatsapp_interactive_attributes(message)
    return super if interactive_reply.blank?

    super.merge(whatsapp_interactive: interactive_reply)
  end

  # button_reply / list_reply: interactive messages; button: quick reply on a template.
  def whatsapp_interactive_attributes(message)
    %w[button_reply list_reply].each do |reply_type|
      reply = message.dig(:interactive, reply_type)
      next if reply.blank?

      return { type: reply_type, id: reply[:id], title: reply[:title], description: reply[:description] }.compact_blank
    end

    button = message[:button]
    return if button.blank? || button[:payload].blank?

    { type: 'button', id: button[:payload], title: button[:text] }.compact_blank
  end
end
