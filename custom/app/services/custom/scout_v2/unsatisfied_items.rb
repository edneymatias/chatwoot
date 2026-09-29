# frozen_string_literal: true

class Custom::ScoutV2::UnsatisfiedItems
  class << self
    def call(playbook:, conversation:, scout:, ctx:)
      return empty_record if playbook.blank?

      opportunity = conversation&.reload_active_opportunity if conversation.respond_to?(:reload_active_opportunity)
      opportunity ||= ctx&.opportunity

      pending_keys = Custom::ScoutV2::RoutingSnapshot::PendingFields.call(scout: scout, opportunity: opportunity)
      satisfied_caps = ctx&.satisfied_capabilities || []
      satisfied_facts = ctx&.satisfied_business_facts || []

      {
        procedure: playbook.name,
        pending_fields: pending_keys,
        unmet_requires: (playbook.requires || []) - satisfied_caps,
        unmet_needs: (playbook.needs || []) - satisfied_facts
      }
    end

    def trace!(playbook:, conversation:, scout:, ctx:)
      record = call(playbook: playbook, conversation: conversation, scout: scout, ctx: ctx)

      if defined?(OpenTelemetry::Trace)
        current_span = OpenTelemetry::Trace.current_span
        current_span.set_attribute('langfuse.trace.metadata.unsatisfied_flags', record.to_json) if current_span&.recording?
      end

      record
    end

    private

    def empty_record
      {
        procedure: nil,
        pending_fields: [],
        unmet_requires: [],
        unmet_needs: []
      }
    end
  end
end
