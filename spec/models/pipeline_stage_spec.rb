require 'rails_helper'

RSpec.describe PipelineStage, type: :model do
  describe 'validations' do
    it { is_expected.to validate_presence_of(:account_id) }
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:opportunities).dependent(:restrict_with_error) }
  end

  describe 'position assignment' do
    let(:account) { create(:account) }

    it 'auto-assigns position based on max position' do
      stage1 = account.pipeline_stages.create!(name: 'Stage 1')
      expect(stage1.position).to eq(1)

      stage2 = account.pipeline_stages.create!(name: 'Stage 2')
      expect(stage2.position).to eq(2)
    end
  end

  describe 'destroy restrictions' do
    let(:account) { create(:account) }
    let(:stage) { account.pipeline_stages.create!(name: 'Stage 1') }
    let(:contact) { create(:contact, account: account) }

    it 'cannot be destroyed if it has opportunities' do
      Opportunity.create!(account: account, contact: contact, pipeline_stage: stage, title: 'Opp 1')
      expect(stage.destroy).to be_falsey
    end
  end
end
