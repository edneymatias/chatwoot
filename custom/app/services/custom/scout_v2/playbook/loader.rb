# frozen_string_literal: true

# Never raises for a malformed playbook file: frontmatter it cannot use (unparseable YAML, a
# badly shaped `when_state`/`exits`) is recorded on `Playbook#load_errors` so the Validator can
# report every problem in one pass. A missing directory raises `Errno::ENOENT` from `Dir.children`
# so a mistyped `SCOUT_V2_PLAYBOOKS_DIR` fails boot instead of loading zero playbooks.
class Custom::ScoutV2::Playbook::Loader
  FRONTMATTER_PATTERN = /\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n(.*))?\z/m
  ALLOWED_EXIT_KEYS = %w[kind fields target stage].freeze

  class << self
    def load_all(dir = ENV['SCOUT_V2_PLAYBOOKS_DIR'].presence || Rails.root.join('custom/playbooks'))
      new(dir).load_all
    end
  end

  def initialize(dir)
    @dir = dir.to_s
  end

  def load_all
    Custom::ScoutV2::Playbook::Catalog.new(markdown_files.map { |file_path| load_playbook(file_path) })
  end

  private

  def markdown_files
    Dir.children(@dir).select { |entry| entry.end_with?('.md') }.sort.map { |entry| File.join(@dir, entry) }
  end

  def load_playbook(file_path)
    header, body = split_frontmatter(File.read(file_path))
    load_errors = []
    frontmatter = parse_frontmatter(header, load_errors)

    build_playbook(frontmatter, body, file_path, load_errors)
  end

  def split_frontmatter(content)
    match = FRONTMATTER_PATTERN.match(content)
    if match
      [match[1], match[2] || '']
    else
      ['', content]
    end
  end

  def parse_frontmatter(header, load_errors)
    parsed = YAML.safe_load(header)
    parsed.is_a?(Hash) ? parsed : {}
  rescue Psych::Exception => e
    load_errors << "Invalid YAML frontmatter: #{e.message}"
    {}
  end

  def build_playbook(frontmatter, body, file_path, load_errors)
    Custom::ScoutV2::Playbook.new(
      name: frontmatter['name'],
      title: frontmatter['title'],
      priority: frontmatter['priority'],
      trigger: frontmatter['trigger'],
      when_state: normalize_when_state(frontmatter['when_state'], load_errors),
      requires: Array(frontmatter['requires']).map(&:to_s),
      needs: Array(frontmatter['needs']).map(&:to_s),
      tools: Array(frontmatter['tools']).map(&:to_s),
      exits: normalize_exits(frontmatter['exits'], load_errors),
      body: body,
      file_path: file_path,
      load_errors: load_errors
    )
  end

  def normalize_when_state(raw_when_state, load_errors)
    return [] if raw_when_state.nil?

    unless raw_when_state.is_a?(Array)
      load_errors << "when_state must be a list (got #{raw_when_state.inspect})"
      return []
    end

    raw_when_state.filter_map { |entry| when_state_condition(entry, load_errors) }
  end

  def when_state_condition(entry, load_errors)
    return [entry, nil] if entry.is_a?(String)
    return [entry.keys.first.to_s, entry.values.first&.to_s] if entry.is_a?(Hash) && entry.size == 1

    load_errors << "Invalid when_state entry: #{entry.inspect} (expected a predicate name or a single-key mapping)"
    nil
  end

  def normalize_exits(raw_exits, load_errors)
    return {} if raw_exits.nil?

    unless raw_exits.is_a?(Hash)
      load_errors << "exits must be a mapping (got #{raw_exits.inspect})"
      return {}
    end

    raw_exits.each_with_object({}) do |(exit_name, entry), result|
      decl = build_exit_declaration(exit_name.to_s, entry, load_errors)
      result[exit_name.to_s] = decl if decl
    end
  end

  def build_exit_declaration(exit_name, entry, load_errors)
    unless entry.is_a?(Hash)
      load_errors << "Invalid exit '#{exit_name}': expected a mapping"
      return nil
    end

    unknown_keys = entry.keys.map(&:to_s) - ALLOWED_EXIT_KEYS
    unknown_keys.each { |key| load_errors << "Invalid exit '#{exit_name}': unknown key '#{key}'" }

    fields = normalize_exit_fields(exit_name, entry['fields'], load_errors)
    Custom::ScoutV2::Playbook::ExitDeclaration.new(
      name: exit_name,
      kind: entry['kind']&.to_s,
      fields: fields,
      target: entry['target']&.to_s,
      stage: entry['stage']&.to_s
    )
  end

  def normalize_exit_fields(exit_name, raw_fields, load_errors)
    return {} if raw_fields.nil?

    unless raw_fields.is_a?(Hash)
      load_errors << "Invalid exit '#{exit_name}': fields must be a mapping"
      return {}
    end

    raw_fields.each_with_object({}) do |(k, v), acc|
      acc[k.to_s] = v.to_s
    end
  end
end
