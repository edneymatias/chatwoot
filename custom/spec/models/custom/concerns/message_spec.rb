# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Concerns::Message do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :open)
  end
  let(:stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      title: 'Deal',
      origin_conversation: conversation,
      active_conversation: conversation
    )
  end

  describe 'after_create_commit broadcast' do
    it 'rebroadcasts linked opportunities when an incoming non-private message is created' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      create(:message, account: account, conversation: conversation, message_type: :incoming, private: false)

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id, 'has_unread_messages' => true)
      ).at_least(:once)
    end

    it 'does not rebroadcast when an outgoing message is created' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      create(:message, account: account, conversation: conversation, message_type: :outgoing, private: false)

      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id)
      )
    end

    it 'does not rebroadcast when a private message is created' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      create(:message, account: account, conversation: conversation, message_type: :incoming, private: true)

      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id)
      )
    end

    it 'does not error when conversation has no linked opportunities' do
      other_conv = create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)

      expect do
        create(:message, account: account, conversation: other_conv, message_type: :incoming, private: false)
      end.not_to raise_error
    end
  end
end
