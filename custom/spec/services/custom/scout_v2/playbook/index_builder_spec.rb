# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Playbook::IndexBuilder do
  let(:playbook1) do
    Custom::ScoutV2::Playbook.new(
      name: 'qualificacao',
      trigger: 'Quando o cliente demonstra interesse de compra ou deseja informações comerciais.'
    )
  end
  let(:playbook2) do
    Custom::ScoutV2::Playbook.new(
      name: 'duvida_comercial',
      trigger: 'Quando o cliente pergunta sobre preços, planos ou formas de pagamento.'
    )
  end

  describe '.call' do
    context 'when catalog contains playbooks' do
      let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([playbook1, playbook2]) }

      it 'outputs [Playbook Index] header followed by one line per playbook' do
        result = described_class.call(catalog)

        expect(result).to start_with("[Playbook Index]\n")
        expect(result).to include("- qualificacao: #{playbook1.trigger}")
        expect(result).to include("- duvida_comercial: #{playbook2.trigger}")

        lines = result.strip.split("\n")
        expect(lines.size).to eq(3)
        expect(lines[0]).to eq('[Playbook Index]')
        expect(lines[1]).to eq("- qualificacao: #{playbook1.trigger}")
        expect(lines[2]).to eq("- duvida_comercial: #{playbook2.trigger}")
      end

      it 'normalizes triggers ending in newlines so entries remain exactly one line per playbook' do
        pb1 = Custom::ScoutV2::Playbook.new(
          name: 'qualificacao',
          trigger: "Quando o cliente demonstra interesse.\n"
        )
        pb2 = Custom::ScoutV2::Playbook.new(
          name: 'duvida_comercial',
          trigger: "Quando o cliente pergunta sobre preços.\n"
        )
        cat = Custom::ScoutV2::Playbook::Catalog.new([pb1, pb2])

        result = described_class.call(cat)
        lines = result.strip.split("\n")

        expect(lines.size).to eq(3)
        expect(lines[0]).to eq('[Playbook Index]')
        expect(lines[1]).to eq('- qualificacao: Quando o cliente demonstra interesse.')
        expect(lines[2]).to eq('- duvida_comercial: Quando o cliente pergunta sobre preços.')
      end
    end

    context 'when catalog is empty' do
      let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([]) }

      it 'outputs header and a single non-list line stating no playbook is available to open this turn' do
        result = described_class.call(catalog)

        lines = result.strip.split("\n")
        expect(lines.size).to eq(2)
        expect(lines[0]).to eq('[Playbook Index]')
        expect(lines[1]).not_to start_with('-')
        expect(lines[1]).to eq('Nenhum playbook disponível para abrir neste turno.')
      end
    end
  end
end
