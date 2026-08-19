# frozen_string_literal: true

class ScoutTool < ApplicationRecord
  self.table_name = 'ichatr_scout_tools'

  encrypts :auth_headers

  belongs_to :account

  alias_attribute :parameters_schema, :parameter_schema

  validates :account_id, :name, :description, :endpoint_url, :http_method, presence: true
end
