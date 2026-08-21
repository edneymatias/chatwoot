# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::UpdateContact do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Old Name', email: 'old@example.com') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    it 'updates contact attributes and merges custom attributes' do
      result = tool.execute(
        name: 'New Name',
        email: 'new@example.com',
        phone: '+5511999999999',
        custom_attributes: { 'budget' => '10000', 'decision_maker' => true }
      )

      expect(result).to include('successfully')
      contact.reload
      expect(contact.name).to eq('New Name')
      expect(contact.email).to eq('new@example.com')
      expect(contact.phone_number).to eq('+5511999999999')
      expect(contact.custom_attributes['budget']).to eq('10000')
      expect(contact.custom_attributes['decision_maker']).to be(true)
    end
  end
end
