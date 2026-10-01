# frozen_string_literal: true

class Custom::ScoutV2::Capabilities::CustomerRegistry < Custom::ScoutV2::Capabilities::Base
  capability_name 'customer_registry'

  PHONE_MISSING_ERROR = 'O contato não tem telefone registrado. Não peça o telefone ao cliente; ' \
                        'chame exit_handoff neste mesmo turno informando que o telefone está ausente.'

  UNIDENTIFIED_PERSON_ERROR = 'O sistema do cliente encontrou um cadastro, mas não foi possível identificá-lo. ' \
                              'Não cadastre novamente; chame exit_handoff neste mesmo turno.'

  UNCONFIRMED_CREATION_ERROR = 'O sistema do cliente não confirmou o cadastro (resposta sem identificador); ' \
                               'ele pode ter sido criado. Não repita a operação; chame exit_handoff neste mesmo turno.'

  operation :find_by_phone do
    output required: %w[status], shape: :record
  end

  operation :create do
    input :name, type: 'string', required: true
    output required: %w[status], shape: :record
  end

  def check_preconditions_for_find_by_phone
    check_phone_precondition
  end

  def check_preconditions_for_create(**_inputs)
    check_phone_precondition
  end

  def find_by_phone
    phone = normalized_phone
    res = provider.find_person(phone: phone)

    case res[:status]
    when :found
      handle_found_person(res[:person])
    when :ambiguous
      { status: 'ambiguous' }
    else
      { status: 'not_found' }
    end
  end

  def create(name:)
    phone = normalized_phone
    res = provider.create_person(name: name, phone: phone) || {}

    person_id = res[:id] || res['id']
    person_name = res[:name] || res['name'] || name

    if person_id.blank?
      return {
        error: UNCONFIRMED_CREATION_ERROR,
        deviations: ["campo de saída 'id' ausente"]
      }
    end

    state = ScoutConversationState.for_conversation(conversation)
    state.remember_customer!(id: person_id, name: person_name)
    { status: 'created', name: person_name }
  end

  private

  def contact_phone
    conversation&.contact&.phone_number
  end

  def normalized_phone
    raw = contact_phone
    provider.normalize_phone_digits(raw)
  end

  def check_phone_precondition
    PHONE_MISSING_ERROR if contact_phone.blank?
  end

  def handle_found_person(person)
    person ||= {}
    person_id = person[:id] || person['id']
    person_name = person[:name] || person['name']

    if person_id.blank?
      return {
        error: UNIDENTIFIED_PERSON_ERROR,
        deviations: ["campo de saída 'id' ausente"]
      }
    end

    state = ScoutConversationState.for_conversation(conversation)
    state.remember_customer!(id: person_id, name: person_name)
    { status: 'found', name: person_name }
  end
end
