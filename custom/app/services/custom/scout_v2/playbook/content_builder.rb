# frozen_string_literal: true

class Custom::ScoutV2::Playbook::ContentBuilder
  PENDING_STEPS_NOTICE = 'Passos marcados como PENDENTE dependem de integrações ou políticas ainda indisponíveis. ' \
                         'Não simule, não prometa e não confirme essas ações. Se o cliente precisar delas, use exit_handoff.'

  PHONE_MISSING_NOTICE = 'O contato não tem telefone registrado. Não chame ferramentas customer_registry_*, ' \
                         'não peça o telefone ao cliente e chame exit_handoff neste mesmo turno informando que o telefone está ausente.'
  def self.call(playbook:, ctx:)
    new(playbook: playbook, ctx: ctx).call
  end

  def initialize(playbook:, ctx:)
    @playbook = playbook
    @ctx = ctx
  end

  def call
    rendered_body, has_pending = render_body_markers(@playbook.body.strip)
    condition_names = @playbook.when_state.to_set(&:first)

    blocks = [
      rendered_body,
      (PENDING_STEPS_NOTICE if has_pending),
      build_contact_gaps_block(condition_names),
      build_pending_fields_block(condition_names),
      build_phone_missing_notice_block
    ].compact_blank
    blocks.join("\n\n")
  end

  private

  def build_contact_gaps_block(condition_names)
    return unless condition_names.include?('contact_identity_incomplete')

    contact = @ctx.conversation&.contact || @ctx.contact
    contact = contact.reload if contact.respond_to?(:reload) && contact.respond_to?(:persisted?) && contact.persisted?
    Custom::ScoutV2::Playbook::ContactGapsFormatter.call(contact: contact)
  end

  def build_pending_fields_block(condition_names)
    return unless condition_names.intersect?(Set['in_qualification', 'pending_required_fields'])

    Custom::ScoutV2::Playbook::PendingFieldsFormatter.call(
      account_id: resolve_account_id,
      pending_keys: resolve_pending_keys
    )
  end

  def build_phone_missing_notice_block
    return unless (@playbook.requires || []).include?('customer_registry')

    contact = @ctx.conversation&.contact || @ctx.contact
    contact = contact.reload if contact.respond_to?(:reload) && contact.respond_to?(:persisted?) && contact.persisted?
    return if contact&.phone_number.present?

    PHONE_MISSING_NOTICE
  end

  def resolve_account_id
    @ctx.conversation&.account_id || @ctx.scout&.account_id || @ctx.contact&.account_id
  end

  def resolve_pending_keys
    opportunity = @ctx.conversation&.reload_active_opportunity if @ctx.conversation.respond_to?(:reload_active_opportunity)
    opportunity ||= @ctx.opportunity

    if @ctx.scout.present?
      Custom::ScoutV2::RoutingSnapshot::PendingFields.call(scout: @ctx.scout, opportunity: opportunity)
    else
      @ctx.pending_fields
    end
  end

  def render_body_markers(body)
    satisfied = ((@ctx.satisfied_capabilities || []) + (@ctx.satisfied_business_facts || [])).to_set
    has_pending = false

    rendered = body.gsub(/(\s*)\[\[depends:\s*([^\]]+?)\s*\]\]/) do
      leading_space = ::Regexp.last_match(1)
      names = ::Regexp.last_match(2).split(',').map(&:strip)
      unsatisfied = names.reject { |n| satisfied.include?(n) }

      if unsatisfied.any?
        has_pending = true
        "#{leading_space}(PENDENTE — indisponível: #{unsatisfied.join(', ')})"
      else
        ''
      end
    end

    [rendered, has_pending]
  end
end
