require 'rails_helper'

RSpec.describe Meta::AttachCampaignThumbnailJob, type: :job do
  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:stage) { PipelineStage.create!(account: account, name: 'Lead', position: 1) }
  let!(:opportunity) do
    Opportunity.create!(
      account: account,
      contact: contact,
      pipeline_stage: stage,
      status: :open,
      title: 'Thumbnail Test Opportunity',
      campaign_thumbnail_url: 'https://example.com/thumb.jpg'
    )
  end

  describe '#perform' do
    let(:image_content) { File.read(Rails.root.join('spec/assets/avatar.png')) }

    before do
      stub_request(:get, 'https://example.com/thumb.jpg')
        .to_return(status: 200, body: image_content, headers: { 'Content-Type' => 'image/png' })
    end

    it 'attaches the image to opportunity.campaign_thumbnail' do
      described_class.perform_now(opportunity.id, 'https://example.com/thumb.jpg')
      opportunity.reload

      expect(opportunity.campaign_thumbnail).to be_attached
    end

    it 'handles download failure gracefully' do
      stub_request(:get, 'https://example.com/broken.jpg').to_return(status: 404)

      expect do
        described_class.perform_now(opportunity.id, 'https://example.com/broken.jpg')
      end.not_to raise_error

      opportunity.reload
      expect(opportunity.campaign_thumbnail).not_to be_attached
    end
  end
end
