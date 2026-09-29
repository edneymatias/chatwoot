# frozen_string_literal: true

Custom::ScoutV2::Playbook::ExitDeclaration = Data.define(:name, :kind, :fields, :target, :stage) do
  def initialize(name:, kind:, fields: {}, target: nil, stage: nil)
    super(
      name: name,
      kind: kind,
      fields: fields.freeze,
      target: target,
      stage: stage
    )
  end
end

Custom::ScoutV2::Playbook::ExitDeclaration::KINDS = %w[terminal transition escalation].freeze
Custom::ScoutV2::Playbook::ExitDeclaration::FIELD_TYPES = %w[string integer number boolean datetime].freeze
Custom::ScoutV2::Playbook::ExitDeclaration::STAGE_ROLES = %w[qualified unqualified].freeze
Custom::ScoutV2::Playbook::ExitDeclaration::HANDOFF = Custom::ScoutV2::Playbook::ExitDeclaration.new(
  name: 'handoff',
  kind: 'escalation',
  fields: { 'reason' => 'string' }.freeze,
  target: nil,
  stage: nil
).freeze
