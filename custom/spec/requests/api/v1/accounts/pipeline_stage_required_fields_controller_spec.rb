require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::PipelineStageRequiredFields', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:pipeline_stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:custom_attribute) do
    create(:custom_attribute_definition,
           account: account,
           attribute_model: 'opportunity_attribute',
           attribute_key: 'company',
           attribute_display_type: 'text')
  end

  before do
    allow(account).to receive(:feature_enabled?).and_call_original
    allow(account).to receive(:feature_enabled?).with('kanban_board').and_return(true)
  end

  describe 'POST /api/v1/accounts/{account.id}/pipeline_stages/{pipeline_stage.id}/pipeline_stage_required_fields' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post api_v1_account_pipeline_stage_required_fields_url(account_id: account.id, pipeline_stage_id: pipeline_stage.id),
             params: { pipeline_stage_required_field: { custom_attribute_definition_id: custom_attribute.id } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized for agent' do
        post api_v1_account_pipeline_stage_required_fields_url(account_id: account.id, pipeline_stage_id: pipeline_stage.id),
             headers: agent.create_new_auth_token,
             params: { pipeline_stage_required_field: { custom_attribute_definition_id: custom_attribute.id } },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new required field for administrator' do
        expect do
          post api_v1_account_pipeline_stage_required_fields_url(account_id: account.id, pipeline_stage_id: pipeline_stage.id),
               headers: user.create_new_auth_token,
               params: { pipeline_stage_required_field: { custom_attribute_definition_id: custom_attribute.id } },
               as: :json
        end.to change(PipelineStageRequiredField, :count).by(1)

        expect(response).to have_http_status(:success)
        expect(JSON.parse(response.body)['custom_attribute_definition_id']).to eq(custom_attribute.id)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/pipeline_stages/{pipeline_stage.id}/pipeline_stage_required_fields/{custom_attribute.id}' do
    let!(:required_field) do
      PipelineStageRequiredField.create!(account: account, pipeline_stage: pipeline_stage, custom_attribute_definition: custom_attribute)
    end

    context 'when it is an authenticated user' do
      it 'deletes the required field' do
        expect do
          delete api_v1_account_pipeline_stage_required_field_url(account_id: account.id, pipeline_stage_id: pipeline_stage.id, id: custom_attribute.id),
                 headers: user.create_new_auth_token,
                 as: :json
        end.to change(PipelineStageRequiredField, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end
  end
end
