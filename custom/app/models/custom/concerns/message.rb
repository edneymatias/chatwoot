# frozen_string_literal: true

module Custom::Concerns::Message
  extend ActiveSupport::Concern

  included do
    after_commit :refresh_linked_opportunities_kanban_badges, on: :create, if: :incoming_non_private_message?
  end

  private

  def incoming_non_private_message?
    incoming? && !private?
  end

  # When an incoming non-private message arrives, any Opportunity linked to this conversation
  # might need to surface its unread message dot. Because the Opportunity record itself is
  # untouched, push a fresh ActionCable broadcast for each linked opportunity.
  def refresh_linked_opportunities_kanban_badges
    conversation&.opportunities&.find_each(&:broadcast_kanban_badges_refresh)
  end
end
