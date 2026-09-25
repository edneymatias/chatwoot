# frozen_string_literal: true

class Custom::ScoutV2::Tools::Registry
  TOOL_CLASSES = {
    'manage_opportunity' => Custom::Scout::Tools::ManageOpportunity
  }.freeze

  class << self
    def build(tool_names, scout:, conversation:)
      tool_names.map do |name|
        tool_class = TOOL_CLASSES.fetch(name)
        tool_class.new(scout, conversation, playground: false)
      end
    end
  end
end
