# frozen_string_literal: true

module Custom::Conversation
  private

  def determine_conversation_status
    super
    return unless pending?

    scout = inbox&.scout
    self.status = :open if scout&.enabled? && !scout.engages?(contact, self)
  end
end
