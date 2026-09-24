# frozen_string_literal: true

Custom::ScoutV2::Playbook = Data.define(
  :name, :title, :priority, :trigger, :when_state,
  :requires, :needs, :tools, :exits, :body, :file_path, :load_errors
) do
  def initialize(**attrs)
    super(
      name: attrs[:name],
      title: attrs[:title],
      priority: attrs[:priority],
      trigger: attrs[:trigger],
      when_state: (attrs[:when_state] || []).freeze,
      requires: (attrs[:requires] || []).freeze,
      needs: (attrs[:needs] || []).freeze,
      tools: (attrs[:tools] || []).freeze,
      exits: (attrs[:exits] || {}).freeze,
      body: (attrs[:body] || '').freeze,
      file_path: attrs[:file_path],
      load_errors: (attrs[:load_errors] || []).freeze
    )
  end
end
