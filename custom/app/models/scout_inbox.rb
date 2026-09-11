# frozen_string_literal: true

class ScoutInbox < ApplicationRecord
  self.table_name = 'ichatr_scout_inboxes'

  belongs_to :scout, class_name: 'Scout'
  belongs_to :inbox, class_name: 'Inbox'

  validates :scout_id, :inbox_id, presence: true
  validates :inbox_id, uniqueness: true
end
