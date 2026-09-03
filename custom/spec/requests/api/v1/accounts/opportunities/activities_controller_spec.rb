# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Opportunities::Activities', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:contact) { create(:contact, account: account) }
  let(:opportunity) { Opportunity.create!(account: account, title: 'Opportunity 1', pipeline_stage: stage, contact: contact) }

  before do
    account.enable_features!('opportunities')
  end

  describe 'GET /api/v1/accounts/{account.id}/opportunities/{opportunity.id}/activities' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id), as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated' do
      let!(:act1) do
        opportunity.activities.create!(
          account: account,
          event_type: 'opportunity_created',
          actor: user,
          metadata: {},
          occurred_at: 2.hours.ago
        )
      end
      let!(:act2) do
        opportunity.activities.create!(
          account: account,
          event_type: 'opportunity_stage_changed',
          actor: user,
          metadata: { 'from_stage_id' => stage.id, 'to_stage_id' => stage.id },
          occurred_at: 1.hour.ago
        )
      end

      it 'returns the list of activities ordered by occurred_at descending' do
        get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id),
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.pluck('id')).to eq([act2.id, act1.id])
        expect(json.first['event_type']).to eq('opportunity_stage_changed')
        expect(json.first['actor']['name']).to eq(user.name)
        expect(json.first.slice('conversation_status', 'conversation_viewable')).to be_empty
      end

      context 'with conversation event types' do
        let(:inbox) { create(:inbox, account: account) }
        let(:inbox_restricted) { create(:inbox, account: account) }
        let(:conv_open) { create(:conversation, account: account, inbox: inbox, status: :open) }
        let(:conv_resolved) { create(:conversation, account: account, inbox: inbox, status: :resolved) }
        let(:conv_restricted) { create(:conversation, account: account, inbox: inbox_restricted, status: :pending) }

        before do
          create(:inbox_member, user: user, inbox: inbox)
        end

        it 'enriches viewable conversation events with status and viewable true' do
          act_open = opportunity.activities.create!(
            account: account,
            event_type: 'conversation_opened',
            actor: user,
            metadata: { 'conversation_id' => conv_open.id, 'conversation_display_id' => conv_open.display_id },
            occurred_at: 4.hours.ago
          )
          act_resolved = opportunity.activities.create!(
            account: account,
            event_type: 'conversation_transferred_in',
            actor: user,
            metadata: { 'conversation_id' => conv_resolved.id, 'conversation_display_id' => conv_resolved.display_id },
            occurred_at: 3.hours.ago
          )

          get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id),
              headers: user.create_new_auth_token,
              as: :json

          by_id = response.parsed_body.index_by { |item| item['id'] }
          expect(by_id[act_open.id].slice('conversation_status', 'conversation_viewable')).to eq(
            { 'conversation_status' => 'open', 'conversation_viewable' => true }
          )
          expect(by_id[act_resolved.id].slice('conversation_status', 'conversation_viewable')).to eq(
            { 'conversation_status' => 'resolved', 'conversation_viewable' => true }
          )
        end

        it 'sets viewable false for restricted or nonexistent conversations' do
          act_restricted = opportunity.activities.create!(
            account: account,
            event_type: 'conversation_transferred_out',
            actor: user,
            metadata: { 'conversation_id' => conv_restricted.id, 'conversation_display_id' => conv_restricted.display_id },
            occurred_at: 2.hours.ago
          )
          act_missing = opportunity.activities.create!(
            account: account,
            event_type: 'conversation_detached',
            actor: user,
            metadata: { 'conversation_id' => 999_999, 'conversation_display_id' => 999_999 },
            occurred_at: 1.hour.ago
          )

          get api_v1_account_opportunity_activities_url(account_id: account.id, opportunity_id: opportunity.id),
              headers: user.create_new_auth_token,
              as: :json

          by_id = response.parsed_body.index_by { |item| item['id'] }
          expect(by_id[act_restricted.id].slice('conversation_status', 'conversation_viewable')).to eq(
            { 'conversation_status' => 'pending', 'conversation_viewable' => false }
          )
          expect(by_id[act_missing.id].slice('conversation_status', 'conversation_viewable')).to eq(
            { 'conversation_status' => nil, 'conversation_viewable' => false }
          )
        end
      end
    end
  end
end
