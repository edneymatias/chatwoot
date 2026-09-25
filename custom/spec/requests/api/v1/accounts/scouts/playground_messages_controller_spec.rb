# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Scouts::PlaygroundMessages', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:scout) { Scout.create!(account: account, name: 'Playground Bot', enabled: true) }

  before do
    account.enable_features!('scout')
  end

  describe 'POST /api/v1/accounts/{account.id}/scouts/{scout.id}/playground_messages' do
    let(:valid_params) do
      {
        message: 'Qual o valor da mensalidade?',
        message_history: [
          { role: 'user', content: 'Olá' },
          { role: 'assistant', content: 'Olá! Como posso ajudar?' }
        ]
      }
    end

    context 'when scout_v2 feature flag is enabled' do
      before do
        account.enable_features!('scout_v2')
      end

      it 'resolves sandbox conversation and dispatches via TurnRunner' do
        sandbox_conversation = Custom::ScoutV2::PlaygroundConversation.for(scout)
        turn_runner_double = instance_double(
          Custom::ScoutV2::TurnRunner,
          perform: { reply: 'Resposta V2', tool_calls: [] }
        )

        expect(Custom::ScoutV2::TurnRunner).to receive(:new).with(
          scout: scout,
          conversation: sandbox_conversation,
          message: 'Qual o valor da mensalidade?',
          message_history: [
            { role: 'user', content: 'Olá' },
            { role: 'assistant', content: 'Olá! Como posso ajudar?' }
          ]
        ).and_return(turn_runner_double)

        post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
             params: valid_params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('reply' => 'Resposta V2', 'tool_calls' => [])
      end
    end

    context 'when scout_v2 feature flag is disabled' do
      it 'dispatches via existing Custom::Scout::PlaygroundRunner' do
        v1_runner_double = instance_double(
          Custom::Scout::PlaygroundRunner,
          perform: { reply: 'Resposta V1', tool_calls: [] }
        )

        expect(Custom::Scout::PlaygroundRunner).to receive(:new).with(
          scout: scout,
          message: 'Qual o valor da mensalidade?',
          message_history: [
            { role: 'user', content: 'Olá' },
            { role: 'assistant', content: 'Olá! Como posso ajudar?' }
          ]
        ).and_return(v1_runner_double)

        post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
             params: valid_params,
             headers: agent.create_new_auth_token

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq('reply' => 'Resposta V1', 'tool_calls' => [])
      end
    end

    it 'switches execution path immediately when toggling flag between requests' do
      v1_runner_double = instance_double(Custom::Scout::PlaygroundRunner, perform: { reply: 'V1', tool_calls: [] })
      turn_runner_double = instance_double(Custom::ScoutV2::TurnRunner, perform: { reply: 'V2', tool_calls: [] })

      allow(Custom::Scout::PlaygroundRunner).to receive(:new).and_return(v1_runner_double)
      allow(Custom::ScoutV2::TurnRunner).to receive(:new).and_return(turn_runner_double)

      # Turn 1: flag disabled -> V1
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
           params: valid_params,
           headers: agent.create_new_auth_token
      expect(response.parsed_body['reply']).to eq('V1')

      # Toggle flag on
      account.enable_features!('scout_v2')

      # Turn 2: flag enabled -> V2
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
           params: valid_params,
           headers: agent.create_new_auth_token
      expect(response.parsed_body['reply']).to eq('V2')

      # Toggle flag off
      account.disable_features!('scout_v2')

      # Turn 3: flag disabled -> V1
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
           params: valid_params,
           headers: agent.create_new_auth_token
      expect(response.parsed_body['reply']).to eq('V1')
    end

    it 'returns unprocessable entity when message is blank' do
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
           params: { message: '   ' },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('Message cannot be blank')
    end
  end
end
