# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::FollowUpJob, type: :job do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, email: 'contact@example.com') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox, status: :pending)
  end
  let(:initial_stage) { PipelineStage.create!(account: account, name: 'Lead Qualified') }
  let(:rescue_stage) { PipelineStage.create!(account: account, name: 'Rescue Stage') }
  let(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      title: 'Enterprise Deal',
      pipeline_stage: initial_stage,
      status: :open
    )
  end
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Follow-Up Scout',
      enabled: true,
      rescue_stage: rescue_stage,
      follow_up_delays_hours: [2, 12, 24]
    )
  end

  before do
    ScoutInbox.create!(scout: scout, inbox: inbox)
    OpportunityConversation.create!(account: account, opportunity: opportunity, conversation: conversation)
  end

  describe '#perform' do
    context 'when conversation has exceeded the first threshold (2 hours)' do
      before do
        conversation.update!(last_activity_at: 3.hours.ago)
      end

      it 'sends the first re-engagement nudge and leaves conversation pending' do
        expect do
          described_class.perform_now
        end.to change(conversation.messages, :count).by(1)

        message = conversation.messages.last
        expect(message.message_type).to eq('outgoing')
        expect(message.private).to be(false)
        expect(message.content_attributes['scout_follow_up']).to be(true)
        expect(message.content).to eq(I18n.t('conversations.scout.follow_up_nudge', locale: conversation.account.locale))
        expect(conversation.reload.status).to eq('pending')
        expect(opportunity.reload.pipeline_stage_id).to eq(initial_stage.id)
      end

      it 'does not send a second nudge if 12 hours have not passed yet' do
        described_class.perform_now # sends 1st nudge
        # Conversation last_activity_at was updated when the 1st nudge was created, or is only 3 hours past initial
        conversation.update!(last_activity_at: 5.hours.ago)

        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end
    end

    context 'when conversation has exceeded the second threshold (12 hours)' do
      before do
        # Contact message followed by 1st nudge
        conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: 'Oi')
        conversation.messages.create!(
          account: account, inbox: inbox, message_type: :outgoing, private: false,
          content: 'Nudge 1', content_attributes: { scout_follow_up: true }
        )
        conversation.update!(last_activity_at: 13.hours.ago)
      end

      it 'sends the second re-engagement nudge and leaves conversation pending' do
        expect do
          described_class.perform_now
        end.to change(conversation.messages, :count).by(1)

        message = conversation.messages.last
        expect(message.message_type).to eq('outgoing')
        expect(message.content_attributes['scout_follow_up']).to be(true)
        expect(conversation.reload.status).to eq('pending')
        expect(opportunity.reload.pipeline_stage_id).to eq(initial_stage.id)
      end
    end

    context 'when evaluating second nudge timing after real first nudge execution' do
      it 'sends nudge 2 based on total silence from contact rather than compounding off nudge 1' do
        initial_time = 13.hours.ago
        conversation.update!(created_at: initial_time, last_activity_at: initial_time)
        conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: 'Oi',
                                      created_at: initial_time)

        # Fast-forward to 3 hours past initial message (exceeding threshold 1 of 2h)
        travel_to(initial_time + 3.hours) do
          expect do
            described_class.perform_now
          end.to change(conversation.messages, :count).by(1)

          expect(conversation.reload.messages.last.content_attributes['scout_follow_up']).to be(true)
        end

        # Fast-forward to 13 hours past initial message (10h after nudge 1).
        # Total silence from contact = 13h (exceeds 12h threshold 2).
        travel_to(initial_time + 13.hours) do
          expect do
            described_class.perform_now
          end.to change(conversation.messages, :count).by(1)

          expect(conversation.reload.messages.last.content_attributes['scout_follow_up']).to be(true)
          expect(conversation.reload.status).to eq('pending')
        end
      end
    end

    context 'when contact replies after a nudge' do
      before do
        conversation.messages.create!(
          account: account, inbox: inbox, message_type: :outgoing, private: false,
          content: 'Nudge 1', content_attributes: { scout_follow_up: true }
        )
        # Contact replies
        conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: 'Estou aqui!')
        conversation.update!(last_activity_at: 1.hour.ago)
      end

      it 'resets follow_up_attempts and does not send a second nudge' do
        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end
    end

    context 'when conversation is no longer pending at execution time' do
      before do
        conversation.update!(last_activity_at: 3.hours.ago, status: :open)
      end

      it 'takes no action and sends no messages' do
        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end
    end

    context 'when final threshold (24 hours) is exceeded' do
      before do
        conversation.messages.create!(account: account, inbox: inbox, sender: contact, message_type: :incoming, content: 'Oi')
        conversation.messages.create!(
          account: account, inbox: inbox, message_type: :outgoing, private: false,
          content: 'Nudge 1', content_attributes: { scout_follow_up: true }
        )
        conversation.messages.create!(
          account: account, inbox: inbox, message_type: :outgoing, private: false,
          content: 'Nudge 2', content_attributes: { scout_follow_up: true }
        )
        conversation.update!(last_activity_at: 25.hours.ago)
      end

      it 'moves opportunity to rescue stage and hands off conversation with continuity message' do
        described_class.perform_now

        expect(opportunity.reload.pipeline_stage_id).to eq(rescue_stage.id)
        expect(opportunity.status).to eq('open')
        expect(conversation.reload.status).to eq('open')

        public_handoff = conversation.messages.where(private: false, message_type: :outgoing).last
        expect(public_handoff.content).to eq(I18n.t('conversations.scout.follow_up_handoff', locale: conversation.account.locale))

        private_note = conversation.messages.where(private: true).last
        expect(private_note.content).to include('Transferência para atendimento humano')
        expect(private_note.content).to include("Oportunidade ##{opportunity.id}")
      end
    end

    context 'when scout has no rescue stage configured' do
      before do
        scout.update!(rescue_stage: nil)
        conversation.update!(last_activity_at: 3.hours.ago)
      end

      it 'skips processing entirely' do
        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end
    end

    context 'when linked opportunity is not open' do
      before do
        opportunity.update!(status: :won)
        conversation.update!(last_activity_at: 3.hours.ago)
      end

      it 'skips processing when opportunity is won' do
        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end

      it 'skips processing when opportunity is lost' do
        opportunity.update!(status: :lost)

        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end
    end

    context 'when inbox is out of office' do
      before do
        conversation.update!(last_activity_at: 3.hours.ago)
        inbox.update!(working_hours_enabled: true)
        inbox.working_hours.today.update!(closed_all_day: true)
      end

      it 'suppresses nudges during out of office hours' do
        expect do
          described_class.perform_now
        end.not_to change(conversation.messages, :count)
      end

      it 'delivers nudge once back in office' do
        inbox.working_hours.today.update!(closed_all_day: false, open_all_day: true)

        expect do
          described_class.perform_now
        end.to change(conversation.messages, :count).by(1)
      end
    end
  end
end
