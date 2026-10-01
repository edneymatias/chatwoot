# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::Scheduling < Custom::ScoutV2::Capabilities::Base
  capability_name 'scheduling'

  operation :list_slots do
    input :date, type: 'date', required: true, description: 'data no formato YYYY-MM-DD'
    input :service, type: 'string', required: false, description: 'nome do serviço desejado, apenas informativo'
    output required: %w[slot_id starts_at], shape: :list
  end

  operation :book do
    input :slot_id, type: 'string', required: true
    input :notes, type: 'string', required: false
    output required: %w[appointment_id], shape: :record
  end

  def list_slots(date:, **_extra)
    slots = provider.list_free_slots(date: date) || []
    state = ScoutConversationState.for_conversation(conversation)

    slot_map = slots.each_with_object({}) do |slot, map|
      s_id = slot[:slot_id] || slot['slot_id']
      s_at = slot[:starts_at] || slot['starts_at']
      map[s_id] = s_at if s_id.present? && s_at.present?
    end

    state.remember_slots!(slot_map) if slot_map.present?

    { slots: slots }
  end

  def check_preconditions_for_book(slot_id:, **_extra)
    state = ScoutConversationState.for_conversation(conversation)
    cap_state = state.capability_state || {}

    return 'Já existe um agendamento confirmado nesta conversa. Não agende novamente; encerre com exit_agendado.' if cap_state['booking'].present?

    if cap_state['customer'].blank? || cap_state.dig('customer', 'id').blank?
      return 'Nenhum cliente foi localizado ou cadastrado nesta conversa. ' \
             'Use customer_registry_find_by_phone (ou customer_registry_create) antes de agendar.'
    end

    offered_slots = cap_state['offered_slots'] || {}
    unless offered_slots.key?(slot_id.to_s)
      return "O horário '#{slot_id}' não foi oferecido nesta conversa. Liste os horários com scheduling_list_slots e escolha um dos retornados."
    end

    nil
  end

  def book(slot_id:, notes: nil)
    state = ScoutConversationState.for_conversation(conversation)
    cap_state = state.capability_state || {}
    customer = cap_state['customer'] || {}
    starts_at = cap_state.dig('offered_slots', slot_id.to_s)

    res = provider.create_appointment(
      person_id: customer['id'],
      person_name: customer['name'],
      starts_at: starts_at,
      notes: notes
    ) || {}

    handle_booking_result(res, starts_at, state)
  end

  private

  def handle_booking_result(res, starts_at, state)
    appointment_id = res[:appointment_id] || res['appointment_id']
    if appointment_id.blank?
      return {
        error: 'O sistema do cliente não confirmou o agendamento (resposta sem identificador); ' \
               'ele pode ter sido criado. Não repita a operação, não prometa nem confirme o agendamento; ' \
               'chame exit_handoff neste mesmo turno.',
        deviations: ["campo de saída 'appointment_id' ausente"]
      }
    end

    state.remember_booking!(appointment_id: appointment_id, starts_at: starts_at)
    { appointment_id: appointment_id, starts_at: starts_at }
  end
end
