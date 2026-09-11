# frozen_string_literal: true

module Custom::Inbox
  def active_bot?
    super || scout_active?
  end

  private

  def scout_active?
    scout&.enabled? || false
  end
end
