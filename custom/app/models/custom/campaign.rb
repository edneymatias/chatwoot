# frozen_string_literal: true

module Custom::Campaign
  extend ActiveSupport::Concern

  included do
    has_many :ichatr_campaign_recipients,
             class_name: 'Custom::CampaignRecipient',
             dependent: :destroy
  end
end
