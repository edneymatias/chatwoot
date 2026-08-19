# frozen_string_literal: true

class ScoutTool < ApplicationRecord
  self.table_name = 'ichatr_scout_tools'

  encrypts :auth_headers

  belongs_to :account

  validates :account_id, :name, :description, :endpoint_url, :http_method, presence: true
end
