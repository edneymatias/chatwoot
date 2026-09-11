# frozen_string_literal: true

module Custom::Concerns::Inbox
  extend ActiveSupport::Concern

  included do
    has_one :scout_inbox, class_name: 'ScoutInbox', dependent: :destroy
    has_one :scout, through: :scout_inbox
  end
end
