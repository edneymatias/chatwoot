# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Integrations::Hook do
  let(:account) { create(:account) }

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})
      .to_return(status: 200, body: { sucesso: true, dados: [] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'whitespace sanitization (U24, U25)' do
    it 'strips leading and trailing whitespace from settings string values before validation' do
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
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(true)
      expect(
        a_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas\?idEmpresa=42&nrTelcelpessoa=0})
          .with(headers: { 'token' => 'valid-token' })
      ).to have_been_made
    end

    it 'halts save and adds localized invalid_credentials error when adapter raises Erp::AuthenticationError (U27)' do
      stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})
        .to_return(status: 401, body: { sucesso: false, mensagem: 'Invalid credentials' }.to_json, headers: { 'Content-Type' => 'application/json' })

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(false)
      expect(hook.errors[:base]).to include(I18n.t('errors.erp.invalid_credentials'))
    end

    it 'halts save and adds localized connection_error when adapter raises Erp::ApiError (U28)' do
      stub_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})
        .to_return(status: 500, body: 'Server down')

      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )

      expect(hook.save).to be(false)
      expect(hook.errors[:base]).to include(I18n.t('errors.erp.connection_error'))
    end

    it 'skips validation when hook is disabled (U29)' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: valid_settings,
        status: :disabled
      )

      expect(hook.save).to be(true)
      expect(a_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})).not_to have_been_made
    end

    it 'skips validation on update when settings and status are untouched (U29)' do
      hook = Integrations::Hook.create!(
        account: account,
        app_id: 'younus',
        settings: valid_settings
      )
      expect(a_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})).to have_been_made.once

      hook.update!(account_id: account.id)
      # Called once during create!, not called again during update!
      expect(a_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})).to have_been_made.once
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
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'slack',
        settings: { 'reference' => ' some-value ' }
      )

      expect(hook.erp_integration?).to be(false)
      expect(a_request(:get, %r{https://wfh\.ichatr\.com\.br/webhook/pessoas})).not_to have_been_made
    end
  end

  describe 'settings schema validation (FR-010, US2-AS10)' do
    it 'accepts a hook with only token and id_empresa' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: { 'token' => 'tok', 'id_empresa' => '1041' }
      )
      expect(hook).to be_valid
    end

    it 'accepts all six new optional settings' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: {
          'token' => 'tok',
          'id_empresa' => '1041',
          'id_usuario' => '201313',
          'id_convenio' => '1',
          'nr_convenio' => 'ABC-123',
          'id_origem_pessoa' => '11',
          'id_agenda' => '1',
          'id_servico' => '1'
        }
      )
      expect(hook).to be_valid
    end

    it 'accepts cleared empty string for the numeric id keys' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: {
          'token' => 'tok',
          'id_empresa' => '1041',
          'id_usuario' => '',
          'id_convenio' => '',
          'id_origem_pessoa' => '',
          'id_agenda' => '',
          'id_servico' => ''
        }
      )
      expect(hook).to be_valid
    end

    it 'rejects non-numeric values for the numeric id keys' do
      %w[id_usuario id_convenio id_origem_pessoa id_agenda id_servico].each do |key|
        hook = Integrations::Hook.new(
          account: account,
          app_id: 'younus',
          settings: {
            'token' => 'tok',
            'id_empresa' => '1041',
            key => 'not-numeric'
          }
        )
        expect(hook).not_to be_valid
        expect(hook.errors[:settings]).to be_present
      end
    end

    it 'rejects unknown settings keys' do
      hook = Integrations::Hook.new(
        account: account,
        app_id: 'younus',
        settings: {
          'token' => 'tok',
          'id_empresa' => '1041',
          'unknown_field' => 'bad'
        }
      )
      expect(hook).not_to be_valid
      expect(hook.errors[:settings]).to be_present
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
