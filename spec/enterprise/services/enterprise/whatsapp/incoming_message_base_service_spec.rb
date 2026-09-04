require 'rails_helper'

RSpec.describe Enterprise::Whatsapp::IncomingMessageBaseService do
  let(:channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
  let(:status) do
    {
      'id' => 'wamid.not-persisted-yet',
      'status' => 'delivered',
      'timestamp' => '1700000600'
    }
  end

  before { channel.account.enable_features!(:whatsapp_campaign) }

  # Pending since ichatr-main's feature 045 (WhatsApp campaign reply tracking, see
  # specs/045-whatsapp-campaign-reply-tracking/research.md, "Decision: Replace, not augment,
  # the Enterprise recipient tracking"): Custom::Whatsapp::IncomingMessageBaseService#process_statuses
  # fully intercepts (no `super`) before this Enterprise module's #process_statuses ever runs, by
  # design, so this exact deferred-enqueue behavior no longer executes in this fork. It cannot be
  # restored by conditionally calling `super` here without reintroducing real cost: Enterprise's own
  # CampaignRecipient table is permanently empty in this fork (its #perform is intercepted the same
  # way), so `@message` is the only thing gating its enqueue — and this fork never creates a Message
  # for a campaign send until the customer replies (FR-012), meaning `@message` is nil for nearly
  # every delivered/read/failed status webhook of every recipient who hasn't replied yet, not just
  # the rare race this test targets. Calling `super` here would enqueue Enterprise's
  # already-permanently-doomed Campaigns::UpdateRecipientStatusJob (it only ever queries the
  # Enterprise table) on nearly every such webhook — real, continuous Sidekiq churn against a
  # method that can never succeed, which is worse than not running it at all. The equivalent safety
  # net for this fork's own data lives in Custom::UpdateCampaignRecipientStatusJob
  # (custom/app/jobs/custom/update_campaign_recipient_status_job.rb), exercised by
  # custom/spec/services/custom/whatsapp/incoming_message_base_service_spec.rb.
  it 'defers a campaign status when neither a recipient nor a message is persisted yet',
     pending: 'superseded by Custom::UpdateCampaignRecipientStatusJob — see comment above' do
    expect do
      Whatsapp::IncomingMessageService.new(
        inbox: channel.inbox,
        params: { 'statuses' => [status] }.with_indifferent_access
      ).perform
    end.to have_enqueued_job(Campaigns::UpdateRecipientStatusJob).with(channel.inbox.id, status).on_queue('low')
  end

  it 'does not update a recipient from another inbox' do
    other_account = create(:account)
    other_channel = create(:channel_whatsapp, account: other_account, sync_templates: false, validate_provider_config: false)
    other_campaign = create(:campaign, account: other_account, inbox: other_channel.inbox, campaign_type: :one_off)
    other_recipient = CampaignRecipient.create!(
      account: other_account,
      campaign: other_campaign,
      contact: create(:contact, account: other_account),
      inbox: other_channel.inbox,
      status: :sent,
      source_id: status['id']
    )

    Whatsapp::IncomingMessageService.new(
      inbox: channel.inbox,
      params: { 'statuses' => [status] }.with_indifferent_access
    ).perform

    expect(other_recipient.reload).to be_sent
  end
end
