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

  describe '#reorder_to!' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }

    before do
      PipelineStage.seed_defaults_for!(account)
      account.pipeline_stages.create!(name: 'Stage 3')
      account.pipeline_stages.create!(name: 'Stage 4')
      # other account stages to verify cross-account safety
      PipelineStage.seed_defaults_for!(other_account)
    end

    it 'renumbers siblings and maintains gapless unique positions' do
      stages = account.pipeline_stages.order(:position).to_a
      # Current order: Leads Recebidos (1), Em Contato (2), Stage 3 (3), Stage 4 (4)
      stage_to_move = stages.last # Stage 4, currently position 4

      stage_to_move.reorder_to!(2)

      # Should now be: Leads Recebidos (1), Stage 4 (2), Em Contato (3), Stage 3 (4)
      updated_stages = account.pipeline_stages.order(:position).to_a

      expect(updated_stages.pluck(:position)).to eq([1, 2, 3, 4])
      expect(updated_stages[1]).to eq(stage_to_move)
      expect(updated_stages[2].name).to eq('Em Contato')
    end

    it 'is a no-op when position is unchanged' do
      stage = account.pipeline_stages.find_by(position: 2)

      expect { stage.reorder_to!(2) }.not_to(change { account.pipeline_stages.order(:position).pluck(:id, :position) })
    end

    it 'never changes another account\'s stage positions' do
      stage = account.pipeline_stages.find_by(position: 4)

      expect { stage.reorder_to!(1) }.not_to(change { other_account.pipeline_stages.order(:position).pluck(:id, :position) })
    end
  end
end
