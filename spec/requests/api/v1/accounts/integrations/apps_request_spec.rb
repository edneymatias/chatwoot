require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Integrations::Apps' do
  let(:account) { create(:account) }

  before do
    stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas\?idEmpresa=42&nrTelcelpessoa=0})
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'GET /api/v1/accounts/{account.id}/integrations/apps' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/integrations/apps"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns the category attribute for ERP apps' do
        account.enable_features!('erp_integration')
        account.hooks << create(:integrations_hook, app_id: 'younus', account: account, status: :enabled,
                                                    settings: { 'token' => 'valid-token', 'id_empresa' => '42' })

        get "/api/v1/accounts/#{account.id}/integrations/apps",
            headers: agent.create_new_auth_token

        expect(response).to have_http_status(:success)
        erp_app = response.parsed_body['payload'].find { |app| app['id'] == 'younus' }
        expect(erp_app).not_to be_nil
        expect(erp_app['category']).to eql('erp')
      end
    end
  end
end
