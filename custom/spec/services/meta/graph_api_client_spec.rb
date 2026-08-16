require 'rails_helper'

RSpec.describe Meta::GraphApiClient do
  let(:access_token) { 'test_token_123' }
  let(:client) { described_class.new(access_token) }
  let(:ad_id) { '12020584938290123' }

  describe '#fetch_ad_details' do
    context 'when Meta returns a valid ad response' do
      let(:response_body) do
        {
          'id' => ad_id,
          'name' => 'Ad 1',
          'adset' => { 'id' => '111', 'name' => 'Adset 1' },
          'campaign' => { 'id' => '222', 'name' => 'Campaign 1' },
          'creative' => { 'thumbnail_url' => 'https://fbcdn.net/thumb.jpg' }
        }
      end

      before do
        stub_request(:get, %r{https://graph\.facebook\.com/v22\.0/#{ad_id}})
          .to_return(status: 200, body: response_body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'returns parsed response' do
        result = client.fetch_ad_details(ad_id)
        expect(result[:name]).to eq('Ad 1')
        expect(result.dig(:campaign, :name)).to eq('Campaign 1')
      end
    end

    context 'when Meta returns token revoked / expired (code 190)' do
      let(:error_body) do
        {
          'error' => {
            'message' => 'Error validating access token: Session has expired.',
            'type' => 'OAuthException',
            'code' => 190,
            'error_subcode' => 463
          }
        }
      end

      before do
        stub_request(:get, %r{https://graph\.facebook\.com/v22\.0/#{ad_id}})
          .to_return(status: 400, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises Meta::AuthenticationError' do
        expect { client.fetch_ad_details(ad_id) }.to raise_error(Meta::AuthenticationError) do |error|
          expect(error.code).to eq(190)
          expect(error.error_subcode).to eq(463)
        end
      end
    end

    context 'when Meta returns rate limit error (code 17)' do
      let(:error_body) do
        {
          'error' => {
            'message' => 'User request limit reached',
            'type' => 'OAuthException',
            'code' => 17
          }
        }
      end

      before do
        stub_request(:get, %r{https://graph\.facebook\.com/v22\.0/#{ad_id}})
          .to_return(status: 400, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises Meta::RateLimitError' do
        expect { client.fetch_ad_details(ad_id) }.to raise_error(Meta::RateLimitError) do |error|
          expect(error.code).to eq(17)
        end
      end
    end

    context 'when Meta returns node not found or unsupported get on Post (code 100)' do
      let(:error_body) do
        {
          'error' => {
            'message' => '(#100) Tried accessing nonexisting field (adset) on node type (Post)',
            'type' => 'OAuthException',
            'code' => 100
          }
        }
      end

      before do
        stub_request(:get, %r{https://graph\.facebook\.com/v22\.0/#{ad_id}})
          .to_return(status: 400, body: error_body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises Meta::NodeNotFoundError' do
        expect { client.fetch_ad_details(ad_id) }.to raise_error(Meta::NodeNotFoundError) do |error|
          expect(error.code).to eq(100)
        end
      end
    end
  end
end
