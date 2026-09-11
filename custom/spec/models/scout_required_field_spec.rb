# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutRequiredField, type: :model do
  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Field Scout',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end
  let(:custom_attribute) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute')
  end

  describe 'validations' do
    it 'validates unique custom attribute definition per scout' do
      described_class.create!(account: account, scout: scout, custom_attribute_definition: custom_attribute)
      duplicate = described_class.new(account: account, scout: scout, custom_attribute_definition: custom_attribute)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:custom_attribute_definition_id]).to be_present
    end
  end
end
