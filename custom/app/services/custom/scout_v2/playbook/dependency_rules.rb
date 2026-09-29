# frozen_string_literal: true

class Custom::ScoutV2::Playbook::DependencyRules
  DEPENDS_MARKER_PATTERN = /\[\[depends:\s*([^\]]*)\]\]/

  class << self
    def call(playbook:, catalog:, file_ref:, violations:)
      new(playbook: playbook, catalog: catalog, file_ref: file_ref, violations: violations).call
    end
  end

  def initialize(playbook:, catalog:, file_ref:, violations:)
    @playbook = playbook
    @catalog = catalog
    @file_ref = file_ref
    @violations = violations
  end

  def call
    validate_when_state
    validate_requires
    validate_needs
    validate_markers
  end

  private

  def validate_when_state
    @playbook.when_state.each do |condition|
      name, arg = condition
      unless Custom::ScoutV2::Predicates::Registry.registered?(name)
        @violations << "#{@file_ref}: Unregistered predicate: #{name}"
        next
      end

      validate_condition_argument(name, arg)
    end
  end

  def validate_condition_argument(name, arg)
    kind = Custom::ScoutV2::Predicates::Registry.argument_kind(name)
    if kind.nil?
      @violations << "#{@file_ref}: Predicate #{name} takes no argument (got #{arg})" if arg.present?
    elsif arg.blank?
      @violations << "#{@file_ref}: Predicate #{name} requires an argument"
    else
      validate_specific_argument(name, arg, kind)
    end
  end

  def validate_specific_argument(name, arg, kind)
    case kind
    when :stage_role
      unless Custom::ScoutV2::Predicates::OpportunityInStage::ROLES.include?(arg.to_s)
        @violations << "#{@file_ref}: Unknown stage role for #{name}: #{arg}"
      end
    when :playbook_name
      target = @catalog[arg.to_s]
      if target.nil?
        @violations << "#{@file_ref}: Unknown playbook for #{name}: #{arg}"
      elsif target.when_state.empty?
        @violations << "#{@file_ref}: #{name} must name a procedure playbook: #{arg}"
      end
    end
  end

  def validate_requires
    @playbook.requires.each do |cap|
      next if Custom::ScoutV2::Capabilities::Catalog.known?(cap)

      @violations << "#{@file_ref}: Unknown capability: #{cap}"
    end
  end

  def validate_needs
    @playbook.needs.each do |fact|
      next if Custom::ScoutV2::BusinessFacts::Catalog.known?(fact)

      @violations << "#{@file_ref}: Unknown business fact: #{fact}"
    end
  end

  def validate_markers
    declared = (@playbook.requires + @playbook.needs).to_set(&:to_s)
    @playbook.body.to_s.scan(DEPENDS_MARKER_PATTERN) do |match|
      validate_marker_content(match.first, declared)
    end
  end

  def validate_marker_content(content, declared)
    names = content.split(',').map(&:strip)
    if names.empty? || names.all?(&:empty?)
      @violations << "#{@file_ref}: Empty pending-step marker"
      return
    end

    names.each do |name|
      if name.empty?
        @violations << "#{@file_ref}: Empty pending-step marker"
      elsif declared.exclude?(name)
        @violations << "#{@file_ref}: Pending-step marker references undeclared requirement: #{name}"
      end
    end
  end
end
