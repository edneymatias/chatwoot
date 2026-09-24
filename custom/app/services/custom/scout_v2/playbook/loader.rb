# frozen_string_literal: true

# Never raises for a malformed playbook file: frontmatter it cannot use (unparseable YAML, a
# badly shaped `when_state`/`exits`) is recorded on `Playbook#load_errors` so the Validator can
# report every problem in one pass. A missing directory raises `Errno::ENOENT` from `Dir.children`
# so a mistyped `SCOUT_V2_PLAYBOOKS_DIR` fails boot instead of loading zero playbooks.
class Custom::ScoutV2::Playbook::Loader
  FRONTMATTER_PATTERN = /\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n(.*))?\z/m

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
    return raw_exits if raw_exits.is_a?(Hash)

    load_errors << "exits must be a mapping (got #{raw_exits.inspect})" unless raw_exits.nil?
    {}
  end
end
