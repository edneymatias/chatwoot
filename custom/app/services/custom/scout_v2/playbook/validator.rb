# frozen_string_literal: true

class Custom::ScoutV2::Playbook::Validator
  # Playbook and exit names share one format. The body-token patterns deliberately capture more
  # than that format so a reference spelled outside it is still captured and reported, not skipped.
  NAME_PATTERN = /\A[a-z][a-z0-9_]*\z/
  EXIT_TOKEN_PATTERN = /\bexit_([[:word:]-]+)/
  OPEN_PLAYBOOK_PATTERN = /open_playbook\(\s*['"]?([^'")\s]+)['"]?\s*\)/

  class ValidationError < StandardError
    attr_reader :violations

    def initialize(violations = [])
      @violations = Array(violations)
      super(@violations.join("\n"))
    end
  end

  class << self
    def call!(catalog)
      new(catalog).call!
    end
  end

  def initialize(catalog)
    @catalog = catalog
  end

  def call!
    violations = []
    validate_uniqueness(violations)
    validate_playbooks(violations)

    raise ValidationError, violations if violations.any?

    @catalog
  end

  private

  def file_ref(playbook)
    playbook.file_path || playbook.name || '<unknown file>'
  end

  def validate_uniqueness(violations)
    validate_unique_priorities(violations)
    validate_unique_names(violations)
  end

  def validate_unique_priorities(violations)
    with_priorities = @catalog.playbooks.select { |pb| pb.priority.is_a?(Integer) }
    with_priorities.group_by(&:priority).each do |priority, pbs|
      next if pbs.size <= 1

      files = pbs.map { |pb| file_ref(pb) }.join(', ')
      violations << "#{files}: Duplicate priority '#{priority}' declared across playbooks"
    end
  end

  def validate_unique_names(violations)
    with_names = @catalog.playbooks.reject { |pb| pb.name.to_s.strip.empty? }
    with_names.group_by(&:name).each do |name, pbs|
      next if pbs.size <= 1

      files = pbs.map { |pb| file_ref(pb) }.join(', ')
      violations << "#{files}: Duplicate name '#{name}' declared across playbooks"
    end
  end

  def validate_playbooks(violations)
    known_playbook_names = @catalog.playbooks.filter_map(&:name).to_set

    @catalog.playbooks.each do |playbook|
      playbook.load_errors.each { |error| violations << "#{file_ref(playbook)}: #{error}" }
      validate_text_fields(playbook, violations)
      validate_priority_field(playbook, violations)
      validate_name_formats(playbook, violations)
      Custom::ScoutV2::Playbook::DependencyRules.call(
        playbook: playbook,
        catalog: @catalog,
        file_ref: file_ref(playbook),
        violations: violations
      )
      validate_tools(playbook, violations)
      validate_situational_exits(playbook, violations)
      validate_exit_declarations(playbook, violations)
      validate_body_tokens(playbook, known_playbook_names, violations)
    end
  end

  def validate_text_fields(playbook, violations)
    violations << "#{file_ref(playbook)}: Name cannot be blank" if playbook.name.to_s.strip.empty?
    violations << "#{file_ref(playbook)}: Title cannot be blank" if !playbook.title.is_a?(String) || playbook.title.strip.empty?
    violations << "#{file_ref(playbook)}: Trigger cannot be blank" if !playbook.trigger.is_a?(String) || playbook.trigger.strip.empty?
  end

  def validate_priority_field(playbook, violations)
    return if playbook.priority.is_a?(Integer)

    violations << "#{file_ref(playbook)}: Priority must be an Integer (got #{playbook.priority.inspect})"
  end

  def validate_name_formats(playbook, violations)
    name = playbook.name
    unless name.to_s.strip.empty? || (name.is_a?(String) && NAME_PATTERN.match?(name))
      violations << "#{file_ref(playbook)}: Invalid name: #{name.inspect} (must match #{NAME_PATTERN.source})"
    end

    playbook.exits.each_key do |exit_name|
      unless NAME_PATTERN.match?(exit_name)
        violations << "#{file_ref(playbook)}: Invalid exit name: #{exit_name.inspect} (must match #{NAME_PATTERN.source})"
        next
      end

      violations << "#{file_ref(playbook)}: Reserved exit name: handoff" if exit_name == 'handoff'
    end
  end

  def validate_tools(playbook, violations)
    playbook.tools.each do |tool_name|
      next if Custom::ScoutV2::Tools::Registry::TOOL_CLASSES.key?(tool_name)

      violations << "#{file_ref(playbook)}: Unregistered tool: #{tool_name}"
    end
  end

  def validate_body_tokens(playbook, known_playbook_names, violations)
    return if playbook.body.empty?

    validate_exit_tokens(playbook, violations)
    validate_open_playbook_tokens(playbook, known_playbook_names, violations)
  end

  def validate_exit_tokens(playbook, violations)
    exit_tokens = playbook.body.scan(EXIT_TOKEN_PATTERN).flatten.uniq
    exit_tokens.each do |exit_name|
      next if exit_name == 'handoff' || playbook.exits.key?(exit_name)

      violations << "#{file_ref(playbook)}: Undeclared exit token: exit_#{exit_name}"
    end
  end

  def validate_open_playbook_tokens(playbook, known_playbook_names, violations)
    playbook_tokens = playbook.body.scan(OPEN_PLAYBOOK_PATTERN).flatten.uniq
    playbook_tokens.each do |target_name|
      next if known_playbook_names.include?(target_name)

      violations << "#{file_ref(playbook)}: Unresolved playbook: #{target_name}"
    end
  end

  def validate_situational_exits(playbook, violations)
    return unless playbook.when_state.empty?

    playbook.exits.each_key do |exit_name|
      violations << "#{file_ref(playbook)}: Situational playbook cannot declare exits: #{exit_name}"
    end
  end

  def validate_exit_declarations(playbook, violations)
    playbook.exits.each_value do |exit_decl|
      validate_exit_kind(playbook, exit_decl, violations)
      validate_exit_target(playbook, exit_decl, violations)
      validate_exit_fields(playbook, exit_decl, violations)
      validate_exit_stage(playbook, exit_decl, violations)
    end
  end

  def validate_exit_kind(playbook, exit_decl, violations)
    return if Custom::ScoutV2::Playbook::ExitDeclaration::KINDS.include?(exit_decl.kind)

    violations << "#{file_ref(playbook)}: Unknown exit kind for '#{exit_decl.name}': #{exit_decl.kind}"
  end

  def validate_exit_target(playbook, exit_decl, violations)
    if exit_decl.kind == 'transition'
      if exit_decl.target.to_s.strip.empty?
        violations << "#{file_ref(playbook)}: Transition exit '#{exit_decl.name}' requires a target"
        return
      end

      validate_transition_target(playbook, exit_decl, violations)
    elsif !exit_decl.target.nil?
      violations << "#{file_ref(playbook)}: Exit '#{exit_decl.name}' declares a target but is not a transition"
    end
  end

  def validate_transition_target(playbook, exit_decl, violations)
    target_pb = @catalog[exit_decl.target]
    if target_pb.nil?
      violations << "#{file_ref(playbook)}: Unknown transition target for '#{exit_decl.name}': #{exit_decl.target}"
    elsif target_pb.name == playbook.name
      violations << "#{file_ref(playbook)}: Transition exit '#{exit_decl.name}' cannot target its own playbook"
    elsif target_pb.when_state.empty?
      violations << "#{file_ref(playbook)}: Transition exit '#{exit_decl.name}' cannot target situational playbook #{target_pb.name}"
    end
  end

  def validate_exit_fields(playbook, exit_decl, violations)
    exit_decl.fields.each do |field_name, field_type|
      violations << "#{file_ref(playbook)}: Invalid field name in exit '#{exit_decl.name}': #{field_name}" unless NAME_PATTERN.match?(field_name)

      unless Custom::ScoutV2::Playbook::ExitDeclaration::FIELD_TYPES.include?(field_type)
        violations << "#{file_ref(playbook)}: Unsupported field type in exit '#{exit_decl.name}': #{field_name}: #{field_type}"
      end
    end
  end

  def validate_exit_stage(playbook, exit_decl, violations)
    return if exit_decl.stage.nil? || Custom::ScoutV2::Playbook::ExitDeclaration::STAGE_ROLES.include?(exit_decl.stage)

    violations << "#{file_ref(playbook)}: Unknown stage role for '#{exit_decl.name}': #{exit_decl.stage}"
  end
end
