# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Playbook::Validator do
  let(:file_path) { '/path/to/valid_playbook.md' }
  let(:attrs) do
    {
      name: 'valid_playbook',
      title: 'Valid Playbook',
      priority: 10,
      trigger: 'Valid trigger text',
      when_state: [['opportunity_open', nil]],
      requires: ['scheduling'],
      exits: { 'success' => { 'id' => 'integer' } },
      body: 'Some body text mentioning exit_success',
      file_path: file_path
    }
  end
  let(:playbooks) { [Custom::ScoutV2::Playbook.new(**attrs)] }
  let(:catalog) { Custom::ScoutV2::Playbook::Catalog.new(playbooks) }
  let(:error) do
    described_class.call!(catalog)
  rescue StandardError => e
    e
  end

  describe '.call!' do
    context 'when catalog is valid' do
      it 'returns the same catalog' do
        expect(described_class.call!(catalog)).to be(catalog)
      end

      it 'accepts an empty catalog' do
        empty_catalog = Custom::ScoutV2::Playbook::Catalog.new([])
        expect(described_class.call!(empty_catalog)).to be(empty_catalog)
      end

      it 'accepts empty when_state and empty exits' do
        attrs.merge!(when_state: [], exits: {}, body: 'Body with no exit tokens')
        expect(described_class.call!(catalog)).to be(catalog)
      end

      it 'accepts open_playbook calls whose target exists, quoted or not' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 1, body: 'Calling open_playbook(pb2)'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 2, body: 'Calling open_playbook("pb1")')
                          ])
        expect(described_class.call!(catalog)).to be(catalog)
      end
    end

    context 'when a single rule is violated' do
      it 'reports a blank name with the file' do
        attrs[:name] = ''
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*name/i))
      end

      it 'reports a blank title with the file' do
        attrs[:title] = '  '
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*title/i))
      end

      it 'reports a non-string title with the file' do
        attrs[:title] = 123
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*title/i))
      end

      it 'reports a missing trigger with the file' do
        attrs[:trigger] = nil
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*trigger/i))
      end

      it 'reports a non-string trigger with the file' do
        attrs[:trigger] = 123
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*trigger/i))
      end

      it 'reports a missing priority with the file' do
        attrs[:priority] = nil
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_matching(/\A#{Regexp.escape(file_path)}: .*priority.*nil/i))
      end

      it 'reports a non-integer priority with the offending value' do
        attrs[:priority] = 10.5
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, '10.5'))
      end

      it 'reports a name outside the lowercase snake_case format' do
        attrs[:name] = 'Agendamento'
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Agendamento'))
      end

      it 'reports a non-string name' do
        attrs[:name] = 123
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, '123'))
      end

      it 'reports an exit name outside the lowercase snake_case format' do
        attrs.merge!(exits: { 'sem-horario' => {} }, body: 'no exit tokens')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'sem-horario'))
      end

      it 'reports an unregistered when_state predicate' do
        attrs[:when_state] = [['unknown_predicate', nil]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'unknown_predicate'))
      end

      it 'reports an unknown required capability' do
        attrs[:requires] = ['unregistered_capability']
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'unregistered_capability'))
      end

      it 'reports an exit token not declared in the playbook exits' do
        attrs.merge!(exits: { 'declared' => {} }, body: 'Body with exit_undeclared and exit_declared')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'exit_undeclared'))
      end

      it 'reports an exit token declared only in another playbook' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 1, exits: {}, body: 'exit_shared'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 2, exits: { 'shared' => {} }, body: '',
                                                                   file_path: '/path/to/pb2.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'exit_shared'))
      end

      it 'reports exit tokens spelled outside the name format' do
        attrs.merge!(exits: {}, body: 'exit_Agendado or exit_sem-horario')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(
          a_string_including(file_path, 'exit_Agendado'),
          a_string_including(file_path, 'exit_sem-horario')
        )
      end

      it 'reports an open_playbook target missing from the catalog' do
        attrs[:body] = 'Body with open_playbook(missing_target)'
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'missing_target'))
      end

      it 'reports open_playbook targets spelled outside the name format' do
        attrs[:body] = 'open_playbook(Missing_Target) then open_playbook("no-such")'
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(
          a_string_including(file_path, 'Missing_Target'),
          a_string_including(file_path, 'no-such')
        )
      end

      it 'reports load errors recorded by the loader' do
        attrs.merge!(when_state: [], load_errors: ['when_state must be a list (got "opportunity_oppen")'])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'opportunity_oppen'))
      end
    end

    context 'when a rule spans several playbooks' do
      it 'reports a duplicate priority naming every file and the value' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 10, file_path: 'playbooks/pb1.md'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 10, file_path: 'playbooks/pb2.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including('playbooks/pb1.md', 'playbooks/pb2.md', '10'))
      end

      it 'reports a duplicate name naming every file and the name' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'same_name', priority: 1, file_path: 'playbooks/a.md'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'same_name', priority: 2, file_path: 'playbooks/b.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including('playbooks/a.md', 'playbooks/b.md', 'same_name'))
      end

      it 'reports every violation across files in one error' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', requires: ['bad_cap'], file_path: 'playbooks/pb1.md'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 20, when_state: [['bad_pred', nil]], exits: {},
                                                                   body: 'exit_undeclared and open_playbook(no_such_pb)',
                                                                   file_path: 'playbooks/pb2.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(
          a_string_including('playbooks/pb1.md', 'bad_cap'),
          a_string_including('playbooks/pb2.md', 'bad_pred'),
          a_string_including('playbooks/pb2.md', 'exit_undeclared'),
          a_string_including('playbooks/pb2.md', 'no_such_pb')
        )
      end
    end
  end
end
