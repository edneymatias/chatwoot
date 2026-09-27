# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Scouts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Qualified Stage') }
  let!(:attr1) { create(:custom_attribute_definition, account: account, attribute_model: 'opportunity_attribute') }
  let!(:attr2) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute') }

  let!(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Qualifier',
      enabled: true
    )
  end

  before do
    ScoutAccountConfig.create!(
      account: account,
      provider: :gemini,
      model_name: 'gemini-2.5-flash',
      api_key: 'test-key'
    )
  end

  describe 'GET /api/v1/accounts/{account.id}/scouts/{scout.id}' do
    it 'returns scout with required_custom_attribute_definitions' do
      scout.required_custom_attribute_definitions << attr1

      get "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
          headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['id']).to eq(scout.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to eq([attr1.id])
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/scouts/{scout.id}' do
    it 'updates scout funnel fields and synchronizes required custom attributes when wrapped' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                qualified_stage_id: stage.id,
                required_custom_attribute_definition_ids: [attr1.id, attr2.id]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['qualified_stage_id']).to eq(stage.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to contain_exactly(attr1.id, attr2.id)
      expect(scout.reload.required_custom_attribute_definitions).to contain_exactly(attr1, attr2)
    end

    it 'updates scout funnel fields and synchronizes required custom attributes when unwrapped' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              qualified_stage_id: stage.id,
              required_custom_attribute_definition_ids: [attr1.id, attr2.id]
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['qualified_stage_id']).to eq(stage.id)
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to contain_exactly(attr1.id, attr2.id)
      expect(scout.reload.required_custom_attribute_definitions).to contain_exactly(attr1, attr2)
    end

    it 'updates default_country_code and default_area_code' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: { scout: { default_country_code: '+55', default_area_code: '41' } },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['default_country_code']).to eq('+55')
      expect(json['default_area_code']).to eq('41')
      scout.reload
      expect(scout.default_country_code).to eq('+55')
      expect(scout.default_area_code).to eq('41')
    end

    it 'updates rescue_stage_id and follow_up_delays_hours' do
      rescue_stage = PipelineStage.create!(account: account, name: 'Rescue Stage')

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                rescue_stage_id: rescue_stage.id,
                follow_up_delays_hours: [3, 6, 18]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['rescue_stage_id']).to eq(rescue_stage.id)
      expect(json['follow_up_delays_hours']).to eq([3, 6, 18])
      scout.reload
      expect(scout.rescue_stage_id).to eq(rescue_stage.id)
      expect(scout.follow_up_delays_hours).to eq([3, 6, 18])
    end

    it 'returns unprocessable_entity when follow_up_delays_hours is invalid' do
      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                follow_up_delays_hours: [10, 2]
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
      json = response.parsed_body
      expect(json['error']).to be_present
    end

    it 'clears required custom attributes when empty array is passed' do
      scout.required_custom_attribute_definitions << attr1

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                required_custom_attribute_definition_ids: []
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['required_custom_attribute_definitions']).to be_empty
      expect(scout.reload.required_custom_attribute_definitions).to be_empty
    end

    it 'updates audience conditions when passed' do
      conditions = [
        {
          'attribute_key' => 'phone_number',
          'filter_operator' => 'equal_to',
          'values' => ['+5511999999999'],
          'query_operator' => 'and'
        }
      ]

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                audience: conditions
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['audience']).to eq(conditions)
      expect(scout.reload.audience).to eq(conditions)
    end

    it 'clears audience when empty array is passed' do
      scout.update!(audience: [{ 'attribute_key' => 'phone_number', 'filter_operator' => 'equal_to', 'values' => ['+5511999999999'] }])

      patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            params: {
              scout: {
                audience: []
              }
            },
            headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['audience']).to eq([])
      expect(scout.reload.audience).to eq([])
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/scouts/{scout.id}/sync_required_attributes' do
    it 'synchronizes required custom attributes via dedicated action' do
      post "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/sync_required_attributes",
           params: {
             custom_attribute_definition_ids: [attr1.id]
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:success)
      json = response.parsed_body
      expect(json['required_custom_attribute_definitions'].map { |a| a['id'] }).to eq([attr1.id])
      expect(scout.reload.required_custom_attribute_definitions).to eq([attr1])
    end
  end

  describe 'User Story 3: Identity and style settings API boundary' do
    let(:auth_headers) { admin.create_new_auth_token }

    describe 'valid create, update, and show of the five fields' do
      it 'creates a scout with the five fields and returns them' do
        post "/api/v1/accounts/#{account.id}/scouts",
             params: {
               scout: {
                 name: 'Novo Scout V2',
                 role: 'SDR de qualificação comercial',
                 scope: "- Não informa preços de tabela\n- Não agenda fora de SP",
                 tone: 'professional',
                 response_length: 'standard',
                 greeting: 'Olá! Sou o assistente da clínica.'
               }
             },
             headers: auth_headers

        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json['name']).to eq('Novo Scout V2')
        expect(json['role']).to eq('SDR de qualificação comercial')
        expect(json['scope']).to eq("- Não informa preços de tabela\n- Não agenda fora de SP")
        expect(json['tone']).to eq('professional')
        expect(json['response_length']).to eq('standard')
        expect(json['greeting']).to eq('Olá! Sou o assistente da clínica.')
      end

      it 'updates a scout with the five fields, trimming role and turning whitespace scope to null' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: {
                scout: {
                  role: "\n  SDR da clínica\n- adultos\n  ",
                  scope: "   \n ",
                  tone: 'professional',
                  response_length: 'thorough',
                  greeting: 'Olá!'
                }
              },
              headers: auth_headers

        expect(response).to have_http_status(:success)
        expected_attrs = {
          'role' => "SDR da clínica\n- adultos",
          'scope' => nil,
          'tone' => 'professional',
          'response_length' => 'thorough',
          'greeting' => 'Olá!'
        }
        expect(response.parsed_body.slice('role', 'scope', 'tone', 'response_length', 'greeting')).to eq(expected_attrs)
        expect(scout.reload.attributes.slice('role', 'scope', 'tone', 'response_length', 'greeting')).to eq(expected_attrs)
      end

      it 'shows the five fields in GET response' do
        scout.update!(
          role: 'SDR da clínica',
          scope: 'Apenas agendamentos',
          tone: 'humorous',
          response_length: 'concise',
          greeting: 'E aí!'
        )

        get "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
            headers: auth_headers

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['role']).to eq('SDR da clínica')
        expect(json['scope']).to eq('Apenas agendamentos')
        expect(json['tone']).to eq('humorous')
        expect(json['response_length']).to eq('concise')
        expect(json['greeting']).to eq('E aí!')
      end
    end

    describe 'PATCH rejection matrix: enum values' do
      let(:original_name) { scout.name }
      let(:tone_error) { 'Tone is not included in the list of supported tones (friendly, neutral, matter_of_fact, professional, humorous)' }
      let(:length_error) { 'Response length is not included in the list of supported response lengths (concise, standard, thorough)' }

      ['bogus', 1, '1', '', nil].each do |invalid_tone|
        it "rejects invalid tone #{invalid_tone.inspect} with 422 and preserves attributes" do
          patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
                params: {
                  scout: {
                    name: 'Nome Modificado Indevidamente',
                    tone: invalid_tone,
                    required_custom_attribute_definition_ids: [attr1.id]
                  }
                },
                headers: auth_headers

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to include(tone_error)
          expect(scout.reload.name).to eq(original_name)
          expect(scout.required_custom_attribute_definitions).to be_empty
        end
      end

      ['long', 1, '1', '', nil].each do |invalid_response_length|
        it "rejects invalid response_length #{invalid_response_length.inspect} with 422 and preserves attributes" do
          patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
                params: {
                  scout: {
                    name: 'Nome Modificado Indevidamente',
                    response_length: invalid_response_length,
                    required_custom_attribute_definition_ids: [attr1.id]
                  }
                },
                headers: auth_headers

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to include(length_error)
          expect(scout.reload.name).to eq(original_name)
          expect(scout.required_custom_attribute_definitions).to be_empty
        end
      end

      it 'returns both error messages when both tone and response_length are invalid' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: {
                scout: {
                  tone: 'invalido',
                  response_length: 'invalido'
                }
              },
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to include(tone_error)
        expect(json['error']).to include(length_error)
      end
    end

    describe 'PATCH rejection with JSON payload (as: :json)' do
      let(:original_name) { scout.name }
      let(:tone_error) { 'Tone is not included in the list of supported tones (friendly, neutral, matter_of_fact, professional, humorous)' }
      let(:length_error) { 'Response length is not included in the list of supported response lengths (concise, standard, thorough)' }

      [
        [:tone, 1],
        [:tone, nil],
        [:response_length, 1],
        [:response_length, nil]
      ].each do |attribute, invalid_val|
        it "rejects wrapped invalid #{attribute} #{invalid_val.inspect} with 422 and leaves scout unchanged" do
          expected_error = attribute == :tone ? tone_error : length_error
          patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
                params: {
                  scout: {
                    :name => 'Nome Modificado Indevidamente',
                    attribute => invalid_val
                  }
                },
                headers: auth_headers,
                as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to include(expected_error)
          expect(scout.reload.name).to eq(original_name)
        end

        it "rejects unwrapped invalid #{attribute} #{invalid_val.inspect} with 422 and leaves scout unchanged" do
          expected_error = attribute == :tone ? tone_error : length_error
          patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
                params: {
                  :name => 'Nome Modificado Indevidamente',
                  attribute => invalid_val
                },
                headers: auth_headers,
                as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to include(expected_error)
          expect(scout.reload.name).to eq(original_name)
        end
      end
    end

    describe 'PATCH rejection matrix: role and scope length boundaries' do
      let(:original_name) { scout.name }

      it 'rejects role with 501 characters after strip with 422 and preserves attributes' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: {
                scout: {
                  name: 'Nome Modificado Indevidamente',
                  role: 'a' * 501,
                  required_custom_attribute_definition_ids: [attr1.id]
                }
              },
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to include('Role is too long (maximum is 500 characters)')
        expect(scout.reload.name).to eq(original_name)
        expect(scout.required_custom_attribute_definitions).to be_empty
      end

      it 'rejects scope with 501 characters after strip with 422 and preserves attributes' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: {
                scout: {
                  name: 'Nome Modificado Indevidamente',
                  scope: 'b' * 501,
                  required_custom_attribute_definition_ids: [attr1.id]
                }
              },
              headers: auth_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to include('Scope is too long (maximum is 500 characters)')
        expect(scout.reload.name).to eq(original_name)
        expect(scout.required_custom_attribute_definitions).to be_empty
      end

      it 'accepts role and scope with 500 characters plus padding, storing trimmed values' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: {
                scout: {
                  role: "  #{'a' * 500}  \n",
                  scope: "\n  #{'b' * 500}  "
                }
              },
              headers: auth_headers

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['role']).to eq('a' * 500)
        expect(json['scope']).to eq('b' * 500)
        expect(scout.reload.role).to eq('a' * 500)
        expect(scout.scope).to eq('b' * 500)
      end
    end

    describe 'POST rejection on invalid enum' do
      it 'rejects POST with tone: 1 with 422 and creates no scout' do
        expect do
          post "/api/v1/accounts/#{account.id}/scouts",
               params: {
                 scout: {
                   name: 'Scout com tom invalido',
                   tone: 1
                 }
               },
               headers: auth_headers
        end.not_to change(Scout, :count)

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('Tone is not included in the list of supported tones (friendly, neutral, matter_of_fact, professional, humorous)')
      end
    end

    describe 'pt_BR localized error messages' do
      let(:pt_br_admin) do
        create(:user, account: account, role: :administrator, ui_settings: { 'locale' => 'pt_BR' })
      end
      let(:pt_br_headers) { pt_br_admin.create_new_auth_token }

      it 'returns exact Portuguese message for invalid tone' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: { scout: { tone: 'invalido' } },
              headers: pt_br_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('Tom não está incluído na lista de tons suportados (friendly, neutral, matter_of_fact, professional, humorous)')
      end

      it 'returns exact Portuguese message for invalid response_length' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: { scout: { response_length: 'long' } },
              headers: pt_br_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('Tamanho da resposta não está incluído na lista de tamanhos de resposta suportados (concise, standard, thorough)')
      end

      it 'returns exact Portuguese message for role exceeding 500 characters' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: { scout: { role: 'a' * 501 } },
              headers: pt_br_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('Papel é muito longo (máximo de 500 caracteres)')
      end

      it 'returns exact Portuguese message for scope exceeding 500 characters' do
        patch "/api/v1/accounts/#{account.id}/scouts/#{scout.id}",
              params: { scout: { scope: 'b' * 501 } },
              headers: pt_br_headers

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('Escopo é muito longo (máximo de 500 caracteres)')
      end
    end
  end
end
