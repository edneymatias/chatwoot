# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Scouts::ScoutInboxes', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Scout',
      enabled: true
    )
  end

  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-salt-32-chars-length-long!'
    ScoutAccountConfig.create!(
      account: account,
      provider: :gemini,
      model_name: 'gemini-2.5-flash',
      api_key: 'test-key'
    )
  end

  describe 'DELETE /api/v1/accounts/{account.id}/scouts/{scout.id}/scout_inboxes/{id}' do
    let!(:scout_inbox) { scout.scout_inboxes.create!(inbox: inbox) }

    it 'detaches inbox by scout_inbox id' do
      delete "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/scout_inboxes/#{scout_inbox.id}",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(ScoutInbox.find_by(id: scout_inbox.id)).to be_nil
    end

    it 'detaches inbox by inbox_id (as passed by frontend UI)' do
      delete "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/scout_inboxes/#{inbox.id}",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(ScoutInbox.find_by(id: scout_inbox.id)).to be_nil
    end

    it 'returns 404 when neither scout_inbox id nor inbox_id matches' do
      delete "/api/v1/accounts/#{account.id}/scouts/#{scout.id}/scout_inboxes/99999",
             headers: admin.create_new_auth_token

      expect(response).to have_http_status(:not_found)
    end
  end
end
