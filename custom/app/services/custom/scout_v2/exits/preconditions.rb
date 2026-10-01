# frozen_string_literal: true

class Custom::ScoutV2::Exits::Preconditions
  BOOKING_ERROR = 'Você ainda não realizou nenhum agendamento nesta conversa. ' \
                  'Chame scheduling_book antes de exit_agendado, ou transfira com exit_handoff.'

  REGISTRY = {
    'booking' => lambda { |exit_tool|
      state = ScoutConversationState.for_conversation(exit_tool.conversation)
      booking = state.capability_state['booking']
      BOOKING_ERROR if booking.blank? || booking['appointment_id'].blank?
    }
  }.freeze

  class << self
    def known?(name)
      REGISTRY.key?(name.to_s)
    end

    def check(name, exit_tool)
      checker = REGISTRY[name.to_s]
      checker&.call(exit_tool)
    end
  end
end
