# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Conversation do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:scout) { Scout.create!(account: account, name: 'SDR Bot', enabled: true) }
  let(:matching_contact) { create(:contact, account: account, phone_number: '+5511999999999') }
  let(:non_matching_contact) { create(:contact, account: account, phone_number: '+5511888888888') }

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
  end

  describe '#determine_conversation_status' do
    context 'when Scout has an audience configured' do
      before do
        scout.update!(
          audience: [
            {
              'attribute_key' => 'phone_number',
              'filter_operator' => 'equal_to',
              'values' => ['+5511999999999']
            }
          ]
        )
      end

      it 'starts conversation as pending when contact matches the audience' do
        contact_inbox = create(:contact_inbox, contact: matching_contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: matching_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('pending')
      end

      it 'starts conversation as open when contact does not match the audience' do
        contact_inbox = create(:contact_inbox, contact: non_matching_contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: non_matching_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('open')
      end
    end

    context 'when Scout has no audience configured (empty)' do
      before do
        scout.update!(audience: [])
      end

      it 'starts conversation as pending for any contact' do
        contact_inbox = create(:contact_inbox, contact: non_matching_contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: non_matching_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('pending')
      end
    end

    context 'when Scout is disabled' do
      before do
        scout.update!(enabled: false)
      end

      it 'starts conversation as open' do
        contact_inbox = create(:contact_inbox, contact: matching_contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: matching_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('open')
      end
    end

    context 'when inbox has no Scout attached' do
      let(:other_inbox) { create(:inbox, account: account) }

      it 'starts conversation as open' do
        contact_inbox = create(:contact_inbox, contact: matching_contact, inbox: other_inbox)
        conversation = create(:conversation, account: account, inbox: other_inbox, contact: matching_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('open')
      end
    end

    context 'when contact is blocked' do
      let(:blocked_contact) { create(:contact, account: account, blocked: true, phone_number: '+5511999999999') }

      it 'starts conversation as resolved via super' do
        contact_inbox = create(:contact_inbox, contact: blocked_contact, inbox: inbox)
        conversation = create(:conversation, account: account, inbox: inbox, contact: blocked_contact, contact_inbox: contact_inbox)

        expect(conversation.status).to eq('resolved')
      end
    end
  end
end
