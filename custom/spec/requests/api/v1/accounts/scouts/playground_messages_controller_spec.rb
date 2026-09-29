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

      let(:gemini_step) do
        lambda do |parts|
          {
            status: 200,
            headers: { 'Content-Type' => 'application/json' },
            body: { candidates: [{ content: { role: 'model', parts: parts } }] }.to_json
          }
        end
      end

      around do |example|
        if example.metadata[:catalog] == :procedure_only
          Dir.mktmpdir('scout_v2_procedure_only_catalog') do |tmp_dir|
            FileUtils.cp(Rails.root.join('custom/spec/fixtures/scout_v2/qualificacao_procedure.md'), File.join(tmp_dir, 'qualificacao.md'))
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
            FileUtils.cp(Rails.root.join('custom/spec/fixtures/scout_v2/qualificacao_procedure.md'), File.join(tmp_dir, 'qualificacao.md'))
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

          open_playbook_decl = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.find { |f| f['name'] == 'open_playbook' }
          expect(open_playbook_decl).to be_present
          expect(open_playbook_decl['description']).to eq('Open a playbook by name from the playbook index to activate its procedure and tools')
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
          expect(req1_tools).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')
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
          expect(tools1).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')

          tools2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools2).to contain_exactly('search_knowledge_base', 'open_playbook', 'manage_opportunity', 'exit_handoff')

          tools3 = provider_requests[3].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools3).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')

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
          expect(state.reload.attributes.except('unsatisfied_flags', 'updated_at')).to eq(snapshot.except('unsatisfied_flags', 'updated_at'))
          expect(state.unsatisfied_flags).to be_present

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

        it 'leaves conversation state untouched on turn 1 and resumes pinned procedure on turn 2', :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          travel_to(1.hour.ago) { state.record_state_activation!('qualificacao') }
          snapshot = state.reload.attributes.dup

          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          expect(state.reload.attributes.except('unsatisfied_flags', 'updated_at')).to eq(snapshot.except('unsatisfied_flags', 'updated_at'))
          expect(state.unsatisfied_flags).to be_present

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
              gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
              gemini_step.call([{ text: 'Pausa confirmada.' }]),
              gemini_step.call([{ text: 'Sem playbook ativa.' }])
            )

          # Turn 1
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)
          state1 = ScoutConversationState.find_by(conversation_id: sandbox_conversation.id)
          expect(state1).to be_present
          expect(state1.active_playbook).to be_nil
          expect(state1.unsatisfied_flags['procedure']).to be_nil

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
          state2 = ScoutConversationState.find_by(conversation_id: sandbox_conversation.id)
          expect(state2).to be_present
          expect(state2.active_playbook).to be_nil
          expect(state2.unsatisfied_flags['procedure']).to be_nil
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
          expect(tools_last).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')

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
          expect(tools_last).to contain_exactly('search_knowledge_base', 'open_playbook', 'manage_opportunity', 'exit_handoff')
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
          expect(state.reload.attributes.except('unsatisfied_flags', 'updated_at')).to eq(snapshot.except('unsatisfied_flags', 'updated_at'))
          expect(state.unsatisfied_flags).to be_present

          req1_system = provider_requests[1].dig('contents', 0, 'parts', 0, 'text')
          expect(req1_system).to include('[Playbook Index]')
          expect(req1_system).to include('- pausa:')
          expect(req1_system).to include('- duvida_comercial:')
          expect(req1_system).not_to include('- qualificacao:')
          err_part = provider_requests[2].dig('contents', -1, 'parts')&.find { |p| p['functionResponse'] }
          err_text = err_part.dig('functionResponse', 'response', 'content', 0, 'text')
          expect(err_text).to include('Playbook desconhecida: qualificacao. Disponíveis: duvida_comercial, pausa')

          tools_req2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req2).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')
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
          expect(req0_tools).to contain_exactly('search_knowledge_base', 'manage_opportunity', 'open_playbook', 'exit_handoff')
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
          expect(req1_tools).to contain_exactly('search_knowledge_base', 'open_playbook', 'exit_handoff')
          expect(state.reload.attributes.except('unsatisfied_flags', 'updated_at')).to eq(snapshot.except('unsatisfied_flags', 'updated_at'))
          expect(state.unsatisfied_flags).to be_present
          expect(state.trigger?).to be true
        end
      end

      context 'with Scout V2 exits and escalation (US1)' do
        it 'verifies US1-AS1 and US1-AS5: system text headers end with Playbook Index, Escalation and CLOSING_INSTRUCTION is absent' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(gemini_step.call([{ text: 'Olá, como posso ajudar?' }]))

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          headers = system_text.scan(/^\[([^\]]+)\]$/).flatten
          expect(headers.last(2)).to eq(['Playbook Index', 'Escalation'])
          expect(system_text).not_to include('sem perguntas')
          expect(system_text).not_to include('encerramento')
        end

        it 'verifies US1-AS2 and US1-AS3: exit_handoff declared in provider requests with nothing pinned, pinned, and after takeover' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
              gemini_step.call([{ text: 'Pausa confirmada.' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)

          tools_req0 = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req0).to include('exit_handoff')
          handoff_decl = provider_requests[0].dig('tools', 0, 'functionDeclarations').find { |f| f['name'] == 'exit_handoff' }
          expect(handoff_decl['parameters']).to eq(
            'type' => 'OBJECT',
            'properties' => { 'reason' => { 'type' => 'STRING' } },
            'required' => ['reason']
          )

          tools_req1 = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req1).to include('exit_handoff')
        end

        it 'verifies FR-023: playground exit_handoff records last_exit == handoff, clears active procedure, and lists tool call',
           :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('qualificacao')

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Cliente pediu atendente humano' } } }]),
              gemini_step.call([{ text: 'Um atendente já dará continuidade ao seu atendimento.' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(sandbox_conversation.reload.status).to eq('open')
          expect(sandbox_conversation.team_id).to be_nil
          expect(sandbox_conversation.messages.where(private: true)).to be_empty

          expect(state.reload.last_exit).to eq('handoff')
          expect(state.active_playbook).to be_nil

          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(1)
          expect(tool_calls[0]['tool_name']).to eq('exit_handoff')
          expect(tool_calls[0]['arguments']).to eq('reason' => 'Cliente pediu atendente humano')
          expect(tool_calls[0]['result']).to include('Transferência para atendimento humano realizada.')
          expect(tool_calls[0]['result']).to include('Escreva agora sua resposta final ao cliente')
        end

        it 'verifies FR-015: a call after exit_handoff in the same turn returns TURN_ENDED_ERROR and is recorded' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call(
                [
                  { functionCall: { name: 'exit_handoff', args: { reason: 'Primeiro encerra' } } },
                  { functionCall: { name: 'search_knowledge_base', args: { query: 'duvida' } } }
                ]
              ),
              gemini_step.call([{ text: 'Até logo.' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(2)
          expect(tool_calls[0]['tool_name']).to eq('exit_handoff')
          expect(tool_calls[1]['tool_name']).to eq('search_knowledge_base')
          expect(tool_calls[1]['result']).to eq('error' => Custom::ScoutV2::TurnScope::TURN_ENDED_ERROR)
        end
      end

      context 'with Scout V2 declared exits (US2)' do
        around do |example|
          Dir.mktmpdir('scout_v2_us2_catalog') do |tmp_dir|
            File.write(File.join(tmp_dir, 'fluxo_teste.md'), <<~MD)
              ---
              name: fluxo_teste
              title: Fluxo de teste
              priority: 20
              when_state:
                - opportunity_open
              trigger: Fixture com exits declarados.
              tools: [manage_opportunity]
              exits:
                concluido:
                  kind: terminal
                  fields: { resumo: string }
                seguir_outro:
                  kind: transition
                  target: outro_procedimento
                qualificado:
                  kind: escalation
                  fields: { quantidade: integer, motivo: string, retorno_em: datetime }
              ---
              Passos do fluxo teste.
            MD

            File.write(File.join(tmp_dir, 'outro_procedimento.md'), <<~MD)
              ---
              name: outro_procedimento
              title: Outro Procedimento
              priority: 15
              when_state:
                - opportunity_open
              trigger: Procedimento destino da transicao.
              tools: []
              exits:
                finalizado:
                  kind: terminal
                  fields: { detalhe: string }
                voltar_teste:
                  kind: transition
                  target: fluxo_teste
              ---
              Passos do outro procedimento.
            MD

            File.write(File.join(tmp_dir, 'pausa.md'), <<~MD)
              ---
              name: pausa
              title: Pausa
              priority: 50
              trigger: Pausa
              ---
              Corpo da pausa.
            MD

            with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
              example.run
            end
          end
        end

        it 'verifies US2-AS1: declared exits present only while their playbook is in effect' do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_teste')

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
              gemini_step.call([{ text: 'Pausa confirmada.' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token
          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(2)

          tools_req0 = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req0).to include('exit_concluido', 'exit_seguir_outro', 'exit_qualificado', 'exit_handoff')
          declarations_req0 = provider_requests[0].dig('tools', 0, 'functionDeclarations').index_by { |f| f['name'] }
          expect(declarations_req0['exit_qualificado']['parameters']).to eq(
            'type' => 'OBJECT',
            'properties' => {
              'quantidade' => { 'type' => 'INTEGER' },
              'motivo' => { 'type' => 'STRING' },
              'retorno_em' => { 'type' => 'STRING', 'format' => 'date-time' }
            },
            'required' => %w[quantidade motivo retorno_em]
          )
          expect(declarations_req0['exit_seguir_outro']).not_to have_key('parameters')

          tools_req1 = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req1).not_to include('exit_concluido', 'exit_seguir_outro', 'exit_qualificado')
          expect(tools_req1).to include('exit_handoff')
        end

        it 'verifies US2-AS10 and FR-007: refuses second procedure when one was opened mid-turn', :aggregate_failures do
          steps = [
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fluxo_teste' } } }]),
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'outro_procedimento' } } }]),
            gemini_step.call([{ text: 'Continuando com fluxo teste.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(2)
          expect(tool_calls[0]['tool_name']).to eq('open_playbook')
          expect(tool_calls[0].dig('result', 'body')).to include('Passos do fluxo teste.')

          expect(tool_calls[1]['tool_name']).to eq('open_playbook')
          expect(tool_calls[1].dig('result', 'error')).to include('Já existe um procedimento em andamento neste turno: fluxo_teste')

          tools_req1 = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req1).to include('exit_concluido', 'exit_seguir_outro', 'exit_qualificado')

          tools_req2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')
          expect(tools_req2).to eq(provider_requests[1].dig('tools', 0, 'functionDeclarations'))

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('fluxo_teste')
          expect(state.last_exit).to be_nil
        end

        it 'verifies US2-AS10 and FR-007: refuses procedure after a transition in the same turn', :aggregate_failures do
          steps = [
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fluxo_teste' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_seguir_outro', args: {} } }]),
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fluxo_teste' } } }]),
            gemini_step.call([{ text: 'Continuando com outro procedimento.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(3)
          expect(tool_calls[0]['tool_name']).to eq('open_playbook')
          expect(tool_calls[1]['tool_name']).to eq('exit_seguir_outro')
          expect(tool_calls[2]['tool_name']).to eq('open_playbook')
          expect(tool_calls[2].dig('result', 'error')).to include('Já existe um procedimento em andamento neste turno: outro_procedimento')

          tools_req2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')
          tools_req3 = provider_requests[3].dig('tools', 0, 'functionDeclarations')
          expect(tools_req3).to eq(tools_req2)

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.active_playbook).to eq('outro_procedimento')
          expect(state.activation_reason).to eq('transition')
          expect(state.transition_count).to eq(1)
          expect(state.last_exit).to be_nil
        end

        it 'verifies US2-AS2, US2-AS3, and US2-AS9: invalid payload rejected then corrected in same turn, terminal data in tool_calls',
           :aggregate_failures do
          contact = sandbox_conversation.contact.reload
          contact_snapshot = contact.attributes.dup
          opportunity = Opportunity.create!(
            account: account,
            contact: contact,
            active_conversation: sandbox_conversation,
            origin_conversation: sandbox_conversation,
            title: 'Negócio Teste',
            pipeline_stage: lead_stage
          ).reload
          opportunity_snapshot = opportunity.attributes.dup

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_teste')
          steps = [
            gemini_step.call([{ functionCall: { name: 'exit_concluido', args: { resumo: 123, extra: 'bad' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_concluido', args: { resumo: 'Atendimento concluído' } } }]),
            gemini_step.call([{ text: 'Tudo pronto e resolvido!' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)
          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq('Tudo pronto e resolvido!')

          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(2)
          expect(tool_calls[0]['result']['error']).to include("campo 'resumo' deve ser string", "campo 'extra' não declarado")
          expect(tool_calls[1]['result']).to eq("Desfecho 'concluido' registrado. Escreva agora sua resposta final ao cliente.")
          expect(tool_calls[1]['arguments']).to eq('resumo' => 'Atendimento concluído')

          expect(state.reload.last_exit).to eq('concluido')
          expect(state.active_playbook).to be_nil

          expect(opportunity.reload.attributes).to eq(opportunity_snapshot)
          expect(contact.reload.attributes).to eq(contact_snapshot)
        end

        it 'verifies US2-AS5: transition returns target body and subsequent step offers target exits',
           :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_teste')

          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call([{ functionCall: { name: 'exit_seguir_outro', args: {} } }]),
              gemini_step.call([{ text: 'Seguindo para o outro procedimento.' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(1)
          expect(tool_calls[0]['result']).to include('Passos do outro procedimento.')

          req1_system = provider_requests[1].dig('contents', 0, 'parts', 0, 'text')
          expect(req1_system).not_to include('Passos do fluxo teste.')

          tools_req1 = provider_requests[1].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tools_req1).to include('exit_finalizado', 'exit_handoff')
          expect(tools_req1).not_to include('exit_concluido', 'exit_seguir_outro', 'manage_opportunity')

          expect(state.reload.active_playbook).to eq('outro_procedimento')
          expect(state.activation_reason).to eq('transition')
          expect(state.transition_count).to eq(1)
        end

        it 'verifies FR-016 and FR-024: same-step transition followed by obsolete exit records unavailable-tool error',
           :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_teste')

          steps = [
            gemini_step.call(
              [
                { functionCall: { name: 'exit_seguir_outro', args: {} } },
                { functionCall: { name: 'exit_concluido', args: { resumo: 'Fechando antes da hora' } } }
              ]
            ),
            gemini_step.call([{ text: 'Transição realizada com sucesso.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(2)
          expect(tool_calls[0]['tool_name']).to eq('exit_seguir_outro')
          expect(tool_calls[1]['tool_name']).to eq('exit_concluido')
          expect(tool_calls[1].dig('result', 'error')).to include("Model tried to call unavailable tool 'exit_concluido'")

          expect(state.reload.active_playbook).to eq('outro_procedimento')
          expect(state.last_exit).to be_nil
        end

        it 'verifies FR-011 and Edge Cases: third transition in one turn returns TRANSITION_LIMIT_ERROR and sets handoff_limit_reached_at',
           :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_teste')

          steps = [
            gemini_step.call([{ functionCall: { name: 'exit_seguir_outro', args: {} } }]),
            gemini_step.call([{ functionCall: { name: 'exit_voltar_teste', args: {} } }]),
            gemini_step.call([{ functionCall: { name: 'exit_seguir_outro', args: {} } }]),
            gemini_step.call([{ text: 'Limite de transições atingido, encerrando atendimento.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(3)
          expect(tool_calls[0]['tool_name']).to eq('exit_seguir_outro')
          expect(tool_calls[1]['tool_name']).to eq('exit_voltar_teste')
          expect(tool_calls[2]['tool_name']).to eq('exit_seguir_outro')

          expected_limit_error = format(Custom::ScoutV2::Exits::Transition::TRANSITION_LIMIT_ERROR, target: 'outro_procedimento')
          expect(tool_calls[2].dig('result', 'error')).to eq(expected_limit_error)

          expect(state.reload.handoff_limit_reached_at).to be_present
          expect(state.active_playbook).to eq('fluxo_teste')
          expect(state.activation_reason).to eq('transition')
          expect(state.transition_count).to eq(2)
          expect(state.last_exit).to be_nil

          tools_req2 = provider_requests[2].dig('tools', 0, 'functionDeclarations')
          tools_req3 = provider_requests[3].dig('tools', 0, 'functionDeclarations')
          expect(tools_req3).to eq(tools_req2)
        end
      end

      context 'with Scout V2 tool catalog and stage moves (US3)' do
        around do |example|
          Dir.mktmpdir('scout_v2_us3_catalog') do |tmp_dir|
            File.write(File.join(tmp_dir, 'fluxo_ambos.md'), <<~MD)
              ---
              name: fluxo_ambos
              title: Fluxo com ambos os tools
              priority: 20
              when_state:
                - opportunity_open
              trigger: Ambos os tools disponiveis.
              tools: [update_contact, manage_opportunity]
              exits:
                fechar:
                  kind: terminal
                  stage: qualified
              ---
              Passos com ambos.
            MD

            File.write(File.join(tmp_dir, 'pausa.md'), <<~MD)
              ---
              name: pausa
              title: Pausa
              priority: 50
              trigger: Pausar atendimento.
              ---
              Pausa situacional.
            MD

            with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
              example.run
            end
          end
        end

        it 'verifies US3-AS1, SC-006, and US3-AS5: removed tools never offered with nothing pinned, after mid-turn open, or after takeover',
           :aggregate_failures do
          steps = [
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fluxo_ambos' } } }]),
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'pausa' } } }]),
            gemini_step.call([{ text: 'Atendimento pausado.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(3)

          provider_requests.each do |req|
            tool_names = req.dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
            expect(tool_names).not_to include('move_opportunity_stage', 'handover_to_human', 'call_custom_api')
          end

          # Request 0: nothing pinned
          req0_names = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(req0_names).to include('search_knowledge_base', 'exit_handoff', 'open_playbook')
          expect(req0_names).not_to include('manage_opportunity', 'update_contact', 'exit_fechar')

          # Request 1: after mid-turn procedure open
          req1_tools = provider_requests[1].dig('tools', 0, 'functionDeclarations') || []
          req1_names = req1_tools.map { |f| f['name'] }
          expect(req1_names).to include('manage_opportunity', 'update_contact', 'exit_fechar', 'exit_handoff')
          manage_decl = req1_tools.find { |f| f['name'] == 'manage_opportunity' }
          expect(manage_decl.dig('parameters', 'properties')&.keys).not_to include('stage_id')

          # Request 2: after situational takeover
          req2_names = provider_requests[2].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(req2_names).to include('search_knowledge_base', 'exit_handoff', 'open_playbook')
          expect(req2_names).not_to include('manage_opportunity', 'update_contact', 'exit_fechar')
        end

        it 'verifies US3-AS2, US3-AS3, and US1-AS6: stage move with missing required fields fails, succeeds after fill without closing instruction',
           :aggregate_failures do
          orcamento_def = CustomAttributeDefinition.create!(
            account: account,
            attribute_key: 'orcamento',
            attribute_display_name: 'Orçamento',
            attribute_model: 'opportunity_attribute',
            attribute_display_type: 'number'
          )
          ScoutRequiredField.create!(scout: scout, custom_attribute_definition: orcamento_def)

          opportunity = Opportunity.create!(
            account: account,
            contact: sandbox_conversation.contact,
            active_conversation: sandbox_conversation,
            origin_conversation: sandbox_conversation,
            title: 'Negócio Sandbox',
            pipeline_stage: lead_stage
          )

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_ambos')

          steps = [
            gemini_step.call([{ functionCall: { name: 'exit_fechar', args: {} } }]),
            gemini_step.call(
              [
                { functionCall: {
                  name: 'manage_opportunity',
                  args: { action: 'update', opportunity_id: opportunity.id, custom_attributes: { 'orcamento' => '5000' } }
                } },
                { functionCall: { name: 'exit_fechar', args: {} } }
              ]
            ),
            gemini_step.call([{ text: 'Oportunidade qualificada com sucesso!' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(3)

          # First exit attempt failed due to missing orcamento
          expect(tool_calls[0]['tool_name']).to eq('exit_fechar')
          expect(tool_calls[0]['result']['error']).to include('Orçamento')

          # Second attempt succeeded after filling orcamento
          expect(tool_calls[1]['tool_name']).to eq('manage_opportunity')
          expect(tool_calls[2]['tool_name']).to eq('exit_fechar')
          expect(tool_calls[2]['result']).to eq("Desfecho 'fechar' registrado. Escreva agora sua resposta final ao cliente.")
          expect(tool_calls[2]['result']).not_to include('sem perguntas')
          expect(tool_calls[2]['result']).not_to include('encerramento')

          expect(opportunity.reload.pipeline_stage_id).to eq(qualified_stage.id)
          expect(state.reload.last_exit).to eq('fechar')
        end

        it 'verifies FR-014 and Edge Cases: stage-declaring exit errors when no active opportunity exists' do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_ambos')

          steps = [
            gemini_step.call([{ functionCall: { name: 'exit_fechar', args: {} } }]),
            gemini_step.call([{ text: 'Não foi possível mover o estágio pois não há oportunidade.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(1)
          expect(tool_calls[0]['tool_name']).to eq('exit_fechar')
          expect(tool_calls[0].dig('result', 'error')).to eq('A oportunidade não pode mudar de estágio: a conversa não tem oportunidade.')

          expect(state.reload.last_exit).to be_nil
        end

        it 'verifies FR-014 and Edge Cases: stage-declaring exit errors when scout qualified_stage is unset' do
          scout.update!(qualified_stage: nil)
          opportunity = Opportunity.create!(
            account: account,
            contact: sandbox_conversation.contact,
            active_conversation: sandbox_conversation,
            origin_conversation: sandbox_conversation,
            title: 'Negócio Sandbox',
            pipeline_stage: lead_stage
          )

          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_ambos')

          steps = [
            gemini_step.call([{ functionCall: { name: 'exit_fechar', args: {} } }]),
            gemini_step.call([{ text: 'Não foi possível mover o estágio pois o estágio não está configurado.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          tool_calls = response.parsed_body['tool_calls']
          expect(tool_calls.size).to eq(1)
          expect(tool_calls[0]['tool_name']).to eq('exit_fechar')
          expected_error = "A oportunidade não pode mudar de estágio: o estágio 'qualified' não está configurado para este assistente."
          expect(tool_calls[0].dig('result', 'error')).to eq(expected_error)

          expect(opportunity.reload.pipeline_stage_id).to eq(lead_stage.id)
          expect(state.reload.last_exit).to be_nil
        end

        it 'verifies FR-014 and US3-AS3: stage move sees opportunity created earlier in same turn',
           :aggregate_failures do
          steps = [
            gemini_step.call([{ functionCall: { name: 'open_playbook', args: { name: 'fluxo_ambos' } } }]),
            gemini_step.call([{ functionCall: { name: 'manage_opportunity', args: { action: 'create', title: 'Oportunidade Nova' } } }]),
            gemini_step.call([{ functionCall: { name: 'exit_fechar', args: {} } }]),
            gemini_step.call([{ text: 'Oportunidade criada e qualificada com sucesso.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          expect(state.reload.last_exit).to eq('fechar')

          opp = sandbox_conversation.reload_active_opportunity
          expect(opp).to be_present
          expect(opp.title).to eq('Oportunidade Nova')
          expect(opp.pipeline_stage_id).to eq(qualified_stage.id)
        end

        it 'verifies US1-AS1, FR-001, and US3-AS1: system text order with pinned procedure and removed tools absent',
           :aggregate_failures do
          state = ScoutConversationState.for_conversation(sandbox_conversation)
          state.record_state_activation!('fluxo_ambos')

          steps = [
            gemini_step.call([{ text: 'Continuando com fluxo ambos.' }])
          ]
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(*steps)

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(provider_requests.size).to eq(1)

          system_text = provider_requests[0].dig('contents', 0, 'parts', 0, 'text')
          index_pos = system_text.index('[Playbook Index]')
          escalation_pos = system_text.index('[Escalation]')
          body_pos = system_text.index('Passos com ambos.')

          expect(index_pos).to be < escalation_pos
          expect(escalation_pos).to be < body_pos

          tool_names = provider_requests[0].dig('tools', 0, 'functionDeclarations')&.map { |f| f['name'] } || []
          expect(tool_names).not_to include('move_opportunity_stage', 'handover_to_human', 'call_custom_api')
        end
      end

      context 'with Scout V2 plain-text final reply and unreadable handling (US4)' do
        it 'verifies US4-AS3 and FR-020: reply is plain text verbatim and no request sets response schema' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(gemini_step.call([{ text: 'Texto final do modelo sem schema.' }]))

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq('Texto final do modelo sem schema.')

          generation_config = provider_requests[0]['generationConfig'] || {}
          expect(generation_config['responseMimeType']).not_to eq('application/json')
          expect(generation_config['responseSchema']).to be_nil
        end

        it 'verifies unreadable/whitespace reply with no escalation returns simulation error' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(gemini_step.call([{ text: '   ' }]))

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq('Erro ao executar simulação: Resposta final do modelo vazia ou ilegível.')
          expect(response.parsed_body['error']).to eq('Resposta final do modelo vazia ou ilegível.')
        end

        it 'verifies unreadable reply after exit_handoff returns standard handoff message and keeps last_exit' do
          stub_request(:post, %r{generativelanguage\.googleapis\.com/.*:generateContent})
            .with { |req| provider_requests << JSON.parse(req.body) }
            .to_return(
              gemini_step.call([{ functionCall: { name: 'exit_handoff', args: { reason: 'Preciso de ajuda humana' } } }]),
              gemini_step.call([{ text: '' }])
            )

          post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/playground_messages",
               params: valid_params,
               headers: agent.create_new_auth_token

          expect(response).to have_http_status(:ok)
          expect(response.parsed_body['reply']).to eq(I18n.t('conversations.scout.handoff'))
          state = ScoutConversationState.find_by(conversation_id: sandbox_conversation.id)
          expect(state&.last_exit).to eq('handoff')
        end
      end
    end
  end
end
