# frozen_string_literal: true

class Custom::ScoutV2::PlaygroundConversation
  def self.for(scout)
    new(scout).resolve
  end

  def initialize(scout)
    @scout = scout
    @account = scout.account
  end

  def resolve
    contact = find_or_create_contact
    contact_inbox = contact.contact_inboxes.first || build_sandbox_infrastructure(contact)
    find_or_create_conversation(contact, contact_inbox)
  end

  private

  def find_or_create_contact
    Contact.find_or_create_by!(
      account: @account,
      identifier: "scoutv2-playground-scout-#{@scout.id}"
    ) do |c|
      c.name = "Scout Playground (#{@scout.name})"
    end
  end

  def build_sandbox_infrastructure(contact)
    ActiveRecord::Base.transaction do
      channel = Channel::Api.create!(account: @account)
      inbox = Inbox.create!(
        account: @account,
        name: "Scout Playground — #{@scout.name}",
        channel: channel
      )
      ScoutInbox.create!(scout: @scout, inbox: inbox)
      ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
    end
  end

  def find_or_create_conversation(contact, contact_inbox)
    conversation = contact.conversations.find_by(inbox: contact_inbox.inbox)
    return conversation if conversation.present?

    conversation = Conversation.create!(
      account: @account,
      inbox: contact_inbox.inbox,
      contact: contact,
      contact_inbox: contact_inbox
    )
    conversation.open! unless conversation.open?
    conversation
  end
end
