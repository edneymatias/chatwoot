# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Playbook::DependencyRules do
  let(:file_ref) { 'custom/playbooks/test.md' }
  let(:violations) { [] }
  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new([]) }

  def build_playbook(exits:)
    Custom::ScoutV2::Playbook.new(
      name: 'test_playbook',
      title: 'Test',
      priority: 10,
      trigger: 'Trigger',
      when_state: [],
      requires: [],
      exits: exits,
      body: 'exit_agendado exit_seguir',
      file_path: file_ref
    )
  end

  describe 'exit precondition validation' do
    it 'accepts known precondition on terminal exit' do
      exit_decl = Custom::ScoutV2::Playbook::ExitDeclaration.new(
        name: 'agendado',
        kind: 'terminal',
        fields: {},
        target: nil,
        stage: nil,
        precondition: 'booking'
      )
      playbook = build_playbook(exits: { 'agendado' => exit_decl })

      described_class.call(playbook: playbook, catalog: catalog, file_ref: file_ref, violations: violations)
      expect(violations).to be_empty
    end

    it 'rejects unknown precondition name' do
      exit_decl = Custom::ScoutV2::Playbook::ExitDeclaration.new(
        name: 'agendado',
        kind: 'terminal',
        fields: {},
        target: nil,
        stage: nil,
        precondition: 'unknown_precondition'
      )
      playbook = build_playbook(exits: { 'agendado' => exit_decl })

      described_class.call(playbook: playbook, catalog: catalog, file_ref: file_ref, violations: violations)
      expect(violations).to include("#{file_ref}: Unknown exit precondition for 'agendado': unknown_precondition")
    end

    it 'rejects precondition on non-terminal exit' do
      exit_decl = Custom::ScoutV2::Playbook::ExitDeclaration.new(
        name: 'seguir',
        kind: 'transition',
        fields: {},
        target: 'outro',
        stage: nil,
        precondition: 'booking'
      )
      playbook = build_playbook(exits: { 'seguir' => exit_decl })

      described_class.call(playbook: playbook, catalog: catalog, file_ref: file_ref, violations: violations)
      expect(violations).to include("#{file_ref}: Exit 'seguir' declares a precondition but is not terminal")
    end
  end
end
