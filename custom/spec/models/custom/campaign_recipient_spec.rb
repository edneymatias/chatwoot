# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::CampaignRecipient, type: :model do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:campaign) { create(:campaign, account: account, inbox: inbox) }
  let(:recipient) do
    described_class.create!(
      account: account,
      campaign: campaign,
      contact: contact,
      inbox: inbox
    )
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:campaign) }
    it { is_expected.to belong_to(:contact) }
    it { is_expected.to belong_to(:inbox) }
    it { is_expected.to belong_to(:campaign_message).optional }
  end

  describe 'validations' do
    it 'validates uniqueness of contact scoped to campaign' do
      recipient
      duplicate = described_class.new(
        account: account,
        campaign: campaign,
        contact: contact,
        inbox: inbox
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:contact_id]).to be_present
    end

    it 'validates uniqueness of source_id when present' do
      recipient.update!(source_id: 'wamid_123')
      other_contact = create(:contact, account: account)
      duplicate = described_class.new(
        account: account,
        campaign: campaign,
        contact: other_contact,
        inbox: inbox,
        source_id: 'wamid_123'
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:source_id]).to be_present
    end

    it 'validates uniqueness of reply_source_id when present' do
      recipient.update!(reply_source_id: 'reply_wamid_123')
      other_contact = create(:contact, account: account)
      duplicate = described_class.new(
        account: account,
        campaign: campaign,
        contact: other_contact,
        inbox: inbox,
        reply_source_id: 'reply_wamid_123'
      )
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:reply_source_id]).to be_present
    end
  end

  describe '#mark_sent!' do
    it 'transitions to sent and records sent_at and source_id' do
      recipient.mark_sent!('wamid_999')
      expect(recipient.status).to eq('sent')
      expect(recipient.source_id).to eq('wamid_999')
      expect(recipient.sent_at).to be_present
    end
  end

  describe '#mark_skipped!' do
    it 'transitions to skipped and records error_message' do
      recipient.mark_skipped!('Phone number missing')
      expect(recipient.status).to eq('skipped')
      expect(recipient.error_message).to eq('Phone number missing')
    end
  end

  describe '#mark_failed!' do
    it 'transitions to failed and records error details' do
      error = { code: '131026', title: 'Message undeliverable', message: 'Failed to deliver' }
      recipient.mark_failed!(error)
      expect(recipient.status).to eq('failed')
      expect(recipient.error_code).to eq('131026')
      expect(recipient.error_title).to eq('Message undeliverable')
      expect(recipient.error_message).to eq('Failed to deliver')
      expect(recipient.failed_at).to be_present
    end
  end

  describe '#update_from_whatsapp_status!' do
    it 'updates status to delivered' do
      recipient.mark_sent!('wamid_1')
      recipient.update_from_whatsapp_status!(status: 'delivered', timestamp: Time.current.to_i)
      expect(recipient.status).to eq('delivered')
      expect(recipient.delivered_at).to be_present
    end

    it 'updates status to read and does not downgrade if delivered webhook arrives late' do
      recipient.mark_sent!('wamid_1')
      recipient.update_from_whatsapp_status!(status: 'read', timestamp: Time.current.to_i)
      expect(recipient.status).to eq('read')
      expect(recipient.read_at).to be_present

      recipient.update_from_whatsapp_status!(status: 'delivered', timestamp: 1.minute.ago.to_i)
      expect(recipient.status).to eq('read')
      expect(recipient.delivered_at).to be_present
    end

    it 'does not downgrade read to failed via webhook' do
      recipient.mark_sent!('wamid_1')
      recipient.update_from_whatsapp_status!(status: 'read', timestamp: Time.current.to_i)
      recipient.update_from_whatsapp_status!(status: 'failed', timestamp: Time.current.to_i, errors: [{ code: '500' }])
      expect(recipient.status).to eq('read')
    end
  end

  describe '#mark_replied!' do
    it 'sets status to replied and records reply attributes' do
      recipient.mark_sent!('wamid_1')
      recipient.mark_replied!(reply_source_id: 'inbound_wamid', reply_type: :quick_reply, reply_label: 'Schedule Now')

      expect(recipient.status).to eq('replied')
      expect(recipient.reply_source_id).to eq('inbound_wamid')
      expect(recipient.reply_type).to eq('quick_reply')
      expect(recipient.reply_label).to eq('Schedule Now')
      expect(recipient.replied_at).to be_present
    end

    it 'preserves failed status when already failed but records reply attributes' do
      recipient.mark_failed!(code: '400', message: 'Something went wrong')
      recipient.mark_replied!(reply_source_id: 'inbound_wamid', reply_type: :free_text)

      expect(recipient.status).to eq('failed')
      expect(recipient.reply_source_id).to eq('inbound_wamid')
      expect(recipient.reply_type).to eq('free_text')
      expect(recipient.replied_at).to be_present
    end
  end
end
