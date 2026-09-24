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
      validate_required_fields(playbook, violations)
      validate_name_formats(playbook, violations)
      validate_when_state(playbook, violations)
      validate_requires(playbook, violations)
      validate_body_tokens(playbook, known_playbook_names, violations)
    end
  end

  def validate_required_fields(playbook, violations)
    validate_text_fields(playbook, violations)
    validate_priority_field(playbook, violations)
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
      next if exit_name.is_a?(String) && NAME_PATTERN.match?(exit_name)

      violations << "#{file_ref(playbook)}: Invalid exit name: #{exit_name.inspect} (must match #{NAME_PATTERN.source})"
    end
  end

  def validate_when_state(playbook, violations)
    playbook.when_state.each do |condition|
      predicate_name = condition.first
      next if Custom::ScoutV2::Predicates::Registry.registered?(predicate_name)

      violations << "#{file_ref(playbook)}: Unregistered predicate: #{predicate_name}"
    end
  end

  def validate_requires(playbook, violations)
    playbook.requires.each do |cap|
      next if Custom::ScoutV2::Capabilities::Catalog.known?(cap)

      violations << "#{file_ref(playbook)}: Unknown capability: #{cap}"
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
      next if playbook.exits.key?(exit_name)

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
end
