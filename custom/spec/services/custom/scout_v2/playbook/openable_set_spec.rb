# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Playbook::OpenableSet do
  let(:pausa) do
    Custom::ScoutV2::Playbook.new(
      name: 'pausa',
      title: 'Pausa solicitada',
      trigger: 'O cliente pede para pausar.',
      priority: 20,
      when_state: []
    )
  end

  let(:duvida_comercial) do
    Custom::ScoutV2::Playbook.new(
      name: 'duvida_comercial',
      title: 'Dúvidas Comerciais',
      trigger: 'O cliente tem dúvidas sobre preços.',
      priority: 5,
      when_state: []
    )
  end

  let(:qualificacao) do
    Custom::ScoutV2::Playbook.new(
      name: 'qualificacao',
      title: 'Qualificação',
      trigger: 'Quando o cliente quer comprar.',
      priority: 10,
      when_state: [['opportunity_open', nil]]
    )
  end

  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([pausa, duvida_comercial, qualificacao]) }

  describe '.call' do
    context 'when nothing is pinned' do
      it 'returns a Catalog whose members equal the full catalog' do
        result = described_class.call(catalog: catalog, pinned: nil)

        expect(result).to be_a(Custom::ScoutV2::Playbook::Catalog)
        expect(result.to_a).to eq(catalog.to_a)
      end
    end

    context 'when a procedure is pinned' do
      it 'returns a Catalog with only situational (when_state.blank?) members in catalog order' do
        result = described_class.call(catalog: catalog, pinned: qualificacao)

        expect(result).to be_a(Custom::ScoutV2::Playbook::Catalog)
        expect(result.to_a).to eq([pausa, duvida_comercial])
      end

      context 'without situational members in catalog' do
        let(:catalog_without_situational) { Custom::ScoutV2::Playbook::Catalog.new([qualificacao]) }

        it 'returns an empty Catalog' do
          result = described_class.call(catalog: catalog_without_situational, pinned: qualificacao)

          expect(result).to be_a(Custom::ScoutV2::Playbook::Catalog)
          expect(result.none?).to be true
        end
      end
    end

    context 'when the catalog is empty' do
      let(:empty_catalog) { Custom::ScoutV2::Playbook::Catalog.new([]) }

      it 'returns an empty Catalog when nothing is pinned' do
        result = described_class.call(catalog: empty_catalog, pinned: nil)

        expect(result).to be_a(Custom::ScoutV2::Playbook::Catalog)
        expect(result.none?).to be true
      end

      it 'returns an empty Catalog when a procedure is pinned' do
        result = described_class.call(catalog: empty_catalog, pinned: qualificacao)

        expect(result).to be_a(Custom::ScoutV2::Playbook::Catalog)
        expect(result.none?).to be true
      end
    end
  end
end
