# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Capabilities::Registry do
  let(:account) { create(:account) }
  let(:all_settings) do
    {
      'token' => 'secret-token-123',
      'id_empresa' => '1041',
      'id_usuario' => '201313',
      'id_convenio' => '1',
      'nr_convenio' => 'ABC-999',
      'id_origem_pessoa' => '11',
      'id_agenda' => '1',
      'id_servico' => '1'
    }
  end

  before do
    account.enable_features!('erp_integration')
    stub_request(:get, %r{https://wfh.ichatr.com.br/webhook/api/v1/empresas/pessoas/pesquisar})
      .to_return(
        status: 200,
        body: { sucesso: true, mensagem: 'OK', dados: [] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  describe '.resolve' do
    context 'when hook is enabled and all settings are valid digits' do
      before do
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: all_settings)
      end

      it 'resolves scheduling capability with provider' do
        resolution = described_class.resolve('scheduling', account: account)
        expect(resolution.satisfied?).to be(true)
        expect(resolution.capability).to eq('scheduling')
        expect(resolution.provider).to be_a(Erp::Younus::Adapter)
      end

      it 'resolves customer_registry capability with provider' do
        resolution = described_class.resolve('customer_registry', account: account)
        expect(resolution.satisfied?).to be(true)
        expect(resolution.capability).to eq('customer_registry')
        expect(resolution.provider).to be_a(Erp::Younus::Adapter)
      end
    end

    context 'when hook does not exist or is disabled or feature is off' do
      it 'returns unsatisfied resolution when no hook exists without raising' do
        resolution = described_class.resolve('scheduling', account: account)
        expect(resolution.satisfied?).to be(false)
        expect(resolution.provider).to be_nil
      end

      it 'returns unsatisfied resolution when hook is disabled' do
        create(:integrations_hook, account: account, app_id: 'younus', status: :disabled, settings: all_settings)
        resolution = described_class.resolve('scheduling', account: account)
        expect(resolution.satisfied?).to be(false)
        expect(resolution.provider).to be_nil
      end

      it 'returns unsatisfied resolution when erp_integration feature flag is disabled' do
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: all_settings)
        account.disable_features!('erp_integration')
        resolution = described_class.resolve('scheduling', account: account)
        expect(resolution.satisfied?).to be(false)
        expect(resolution.provider).to be_nil
      end

      it 'returns unsatisfied resolution for an unsupported vendor' do
        create(:integrations_hook, account: account, app_id: 'slack', status: :enabled, settings: all_settings)
        resolution = described_class.resolve('scheduling', account: account)
        expect(resolution.satisfied?).to be(false)
      end
    end

    context 'when settings are incomplete or non-numeric' do
      it 'evaluates capabilities independently (missing id_agenda keeps customer_registry satisfied)' do
        incomplete = all_settings.except('id_agenda')
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: incomplete)

        expect(described_class.resolve('scheduling', account: account).satisfied?).to be(false)
        expect(described_class.resolve('customer_registry', account: account).satisfied?).to be(true)
      end

      it 'evaluates capabilities independently (missing nr_convenio keeps scheduling satisfied)' do
        incomplete = all_settings.except('nr_convenio')
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: incomplete)

        expect(described_class.resolve('scheduling', account: account).satisfied?).to be(true)
        expect(described_class.resolve('customer_registry', account: account).satisfied?).to be(false)
      end

      it 'treats blank string setting as unsatisfied' do
        blank_setting = all_settings.merge('id_servico' => '   ')
        create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: blank_setting)

        expect(described_class.resolve('scheduling', account: account).satisfied?).to be(false)
      end

      it 'treats non-numeric id_* value (like id_empresa or id_agenda) as unsatisfied without raising' do
        hook = build(:integrations_hook, account: account, app_id: 'younus', status: :enabled)
        hook.settings = all_settings.merge('id_agenda' => 'not-a-number')
        hook.save(validate: false)

        expect(described_class.resolve('scheduling', account: account).satisfied?).to be(false)
        expect(described_class.resolve('customer_registry', account: account).satisfied?).to be(true)

        hook.settings = all_settings.merge('id_empresa' => 'abc')
        hook.save(validate: false)
        expect(described_class.resolve('scheduling', account: account).satisfied?).to be(false)
        expect(described_class.resolve('customer_registry', account: account).satisfied?).to be(false)
      end
    end

    context 'when checking key requirements against contracts/erp_provider.md §1' do
      it 'matches Adapter.capability_settings exact key requirements' do
        expect(Erp::Younus::Adapter.capability_settings).to eq({
                                                                 'scheduling' => %w[token id_empresa id_agenda id_servico id_usuario id_convenio],
                                                                 'customer_registry' => %w[token id_empresa id_usuario id_convenio nr_convenio
                                                                                           id_origem_pessoa]
                                                               })
      end
    end
  end

  describe '.satisfied_names' do
    it 'returns empty array when account has no integration' do
      expect(described_class.satisfied_names(account: account)).to eq([])
    end

    it 'returns both capability names when all settings are present' do
      create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: all_settings)
      expect(described_class.satisfied_names(account: account)).to eq(%w[scheduling customer_registry])
    end

    it 'returns only customer_registry when id_agenda is missing' do
      create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: all_settings.except('id_agenda'))
      expect(described_class.satisfied_names(account: account)).to eq(%w[customer_registry])
    end

    it 'queries hooks at most once across all capability names' do
      create(:integrations_hook, account: account, app_id: 'younus', status: :enabled, settings: all_settings)
      hooks_queries = []
      subscriber = lambda do |_name, _started, _finished, _id, payload|
        hooks_queries << payload[:sql] if payload[:sql].include?('integrations_hooks') && !payload[:cached]
      end

      ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
        described_class.satisfied_names(account: account)
      end

      expect(hooks_queries.size).to eq(1)
    end
  end
end
