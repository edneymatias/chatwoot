# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Integrations::App do
  describe 'feature flag definition' do
    it 'defines erp_integration in config/features.yml' do
      features = YAML.safe_load(File.read(Rails.root.join('config/features.yml'))).map(&:with_indifferent_access)
      flag = features.find { |f| f[:name] == 'erp_integration' }

      expect(flag).to be_present
      expect(flag[:display_name]).to eq('ERP Integration')
      expect(flag[:enabled]).to be(false)
      expect(flag[:column]).to eq('feature_flags_ext_1')
    end
  end

  describe 'younus app definition' do
    it 'loads younus app definition from config/integration/apps.yml' do
      app = described_class.find(id: 'younus')

      expect(app).to be_present
      expect(app.params[:category]).to eq('erp')
      expect(app.params[:feature_flag]).to eq('erp_integration')
      expect(app.visible_properties).to eq(%w[id_empresa token])
      expect(app.params[:allow_multiple_hooks]).to be(false)
      expect(app.params[:hook_type]).to eq('account')
    end
  end

  describe '#active?' do
    let(:account) { create(:account) }
    let(:younus_app) { described_class.find(id: 'younus') }
    let(:slack_app) { described_class.find(id: 'slack') }

    context 'when app has category erp' do
      it 'returns false when erp_integration feature flag is disabled on account (U21)' do
        account.disable_features!('erp_integration')

        expect(younus_app.active?(account)).to be(false)
      end

      it 'returns true when erp_integration feature flag is enabled on account (U22)' do
        account.enable_features!('erp_integration')

        expect(younus_app.active?(account)).to be(true)
      end
    end

    context 'when app is non-erp' do
      it 'preserves original active? behavior by delegating to super (U23)' do
        allow(GlobalConfigService).to receive(:load).with('SLACK_CLIENT_ID', nil).and_return('some-id')
        allow(GlobalConfigService).to receive(:load).with('SLACK_CLIENT_SECRET', nil).and_return('some-secret')

        expect(slack_app.active?(account)).to be(true)
      end
    end
  end

  describe 'app catalog localization (U42)' do
    it 'defines younus integration copy in en and pt_BR locales' do
      expect(I18n.exists?('integration_apps.younus.name', :en)).to be(true)
      expect(I18n.exists?('integration_apps.younus.description', :en)).to be(true)
      expect(I18n.exists?('integration_apps.younus.short_description', :en)).to be(true)

      expect(I18n.exists?('integration_apps.younus.name', :pt_BR)).to be(true)
      expect(I18n.exists?('integration_apps.younus.description', :pt_BR)).to be(true)
      expect(I18n.exists?('integration_apps.younus.short_description', :pt_BR)).to be(true)
    end
  end
end
