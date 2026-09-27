# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

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

    context 'with the real Scout V2 engine (trigger interruption)' do
      let(:lead_stage) { PipelineStage.create!(account: account, name: 'Lead', position: 0) }
      let(:qualified_stage) { PipelineStage.create!(account: account, name: 'Qualificado', position: 1) }
      let(:unqualified_stage) { PipelineStage.create!(account: account, name: 'Desqualificado', position: 2) }
      let(:scout) do
        Scout.create!(
          account: account,
          name: 'V2 Real Scout',
          enabled: true,
          default_pipeline_stage: lead_stage,
          qualified_stage: qualified_stage,
          unqualified_stage: unqualified_stage
        )
      end
      let(:sandbox_conversation) { Custom::ScoutV2::PlaygroundConversation.for(scout) }
      let(:provider_requests) { [] }
      let(:provider_responses) { [] }

      around do |example|
        if example.metadata[:catalog] == :procedure_only
          Dir.mktmpdir('scout_v2_procedure_only_catalog') do |tmp_dir|
            FileUtils.cp(Rails.root.join('custom/playbooks/qualificacao.md'), File.join(tmp_dir, 'qualificacao.md'))
            with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
              example.run
            end
          end
        elsif example.metadata[:catalog] == :empty
          Dir.mktmpdir('scout_v2_empty_catalog') do |tmp_dir|
            with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
              example.run
            end
          end
        else
          Dir.mktmpdir('scout_v2_fixture_catalog') do |tmp_dir|
            FileUtils.cp(Rails.root.join('custom/playbooks/qualificacao.md'), File.join(tmp_dir, 'qualificacao.md'))
            File.write(File.join(tmp_dir, 'pausa.md'), <<~YAML)
              ---
              name: pausa
              title: Pausa solicitada
              priority: 20
              trigger: O cliente pede para pausar ou continuar a conversa mais tarde.
              ---

              ## Passos
              1. Confirme a pausa com gentileza.
            YAML
            File.write(File.join(tmp_dir, 'duvida_comercial.md'), <<~YAML)
              ---
              name: duvida_comercial
              title: Dúvidas Comerciais
              priority: 5
              trigger: O cliente tem dúvidas sobre preços, planos ou serviços comerciais.
              tools: [manage_opportunity]
              ---

              ## Passos
              1. Esclareça as dúvidas comerciais do cliente.
            YAML
            with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
              example.run
            end
          end
        end
      end

      before do
        account.enable_features!('scout', 'scout_v2', 'opportunities')
        ScoutAccountConfig.create!(account_id: account.id, api_key: 'test-key', model_name: 'gemini-2.0-flash')
        stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
          .with { |req| provider_requests << JSON.parse(req.body) }
          .to_return(*provider_responses)
      end

      shared_context 'with pinned procedure' do
        let!(:field) do
          CustomAttributeDefinition.create!(
            account: account,
            attribute_display_name: 'Orçamento',
            attribute_key: 'orcamento',
            attribute_model: :opportunity_attribute,
            attribute_display_type: :text
          )
        end

        before do
          Opportunity.create!(
            account: account,
            contact: sandbox_conversation.contact,
            pipeline_stage: lead_stage,
            origin_conversation: sandbox_conversation,
            active_conversation: sandbox_conversation,
            title: 'Playground Lead',
            status: :open
          )
          scout.sync_required_attribute_ids!([field.id])
        end
      end

      context 'when a procedure is pinned (AC1)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Qual o seu orçamento?' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'offers open_playbook and lists only situational playbooks in the index (FR-002, FR-003, SC-001, SC-002)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          expect(system_text).to include('- pausa: O cliente pede para pausar')
          expect(system_text).to include('- duvida_comercial: O cliente tem dúvidas sobre preços')
          expect(system_text).not_to include('- qualificacao:')

          offered_tools = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(offered_tools).to include('open_playbook')
        end
      end

      context 'when nothing is pinned (AC2)' do
        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Olá!' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'offers open_playbook and lists all playbooks in the index' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          expect(system_text).to include('- qualificacao:')
          expect(system_text).to include('- pausa:')
          expect(system_text).to include('- duvida_comercial:')

          offered_tools = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(offered_tools).to include('open_playbook')
        end
      end

      context 'when attempting to open a procedure playbook while pinned (AC3)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Continuando atendimento normal.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'returns tool error and continues the turn without writing trigger activation (FR-005, SC-003)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq('Continuando atendimento normal.')
          expect(provider_requests.size).to eq(2)

          tool_response_part = provider_requests[1].dig('contents', -1, 'parts')&.find { |p| p['functionResponse'] }
          tool_response_text = tool_response_part.dig('functionResponse', 'response', 'content', 0, 'text')
          expect(tool_response_text).to include('Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa')

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('state')
        end
      end

      context 'when pinned with a catalog having no situational playbooks (AC4)', catalog: :procedure_only do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Como posso ajudar?' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'does not offer open_playbook and renders empty index line (Edge Case 2, FR-003, FR-004)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          expect(system_text).to include('[Playbook Index]')
          expect(system_text).to include('Nenhum playbook disponível para abrir neste turno.')
          expect(system_text).not_to include('- qualificacao:')

          offered_tools = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(offered_tools).not_to include('open_playbook')
        end
      end

      context 'when nothing pinned with empty catalog (Edge Case 1)', catalog: :empty do
        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Olá!' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'does not offer open_playbook and renders empty index line (FR-003, FR-004)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          expect(system_text).to include('[Playbook Index]')
          expect(system_text).to include('Nenhum playbook disponível para abrir neste turno.')

          offered_tools = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(offered_tools).not_to include('open_playbook')
        end
      end

      context 'when assistant opens a situational playbook while pinned (US3 AC4)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Pausa confirmada com gentileza.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'records exactly one open_playbook tool call in the turn review record (FR-014)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)

          tool_calls = response.parsed_body['tool_calls']
          open_pb_calls = tool_calls.select { |c| c['tool_name'] == 'open_playbook' }
          expect(open_pb_calls.size).to eq(1)
          expect(open_pb_calls.first['arguments']).to eq({ 'name' => 'pausa' })
          expect(open_pb_calls.first.dig('result', 'body')).to include('Confirme a pausa com gentileza.')
        end
      end

      context 'when assistant opens a situational playbook and then searches knowledge base (US2 AC1-AC3)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'search_knowledge_base', args: { query: '' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Resposta após pausa e busca.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'replaces instructions and tools wholesale for remainder of turn (FR-006, FR-007, FR-008, SC-004)', :aggregate_failures do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)

          req1_system = provider_requests[1].dig('contents', 0, 'parts', 0, 'text')
          expect(req1_system).to include('[Playbook Index]')
          expect(req1_system).to include('- pausa:')
          expect(req1_system).to include('- duvida_comercial:')
          expect(req1_system).not_to include('- qualificacao:')
          expect(req1_system).not_to include('Pergunte pelos dados de qualificação pendentes')
          expect(req1_system).not_to include('Campos pendentes para esta oportunidade')

          open_resp = provider_requests[1].dig('contents', -1, 'parts')&.find { |p| p.dig('functionResponse', 'name') == 'open_playbook' }
          open_text = open_resp.dig('functionResponse', 'response', 'content', 0, 'text')
          expect(open_text).to include('Confirme a pausa com gentileza.')
          req1_tools = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(req1_tools).to contain_exactly('search_knowledge_base', 'open_playbook')
        end

        it 'records exactly open_playbook and search_knowledge_base in response tool_calls', :aggregate_failures do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(2)
          expect(tool_calls[0]['tool_name']).to eq('open_playbook')
          expect(tool_calls[0]['arguments']).to eq({ 'name' => 'pausa' })
          expect(tool_calls[0].dig('result', 'body')).to include('Confirme a pausa com gentileza.')
          expect(tool_calls[1]['tool_name']).to eq('search_knowledge_base')
          expect(tool_calls[1]['result']).to eq('Nenhum termo de busca fornecido.')
        end
      end

      context 'when assistant opens multiple situational playbooks consecutively (US2 AC4)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'duvida_comercial' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Final.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'replaces tools fully each time without accumulation (FR-009, FR-010, Edge Cases 3 and 4)' do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(4)

          tools1 = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools1).to contain_exactly('search_knowledge_base', 'open_playbook')

          tools2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools2).to contain_exactly('search_knowledge_base', 'open_playbook', 'manage_opportunity')

          tools3 = provider_requests[3].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools3).to contain_exactly('search_knowledge_base', 'open_playbook')

          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(3)
          expect(tool_calls.map { |c| c['tool_name'] }).to all(eq('open_playbook'))
        end
      end

      context 'when one response returns multiple function calls (FR-016, Edge Case 5)' do
        include_context 'with pinned procedure'

        let(:opportunity) { Opportunity.find_by!(origin_conversation: sandbox_conversation) }

        it 'prevents procedure tool execution when open_playbook precedes it in same step' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [
                        { functionCall: { name: 'open_playbook', args: { name: 'pausa' } } },
                        {
                          functionCall: {
                            name: 'manage_opportunity',
                            args: { action: 'update', opportunity_id: opportunity.id, custom_attributes: { 'orcamento' => '5000' } }
                          }
                        }
                      ]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Final.' }] }
                  }]
                }.to_json
              }
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)

          parts = provider_requests[1].dig('contents', -1, 'parts') || []
          manage_part = parts.find { |p| p.dig('functionResponse', 'name') == 'manage_opportunity' }
          expect(manage_part.dig('functionResponse', 'response', 'content', 0, 'text')).to include('unavailable tool')
          expect(opportunity.reload.custom_attributes).to be_blank
        end

        it 'executes procedure tool and preserves transcript when procedure tool precedes open_playbook' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [
                        {
                          functionCall: {
                            name: 'manage_opportunity',
                            args: { action: 'update', opportunity_id: opportunity.id, custom_attributes: { 'orcamento' => '5000' } }
                          }
                        },
                        { functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }
                      ]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Final.' }] }
                  }]
                }.to_json
              }
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          expect(opportunity.reload.custom_attributes['orcamento']).to eq('5000')

          model_parts = provider_requests[1].dig('contents', -2, 'parts') || []
          expect(model_parts.any? { |p| p.dig('functionCall', 'name') == 'manage_opportunity' }).to be true

          parts = provider_requests[1].dig('contents', -1, 'parts') || []
          expect(parts.any? { |p| p.dig('functionResponse', 'name') == 'manage_opportunity' }).to be true
          expect(parts.any? { |p| p.dig('functionResponse', 'name') == 'open_playbook' }).to be true
        end
      end

      context 'when situational playbook tool records data and next turn resumes procedure (FR-012 clause 3, FR-011)' do
        include_context 'with pinned procedure'

        let(:opportunity) { Opportunity.find_by!(origin_conversation: sandbox_conversation) }
        let(:detour_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'duvida_comercial' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [
                      {
                        functionCall: {
                          name: 'manage_opportunity',
                          args: { action: 'update', opportunity_id: opportunity.id, custom_attributes: { 'orcamento' => '5000' } }
                        }
                      }
                    ]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Esclarecido e atualizado.' }] }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Turno 2 resposta.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'preserves state across detour and reflects gathered data on subsequent turn', :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('qualificacao')
          snapshot = state.reload.attributes.dup

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*detour_responses)
          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          expect(opportunity.reload.custom_attributes['orcamento']).to eq('5000')
          manage_call = response.parsed_body['tool_calls'].find { |c| c['tool_name'] == 'manage_opportunity' }
          expect(manage_call).to be_present
          expected_args = {
            'action' => 'update',
            'opportunity_id' => opportunity.id,
            'custom_attributes' => { 'orcamento' => '5000' }
          }
          expect(manage_call['arguments']).to eq(expected_args)
          expect(state.reload.attributes).to eq(snapshot)

          # Turn 2
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params.merge(message: 'Continuando'),
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(4)
          turn2_system = provider_requests[3].dig('contents', 0, 'parts', 0, 'text')
          expect(turn2_system).to include('Pergunte pelos dados de qualificação pendentes')
          expect(turn2_system).not_to include('- Orçamento (chave: orcamento)')
        end
      end

      context 'when pinned procedure resumes after situational detour (US3 AC1, AC2)' do
        include_context 'with pinned procedure'

        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Pausa confirmada.' }] }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Voltando à qualificação.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'leaves conversation state untouched on turn 1 and resumes pinned procedure on turn 2' do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          travel_to(1.hour.ago) { state.record_state_activation!('qualificacao') }
          snapshot = state.reload.attributes.dup

          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          expect(state.reload.attributes).to eq(snapshot)

          # Turn 2
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params.merge(message: 'Voltei'),
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          turn2_system = provider_requests[2].dig('contents', 0, 'parts', 0, 'text')
          expect(turn2_system).to include('Pergunte pelos dados de qualificação pendentes')
          expect(turn2_system).to include('Campos pendentes para esta oportunidade')
        end
      end

      context 'when nothing pinned and situational playbook opened (US3 AC3)' do
        it 'creates no state row and keeps nothing pinned on next turn', :aggregate_failures do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Pausa confirmada.' }] }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Sem playbook ativa.' }] }
                  }]
                }.to_json
              }
            )

          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          expect(ScoutConversationState.where(conversation_id: sandbox_conversation.id)).to be_empty

          # Turn 2
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params.merge(message: 'Oi'),
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          turn2_system = provider_requests[2].dig('contents', 0, 'parts', 0, 'text')
          expect(turn2_system).not_to include('Pergunte pelos dados de qualificação pendentes')
          expect(turn2_system).not_to include('Confirme a pausa com gentileza.')
          expect(turn2_system).to include('[Playbook Index]')
          expect(ScoutConversationState.where(conversation_id: sandbox_conversation.id)).to be_empty
        end
      end

      context 'when nothing pinned and procedure playbook opened (US3 AC5, FR-013)' do
        it 'persists trigger activation on turn 1 and stays pinned on turn 2' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Iniciando qualificação.' }] }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Continuando qualificação.' }] }
                  }]
                }.to_json
              }
            )

          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('trigger')

          # Turn 2
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params.merge(message: 'Meu nome é João'),
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          turn2_system = provider_requests[2].dig('contents', 0, 'parts', 0, 'text')
          expect(turn2_system).to include('Pergunte pelos dados de qualificação pendentes')
        end
      end

      context 'when nothing pinned with sequence B then A (FR-017, Edge Case 6)' do
        let(:provider_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Final.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'preserves Path B state activation but replaces tools with situational baseline', :aggregate_failures do
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('trigger')

          tools_last = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_last).to contain_exactly('search_knowledge_base', 'open_playbook')

          index_last = provider_requests[2].dig('contents', 0, 'parts', 0, 'text')
          expect(index_last).to include('- qualificacao:')
          expect(index_last).to include('- pausa:')
          expect(index_last).to include('- duvida_comercial:')
        end
      end

      context 'when nothing pinned with sequence A then B (FR-017 A to B, Edge Case 6)' do
        it 'allows Path B procedure activation after Path A, persisting trigger activation and adding tools additively' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: {
                      role: 'model',
                      parts: [{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]
                    }
                  }]
                }.to_json
              },
              {
                status: 200,
                headers: { 'Content-Type' => 'application/json' },
                body: {
                  candidates: [{
                    content: { role: 'model', parts: [{ text: 'Final.' }] }
                  }]
                }.to_json
              }
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('qualificacao')
          expect(state.activation_reason).to eq('trigger')

          tools_last = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_last).to contain_exactly('search_knowledge_base', 'open_playbook', 'manage_opportunity')
        end
      end

      context 'when interrupted procedure is re-opened after a takeover (Edge Case 7)' do
        include_context 'with pinned procedure'

        let(:reopening_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'qualificacao' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Final.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'rejects reopening procedure after takeover, keeps baseline tools, and leaves state untouched', :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('qualificacao')
          snapshot = state.reload.attributes.dup

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*reopening_responses)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq('Final.')
          expect(provider_requests.size).to eq(3)
          expect(state.reload.attributes).to eq(snapshot)

          req1_system = provider_requests[1].dig('contents', 0, 'parts', 0, 'text')
          expect(req1_system).to include('[Playbook Index]')
          expect(req1_system).to include('- pausa:')
          expect(req1_system).to include('- duvida_comercial:')
          expect(req1_system).not_to include('- qualificacao:')
          err_part = provider_requests[2].dig('contents', -1, 'parts')&.find { |p| p['functionResponse'] }
          err_text = err_part.dig('functionResponse', 'response', 'content', 0, 'text')
          expect(err_text).to include('Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa')

          tools_req2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req2).to contain_exactly('search_knowledge_base', 'open_playbook')
        end
      end

      context 'when ongoing procedure was stored by trigger rather than state (Key Entity Pinned Procedure)' do
        let(:trigger_pin_responses) do
          [
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: {
                    role: 'model',
                    parts: [{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]
                  }
                }]
              }.to_json
            },
            {
              status: 200,
              headers: { 'Content-Type' => 'application/json' },
              body: {
                candidates: [{
                  content: { role: 'model', parts: [{ text: 'Final.' }] }
                }]
              }.to_json
            }
          ]
        end

        it 'treats trigger-stored pin as pinned at turn start' do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          travel_to(1.hour.ago) { state.record_trigger_activation!('qualificacao') }

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*trigger_pin_responses)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          req0_system = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          expect(req0_system).to include('Pergunte pelos dados de qualificação pendentes')
          expect(req0_system).to include('- pausa:')
          expect(req0_system).to include('- duvida_comercial:')
          expect(req0_system).not_to include('- qualificacao:')
          req0_tools = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(req0_tools).to contain_exactly('search_knowledge_base', 'manage_opportunity', 'open_playbook')
        end

        it 'drops procedure body on situational takeover while preserving stored trigger state' do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          travel_to(1.hour.ago) { state.record_trigger_activation!('qualificacao') }
          snapshot = state.reload.attributes.dup

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*trigger_pin_responses)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          req1_system = provider_requests[1].dig('contents', 0, 'parts', 0, 'text')
          expect(req1_system).not_to include('Pergunte pelos dados de qualificação pendentes')
          req1_tools = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(req1_tools).to contain_exactly('search_knowledge_base', 'open_playbook')
          expect(state.reload.attributes).to eq(snapshot)
          expect(state.trigger?).to be true
        end
      end
    end
  end
end
