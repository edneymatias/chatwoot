# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::PlaygroundConversation do
  let(:account) { create(:account) }
  let(:scout) { Scout.create!(account: account, name: 'Sales Assistant') }

  describe '.for' do
    it 'creates dedicated records for sandbox infrastructure' do
      expect do
        described_class.for(scout)
      end.to change(Conversation, :count).by(1)
         .and change(Contact, :count).by(1)
         .and change(Inbox, :count).by(1)
         .and change(ScoutInbox, :count).by(1)
         .and change(ContactInbox, :count).by(1)
    end

    it 'returns a persisted open conversation with dedicated associations' do
      conversation = described_class.for(scout)

      expect(conversation).to be_a(Conversation)
      expect(conversation.status).to eq('open')
      expect(conversation.account).to eq(account)
      expect(conversation.contact.identifier).to eq("scoutv2-playground-scout-#{scout.id}")
      expect(conversation.inbox.name).to eq("Scout Playground — #{scout.name}")
      expect(conversation.inbox.scout).to eq(scout)
    end

    it 'is idempotent and reuses the existing conversation without creating duplicates' do
      first_conversation = described_class.for(scout)

      expect do
        second_conversation = described_class.for(scout)
        expect(second_conversation.id).to eq(first_conversation.id)
      end.to not_change(Conversation, :count)
         .and not_change(Contact, :count)
         .and not_change(Inbox, :count)
         .and not_change(ScoutInbox, :count)
         .and not_change(ContactInbox, :count)
    end

    it 'isolates conversations between different scouts in the same account' do
      other_scout = Scout.create!(account: account, name: 'Support Assistant')

      conversation1 = described_class.for(scout)
      conversation2 = described_class.for(other_scout)

      expect(conversation1.id).not_to eq(conversation2.id)
      expect(conversation1.contact_id).not_to eq(conversation2.contact_id)
      expect(conversation1.inbox_id).not_to eq(conversation2.inbox_id)
      expect(conversation1.inbox.scout).to eq(scout)
      expect(conversation2.inbox.scout).to eq(other_scout)
    end
  end
end
