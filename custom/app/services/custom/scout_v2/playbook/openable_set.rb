# frozen_string_literal: true

class Custom::ScoutV2::Playbook::OpenableSet
  class << self
    def call(catalog:, pinned:)
      return catalog if pinned.blank?

      Custom::ScoutV2::Playbook::Catalog.new(catalog.select { |pb| pb.when_state.blank? })
    end
  end
end
