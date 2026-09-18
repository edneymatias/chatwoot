# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Integrations::Hook do
  let(:account) { create(:account) }

  before do
    account.enable_features!('erp_integration')
  end

  describe 'whitespace sanitization (U24, U25)' do
    it 'strips leading and trailing whitespace from settings string values before validation' do
      adapter = instance_double(Erp::Younus::Adapter, test_connection: true)
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: {
          'token' => "  secret-token-123\n",
          'id_empresa' => ' 42 '
        }
      )

      hook.valid?
      expect(hook.settings['token']).to eq('secret-token-123')
      expect(hook.settings['id_empresa']).to eq('42')
    end

    it 'preserves special characters (hyphens, underscores, dots) in credentials (U25)' do
      adapter = instance_double(Erp::Younus::Adapter, test_connection: true)
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: {
          'token' => ' token_with-special.chars_123 ',
          'id_empresa' => ' 42-A_b.1 '
        }
      )

      hook.valid?
      expect(hook.settings['token']).to eq('token_with-special.chars_123')
      expect(hook.settings['id_empresa']).to eq('42-A_b.1')
    end
  end

  describe 'synchronous connection validation (U26, U27, U28, U29)' do
    let(:valid_settings) { { 'token' => 'valid-token', 'id_empresa' => '42' } }

    it 'calls adapter.test_connection on save for enabled ERP hook (U26)' do
      adapter = instance_double(Erp::Younus::Adapter)
      allow(adapter).to receive(:test_connection).and_return(true)
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(true)
      expect(adapter).to have_received(:test_connection)
    end

    it 'halts save and adds localized invalid_credentials error when adapter raises Erp::AuthenticationError (U27)' do
      adapter = instance_double(Erp::Younus::Adapter)
      allow(adapter).to receive(:test_connection).and_raise(Erp::AuthenticationError, 'Invalid credentials')
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(false)
      expect(hook.errors[:base]).to include(I18n.t('errors.erp.invalid_credentials'))
    end

    it 'halts save and adds localized connection_error when adapter raises Erp::ApiError (U28)' do
      adapter = instance_double(Erp::Younus::Adapter)
      allow(adapter).to receive(:test_connection).and_raise(Erp::ApiError, 'Server down')
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(false)
      expect(hook.errors[:base]).to include(I18n.t('errors.erp.connection_error'))
    end

    it 'skips validation when hook is disabled (U29)' do
      allow(Erp::AdapterFactory).to receive(:build)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings,
        status: :disabled
      )

      expect(hook.save).to be(true)
      expect(Erp::AdapterFactory).not_to have_received(:build)
    end

    it 'skips validation on update when settings and status are untouched (U29)' do
      adapter = instance_double(Erp::Younus::Adapter, test_connection: true)
      allow(Erp::AdapterFactory).to receive(:build).and_return(adapter)

      hook = Integrations::Hook.create!(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )
      hook.update!(account_id: account.id)
      # Called once during create!, not called again during update!
      expect(Erp::AdapterFactory).to have_received(:build).once
    end
  end

  describe '#masked_settings (U30)' do
    it 'returns token masked with dots while keeping id_empresa in cleartext' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: { 'token' => 'super-secret', 'id_empresa' => '42' }
      )

      expect(hook.masked_settings).to eq({
                                           'token' => '••••••••',
                                           'id_empresa' => '42'
                                         })
    end
  end

  describe 'non-ERP hooks (U31)' do
    it 'does not apply ERP validation or sanitization to slack or dyte hooks' do
      allow(Erp::AdapterFactory).to receive(:build)

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'slack',
        settings: { 'reference' => ' some-value ' }
      )

      expect(hook.erp_integration?).to be(false)
      expect(Erp::AdapterFactory).not_to have_received(:build)
    end
  end

  describe 'validation localization (U41)' do
    it 'verifies errors.erp keys exist in en and pt_BR' do
      expect(I18n.exists?('errors.erp.invalid_credentials', :en)).to be(true)
      expect(I18n.exists?('errors.erp.connection_error', :en)).to be(true)

      expect(I18n.exists?('errors.erp.invalid_credentials', :pt_BR)).to be(true)
      expect(I18n.exists?('errors.erp.connection_error', :pt_BR)).to be(true)
    end
  end
end
