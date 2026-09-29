# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Exits::PayloadValidator do
  let(:declaration) do
    Custom::ScoutV2::Playbook::ExitDeclaration.new(
      name: 'teste',
      kind: 'terminal',
      fields: {
        'nome' => 'string',
        'idade' => 'integer',
        'saldo' => 'number',
        'ativo' => 'boolean',
        'agendado_para' => 'datetime'
      }
    )
  end

  describe '.call' do
    it 'returns an empty list when all fields match their declared types' do
      payload = {
        'nome' => 'Maria Silva',
        'idade' => 30,
        'saldo' => 150.50,
        'ativo' => true,
        'agendado_para' => '2026-10-01T10:00:00Z'
      }

      expect(described_class.call(declaration, payload)).to be_empty
    end

    it 'accepts integer values for number fields and boolean false' do
      payload = {
        'nome' => 'João',
        'idade' => 25,
        'saldo' => 100,
        'ativo' => false,
        'agendado_para' => '2026-10-01T10:00:00-03:00'
      }

      expect(described_class.call(declaration, payload)).to be_empty
    end

    it 'accepts symbol keys in payload and normalizes them' do
      payload = {
        nome: 'João',
        idade: 25,
        saldo: 100,
        ativo: false,
        agendado_para: '2026-10-01T10:00:00Z'
      }

      expect(described_class.call(declaration, payload)).to be_empty
    end

    it 'reports missing fields' do
      payload = { 'nome' => 'Maria' }

      problems = described_class.call(declaration, payload)
      expect(problems).to include(
        "campo 'idade' ausente",
        "campo 'saldo' ausente",
        "campo 'ativo' ausente",
        "campo 'agendado_para' ausente"
      )
    end

    it 'reports undeclared fields' do
      payload = {
        'nome' => 'Maria',
        'idade' => 30,
        'saldo' => 100,
        'ativo' => true,
        'agendado_para' => '2026-10-01T10:00:00Z',
        'extra_field' => 'valor'
      }

      problems = described_class.call(declaration, payload)
      expect(problems).to contain_exactly("campo 'extra_field' não declarado")
    end

    it 'rejects nil values for any declared field' do
      payload = {
        'nome' => nil,
        'idade' => nil,
        'saldo' => nil,
        'ativo' => nil,
        'agendado_para' => nil
      }

      problems = described_class.call(declaration, payload)
      expect(problems).to contain_exactly(
        "campo 'nome' deve ser string",
        "campo 'idade' deve ser integer",
        "campo 'saldo' deve ser number",
        "campo 'ativo' deve ser boolean",
        "campo 'agendado_para' deve ser datetime"
      )
    end

    it 'rejects blank strings for string and datetime fields' do
      payload = {
        'nome' => '   ',
        'idade' => 30,
        'saldo' => 100,
        'ativo' => true,
        'agendado_para' => ''
      }

      problems = described_class.call(declaration, payload)
      expect(problems).to contain_exactly(
        "campo 'nome' deve ser string",
        "campo 'agendado_para' deve ser datetime"
      )
    end

    it 'rejects invalid datetime strings that do not parse with Time.iso8601' do
      payload = {
        'nome' => 'Maria',
        'idade' => 30,
        'saldo' => 100,
        'ativo' => true,
        'agendado_para' => '2026-10-01'
      }

      problems = described_class.call(declaration, payload)
      expect(problems).to contain_exactly("campo 'agendado_para' deve ser datetime")
    end

    it 'reports every problem at once when payload has multiple violations' do
      payload = {
        'nome' => 123,
        'saldo' => 'não é número',
        'extra' => 'sobrando'
      }

      problems = described_class.call(declaration, payload)
      expect(problems).to contain_exactly(
        "campo 'idade' ausente",
        "campo 'ativo' ausente",
        "campo 'agendado_para' ausente",
        "campo 'extra' não declarado",
        "campo 'nome' deve ser string",
        "campo 'saldo' deve ser number"
      )
    end
  end
end
