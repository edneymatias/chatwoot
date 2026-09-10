# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Concerns::Conversation do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
  end
  let(:stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:scout) { Scout.create!(account: account, name: 'Scout', enabled: true) }

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
  end

  describe '#refresh_linked_opportunities_scout_badge' do
    let!(:opportunity) do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Deal', origin_conversation: conversation)
    end

    it 'rebroadcasts every opportunity linked to the conversation when its status changes' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      conversation.open!

      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id)
      ).at_least(:once)
    end

    it 'reflects the current scout_engaged value in the rebroadcast payload' do
      expect(opportunity.scout_engaged?).to be(true)

      allow(ActionCableBroadcastJob).to receive(:perform_later)
      conversation.open!

      expect(opportunity.reload.scout_engaged?).to be(false)
      expect(ActionCableBroadcastJob).to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id, 'scout_engaged' => false)
      ).at_least(:once)
    end

    it 'does not push an opportunity_updated broadcast when an attribute unrelated to status changes' do
      allow(ActionCableBroadcastJob).to receive(:perform_later)

      conversation.update!(additional_attributes: { some: 'value' })

      expect(ActionCableBroadcastJob).not_to have_received(:perform_later).with(
        ["account_#{account.id}"],
        'opportunity_updated',
        hash_including('id' => opportunity.id)
      )
    end

    it 'does not dispatch through the automation-rule event bus (would spuriously re-trigger "opportunity updated" rules)' do
      # Uses resolved! rather than open! here specifically to isolate this fix's own broadcast
      # path from the pre-existing Custom::ActionCableListener#conversation_opened handler, which
      # separately promotes active_conversation (and so separately broadcasts) only when a
      # conversation transitions specifically to `open` - not relevant to what's under test here.
      allow(ActionCableBroadcastJob).to receive(:perform_later)
      expect(Rails.configuration.dispatcher).not_to receive(:dispatch).with('opportunity_updated', anything, anything)

      conversation.resolved!
    end
  end

  it 'does not error when the conversation has no linked opportunities' do
    expect { conversation.open! }.not_to raise_error
  end
end
