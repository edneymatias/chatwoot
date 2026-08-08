require 'rails_helper'

RSpec.describe PipelineStageRequiredField, type: :model do
  let(:account) { create(:account) }
  let(:pipeline_stage) { PipelineStage.create!(account: account, name: 'Stage 1') }
  let(:custom_attribute_definition) do
    create(:custom_attribute_definition,
           account: account,
           attribute_model: 'opportunity_attribute',
           attribute_key: 'company',
           attribute_display_type: 'text')
  end

  describe 'associations' do
    it { is_expected.to belong_to(:pipeline_stage) }
    it { is_expected.to belong_to(:custom_attribute_definition) }
  end

  describe 'validations' do
    subject do
      described_class.create!(account: account, pipeline_stage: pipeline_stage, custom_attribute_definition: custom_attribute_definition)
    end

    it do
      expect(subject).to validate_uniqueness_of(:custom_attribute_definition_id)
        .scoped_to(:account_id)
        .with_message(I18n.t('errors.pipeline_stage_required_field.already_required'))
    end
  end
end
