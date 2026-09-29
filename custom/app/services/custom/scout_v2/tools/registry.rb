# frozen_string_literal: true

class Custom::ScoutV2::Tools::Registry
  TOOL_CLASSES = {
    'manage_opportunity' => Custom::ScoutV2::Tools::ManageOpportunity,
    'update_contact' => Custom::Scout::Tools::UpdateContact
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
