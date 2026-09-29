# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
RSpec.describe Custom::ScoutV2::Playbook::Validator do
  let(:file_path) { '/path/to/valid_playbook.md' }
  let(:exit_decl) do
    ->(name:, kind: 'terminal', **options) { Custom::ScoutV2::Playbook::ExitDeclaration.new(name: name, kind: kind, **options) }
  end
  let(:default_exit) do
    exit_decl.call(name: 'success', kind: 'terminal', fields: { 'id' => 'integer' })
  end
  let(:attrs) do
    {
      name: 'valid_playbook',
      title: 'Valid Playbook',
      priority: 10,
      trigger: 'Valid trigger text',
      when_state: [['opportunity_open', nil]],
      requires: ['scheduling'],
      exits: { 'success' => default_exit },
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

      it 'accepts tools registered in the ScoutV2 tool registry' do
        attrs[:tools] = ['manage_opportunity']
        expect(described_class.call!(catalog)).to be(catalog)
      end

      it 'accepts open_playbook calls whose target exists, quoted or not' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 1, body: 'Calling open_playbook(pb2)'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 2, body: 'Calling open_playbook("pb1")')
                          ])
        expect(described_class.call!(catalog)).to be(catalog)
      end

      it 'accepts exit_handoff referenced in the body without an exit declaration' do
        attrs[:body] = 'Some body text mentioning exit_success and exit_handoff'
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
        attrs.merge!(exits: { 'sem-horario' => exit_decl.call(name: 'sem-horario') }, body: 'no exit tokens')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'sem-horario'))
      end

      it 'reports an unregistered when_state predicate' do
        attrs[:when_state] = [['unknown_predicate', nil]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Unregistered predicate: unknown_predicate'))
      end

      it 'reports an argument-taking predicate without an argument' do
        attrs[:when_state] = [['opportunity_in_stage', nil]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Predicate opportunity_in_stage requires an argument'))
      end

      it 'reports an argument given to a predicate that takes none' do
        attrs[:when_state] = [%w[contact_has_phone x]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Predicate contact_has_phone takes no argument (got x)'))
      end

      it 'reports an invalid stage role for opportunity_in_stage' do
        attrs[:when_state] = [%w[opportunity_in_stage invalid_role]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Unknown stage role for opportunity_in_stage: invalid_role'))
      end

      it 'reports playbook_not_completed naming a playbook not in the catalog' do
        attrs[:when_state] = [%w[playbook_not_completed ghost_pb]]
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Unknown playbook for playbook_not_completed: ghost_pb'))
      end

      it 'reports playbook_not_completed naming a situational playbook of the catalog' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'proc_pb', when_state: [%w[playbook_not_completed situational_pb]],
                                                                   file_path: 'playbooks/proc.md'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'situational_pb', priority: 2, when_state: [], exits: {}, body: '',
                                                                   file_path: 'playbooks/sit.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including('playbooks/proc.md',
                                                                       'playbook_not_completed must name a procedure playbook: situational_pb'))
      end

      it 'reports an unknown business fact in needs' do
        attrs[:needs] = ['politica_inexistente']
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Unknown business fact: politica_inexistente'))
      end

      it 'reports an empty pending-step marker' do
        attrs[:requires] = ['scheduling']
        attrs[:body] = 'Step 1: [[depends: ]]'
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Empty pending-step marker'))
      end

      it 'reports a pending-step marker referencing an undeclared requirement' do
        attrs[:requires] = ['scheduling']
        attrs[:body] = 'Step 1: [[depends: undeclared_req]]'
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path,
                                                                       'Pending-step marker references undeclared requirement: undeclared_req'))
      end

      it 'reports an unknown required capability' do
        attrs[:requires] = ['unregistered_capability']
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'unregistered_capability'))
      end

      it 'reports a tool missing from the ScoutV2 tool registry' do
        attrs[:tools] = ['unregistered_tool']
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'unregistered_tool'))
      end

      it 'reports an exit token not declared in the playbook exits' do
        attrs.merge!(exits: { 'declared' => exit_decl.call(name: 'declared') }, body: 'Body with exit_undeclared and exit_declared')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'exit_undeclared'))
      end

      it 'reports an exit token declared only in another playbook' do
        pb2_attrs = attrs.merge(
          name: 'pb2', priority: 2,
          exits: { 'shared' => exit_decl.call(name: 'shared') },
          body: '', file_path: '/path/to/pb2.md'
        )
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 1, exits: {}, body: 'exit_shared'),
                            Custom::ScoutV2::Playbook.new(**pb2_attrs)
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
        attrs.merge!(when_state: [], exits: {}, body: '', load_errors: ['when_state must be a list (got "opportunity_oppen")'])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'opportunity_oppen'))
      end

      it 'reports an exit named handoff as reserved' do
        attrs.merge!(exits: { 'handoff' => exit_decl.call(name: 'handoff') }, body: 'Body mentioning exit_handoff')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Reserved exit name: handoff'))
      end

      it 'reports a situational playbook declaring any exit' do
        attrs.merge!(when_state: [], exits: { 'success' => exit_decl.call(name: 'success') }, body: 'Body with exit_success')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, 'Situational playbook cannot declare exits: success'))
      end

      it 'reports an unknown exit kind' do
        attrs[:exits] = { 'success' => exit_decl.call(name: 'success', kind: 'finish') }
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Unknown exit kind for 'success': finish"))
      end

      it 'reports a transition exit without a target' do
        attrs.merge!(exits: { 'next' => exit_decl.call(name: 'next', kind: 'transition', target: nil) }, body: 'Body with exit_next')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Transition exit 'next' requires a target"))
      end

      it 'reports a transition exit targeting an unknown playbook' do
        attrs.merge!(exits: { 'next' => exit_decl.call(name: 'next', kind: 'transition', target: 'missing_pb') }, body: 'Body with exit_next')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Unknown transition target for 'next': missing_pb"))
      end

      it 'reports a transition exit targeting its own playbook' do
        attrs.merge!(exits: { 'next' => exit_decl.call(name: 'next', kind: 'transition', target: 'valid_playbook') }, body: 'Body with exit_next')
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Transition exit 'next' cannot target its own playbook"))
      end

      it 'reports a transition exit targeting a situational playbook' do
        next_exit = exit_decl.call(name: 'next', kind: 'transition', target: 'pb2')
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb1', priority: 1,
                                                                   exits: { 'next' => next_exit },
                                                                   body: 'exit_next', file_path: 'playbooks/pb1.md'),
                            Custom::ScoutV2::Playbook.new(**attrs, name: 'pb2', priority: 2, when_state: [], exits: {},
                                                                   body: '', file_path: 'playbooks/pb2.md')
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(
          a_string_including('playbooks/pb1.md', "Transition exit 'next' cannot target situational playbook pb2")
        )
      end

      it 'reports a target declared on a non-transition exit' do
        attrs[:exits] = { 'success' => exit_decl.call(name: 'success', kind: 'terminal', target: 'other_pb') }
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Exit 'success' declares a target but is not a transition"))
      end

      it 'reports an invalid field name in an exit' do
        attrs[:exits] = { 'success' => exit_decl.call(name: 'success', fields: { 'Bad-Field' => 'string' }) }
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Invalid field name in exit 'success': Bad-Field"))
      end

      it 'reports an unsupported field type in an exit' do
        attrs[:exits] = { 'success' => exit_decl.call(name: 'success', fields: { 'amount' => 'decimal' }) }
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Unsupported field type in exit 'success': amount: decimal"))
      end

      it 'reports an unknown stage role for an exit' do
        attrs[:exits] = { 'success' => exit_decl.call(name: 'success', stage: 'won') }
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to contain_exactly(a_string_including(file_path, "Unknown stage role for 'success': won"))
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

      it 'reports every FR-006 violation in one pass' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(
                              **attrs,
                              name: 'pb1',
                              priority: 1,
                              exits: {
                                'handoff' => exit_decl.call(name: 'handoff'),
                                'bad_kind' => exit_decl.call(name: 'bad_kind', kind: 'stop'),
                                'bad_trans' => exit_decl.call(name: 'bad_trans', kind: 'transition', target: nil),
                                'bad_term' => exit_decl.call(name: 'bad_term', kind: 'terminal', target: 'other'),
                                'bad_field' => exit_decl.call(name: 'bad_field', fields: { 'BadField' => 'string', 'score' => 'float' }),
                                'bad_stage' => exit_decl.call(name: 'bad_stage', stage: 'won')
                              },
                              body: 'exit_handoff exit_undeclared',
                              file_path: 'playbooks/pb1.md'
                            )
                          ])
        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to include(
          a_string_including('Reserved exit name: handoff'),
          a_string_including("Unknown exit kind for 'bad_kind': stop"),
          a_string_including("Transition exit 'bad_trans' requires a target"),
          a_string_including("Exit 'bad_term' declares a target but is not a transition"),
          a_string_including("Invalid field name in exit 'bad_field': BadField"),
          a_string_including("Unsupported field type in exit 'bad_field': score: float"),
          a_string_including("Unknown stage role for 'bad_stage': won"),
          a_string_including('Undeclared exit token: exit_undeclared')
        )
      end

      it 'reports both unknown key and unknown kind violations in one ValidationError and preserves the token reference' do
        tmp_dir = Dir.mktmpdir('scout_v2_validator_exit_spec')
        begin
          File.write(File.join(tmp_dir, 'pb1.md'), <<~MD)
            ---
            name: pb1
            title: Playbook 1
            priority: 1
            trigger: trigger text
            exits:
              custom_exit:
                kind: unknown_kind
                unknown_key: foo
            ---
            Body mentioning exit_custom_exit
          MD

          loaded_catalog = Custom::ScoutV2::Playbook::Loader.load_all(tmp_dir)
          expect { described_class.call!(loaded_catalog) }.to raise_error(
            Custom::ScoutV2::Playbook::Validator::ValidationError
          ) do |err|
            expect(err.violations).to include(
              a_string_including("Invalid exit 'custom_exit': unknown key 'unknown_key'"),
              a_string_including("Unknown exit kind for 'custom_exit': unknown_kind")
            )
            expect(err.violations.none? { |v| v.include?('Undeclared exit token') }).to be true
          end
        ensure
          FileUtils.rm_rf(tmp_dir)
        end
      end

      it 'reports FR-009a and FR-020 condition, requirement, and marker violations in one ValidationError' do
        playbooks.replace([
                            Custom::ScoutV2::Playbook.new(
                              **attrs,
                              name: 'proc_pb',
                              priority: 1,
                              when_state: [
                                ['unknown_pred', nil],
                                ['opportunity_in_stage', nil],
                                %w[contact_has_phone extra],
                                %w[opportunity_in_stage invalid_role],
                                %w[playbook_not_completed ghost_pb],
                                %w[playbook_not_completed sit_pb]
                              ],
                              requires: ['scheduling'],
                              needs: ['unknown_fact'],
                              body: 'exit_success [[depends: ]] and [[depends: missing_req]]',
                              file_path: 'playbooks/proc.md'
                            ),
                            Custom::ScoutV2::Playbook.new(
                              **attrs,
                              name: 'sit_pb',
                              priority: 2,
                              when_state: [],
                              exits: {},
                              body: '',
                              file_path: 'playbooks/sit.md'
                            )
                          ])

        expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
        expect(error.violations).to include(
          a_string_including('playbooks/proc.md: Unregistered predicate: unknown_pred'),
          a_string_including('playbooks/proc.md: Predicate opportunity_in_stage requires an argument'),
          a_string_including('playbooks/proc.md: Predicate contact_has_phone takes no argument (got extra)'),
          a_string_including('playbooks/proc.md: Unknown stage role for opportunity_in_stage: invalid_role'),
          a_string_including('playbooks/proc.md: Unknown playbook for playbook_not_completed: ghost_pb'),
          a_string_including('playbooks/proc.md: playbook_not_completed must name a procedure playbook: sit_pb'),
          a_string_including('playbooks/proc.md: Unknown business fact: unknown_fact'),
          a_string_including('playbooks/proc.md: Empty pending-step marker'),
          a_string_including('playbooks/proc.md: Pending-step marker references undeclared requirement: missing_req')
        )
      end
    end
  end
end
