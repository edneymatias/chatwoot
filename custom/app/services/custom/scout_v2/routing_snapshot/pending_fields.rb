# frozen_string_literal: true

class Custom::ScoutV2::RoutingSnapshot::PendingFields
  def self.call(scout:, opportunity:)
    new(scout: scout, opportunity: opportunity).call
  end

  def initialize(scout:, opportunity:)
    @scout = scout
    @opportunity = opportunity
  end

  def call
    return scout_requirement_keys if @opportunity.nil?

    scout_defs = @scout&.required_custom_attribute_definitions || []
    stage_defs = @opportunity.pipeline_stage&.required_custom_attribute_definitions || []
    all_defs = (scout_defs + stage_defs).uniq

    custom_attrs = @opportunity.custom_attributes || {}
    all_defs.filter_map do |defn|
      key = defn.attribute_key
      key if custom_attrs[key].blank?
    end.uniq
  end

  private

  def scout_requirement_keys
    return [] unless @scout

    @scout.required_custom_attribute_definitions.map(&:attribute_key).uniq
  end
end
