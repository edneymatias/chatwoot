# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# rubocop:disable Rails/DynamicFindBy
RSpec.describe Custom::ScoutV2::Playbook::Loader do
  let(:tmp_dir) { Dir.mktmpdir('scout_v2_playbook_loader_spec') }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  describe '.load_all' do
    context 'with complete frontmatter' do
      let(:file_content) do
        <<~MD
          ---
          name: agendamento
          title: Agendamento de avaliação
          priority: 50
          when_state:
            - opportunity_in_stage: qualificado
            - contact_has_phone
          trigger: >
            O lead confirmou interesse e quer marcar horário.
          requires: [scheduling, customer_registry]
          needs: [politica_reagendamento]
          tools: [update_contact]
          exits:
            agendado: { opportunity_id: integer, starts_at: datetime }
            sem_horario: { motivo: string }
          ---

          ## Passos

          1. Confirme o horário com `scheduling.book`.
          2. Encerre com `exit_agendado`.
        MD
      end

      before do
        File.write(File.join(tmp_dir, 'agendamento.md'), file_content)
      end

      it 'parses frontmatter metadata fields' do
        catalog = described_class.load_all(tmp_dir)
        playbook = catalog.find_by_name('agendamento')

        expect(playbook).not_to be_nil
        expect(playbook.name).to eq('agendamento')
        expect(playbook.title).to eq('Agendamento de avaliação')
        expect(playbook.priority).to eq(50)
        expect(playbook.trigger.strip).to eq('O lead confirmou interesse e quer marcar horário.')
        expect(playbook.file_path).to eq(File.join(tmp_dir, 'agendamento.md'))
      end

      it 'normalizes collections and preserves verbatim body' do
        catalog = described_class.load_all(tmp_dir)
        playbook = catalog.find_by_name('agendamento')

        expect(playbook.when_state).to eq([%w[opportunity_in_stage qualificado], ['contact_has_phone', nil]])
        expect(playbook.requires).to eq(%w[scheduling customer_registry])
        expect(playbook.needs).to eq(%w[politica_reagendamento])
        expect(playbook.tools).to eq(%w[update_contact])
        expected_exits = {
          'agendado' => { 'opportunity_id' => 'integer', 'starts_at' => 'datetime' },
          'sem_horario' => { 'motivo' => 'string' }
        }
        expect(playbook.exits).to eq(expected_exits)
        expect(playbook.body).to eq("\n## Passos\n\n1. Confirme o horário com `scheduling.book`.\n2. Encerre com `exit_agendado`.\n")
      end
    end

    context 'with minimal frontmatter' do
      let(:minimal_content) do
        <<~MD
          ---
          name: minimal
          title: Minimal Playbook
          priority: 10
          trigger: Simple trigger
          ---
          Body text
        MD
      end

      before do
        File.write(File.join(tmp_dir, 'minimal.md'), minimal_content)
      end

      it 'applies collection defaults for omitted fields' do
        catalog = described_class.load_all(tmp_dir)
        playbook = catalog.find_by_name('minimal')

        expect(playbook.when_state).to eq([])
        expect(playbook.requires).to eq([])
        expect(playbook.needs).to eq([])
        expect(playbook.tools).to eq([])
        expect(playbook.exits).to eq({})
        expect(playbook.body).to eq("Body text\n")
      end
    end

    context 'with permissive behavior on missing required fields' do
      let(:incomplete_content) do
        <<~MD
          ---
          title: No name or priority
          ---
          Body here
        MD
      end

      before do
        File.write(File.join(tmp_dir, 'incomplete.md'), incomplete_content)
      end

      it 'does not raise and sets missing fields to nil' do
        expect do
          catalog = described_class.load_all(tmp_dir)
          expect(catalog.playbooks.size).to eq(1)
          playbook = catalog.playbooks.first
          expect(playbook.name).to be_nil
          expect(playbook.priority).to be_nil
          expect(playbook.trigger).to be_nil
          expect(playbook.title).to eq('No name or priority')
        end.not_to raise_error
      end
    end

    context 'with an empty or missing directory' do
      it 'returns empty catalog when directory is empty' do
        catalog = described_class.load_all(tmp_dir)
        expect(catalog.playbooks).to eq([])
      end

      it 'raises when the directory does not exist' do
        expect { described_class.load_all(File.join(tmp_dir, 'non_existent')) }
          .to(raise_error { |error| expect(error.class.name).to eq('Errno::ENOENT') })
      end

      it 'ignores non-markdown files like .keep or .txt' do
        File.write(File.join(tmp_dir, '.keep'), '')
        File.write(File.join(tmp_dir, 'notes.txt'), 'hello')
        catalog = described_class.load_all(tmp_dir)
        expect(catalog.playbooks).to eq([])
      end
    end

    context 'with frontmatter it cannot use' do
      let(:header) { "name: broken\ntitle: Broken\npriority: 1\ntrigger: t\n" }

      it 'records a scalar when_state instead of dropping it' do
        File.write(File.join(tmp_dir, 'a.md'), "---\n#{header}when_state: opportunity_oppen\n---\n")
        playbook = described_class.load_all(tmp_dir).playbooks.first

        expect(playbook.when_state).to eq([])
        expect(playbook.load_errors).to contain_exactly(a_string_including('opportunity_oppen'))
      end

      it 'records a multi-key when_state entry and keeps the valid entries' do
        File.write(File.join(tmp_dir, 'a.md'), <<~MD)
          ---
          #{header.chomp}
          when_state:
            - pending_required_fields
            - { opportunity_open: x, bogus_pred: y }
          ---
        MD
        playbook = described_class.load_all(tmp_dir).playbooks.first

        expect(playbook.when_state).to eq([['pending_required_fields', nil]])
        expect(playbook.load_errors).to contain_exactly(a_string_including('bogus_pred'))
      end

      it 'records a non-mapping exits' do
        File.write(File.join(tmp_dir, 'a.md'), "---\n#{header}exits: [handoff]\n---\n")
        playbook = described_class.load_all(tmp_dir).playbooks.first

        expect(playbook.exits).to eq({})
        expect(playbook.load_errors).to contain_exactly(a_string_including('handoff'))
      end

      it 'records unparseable YAML and still loads the other files' do
        File.write(File.join(tmp_dir, 'a.md'), "---\n#{header}created: 2024-01-01\n---\n")
        File.write(File.join(tmp_dir, 'b.md'), "---\nname: ok\n---\n")
        catalog = described_class.load_all(tmp_dir)

        expect(catalog.playbooks.map(&:file_path)).to eq([File.join(tmp_dir, 'a.md'), File.join(tmp_dir, 'b.md')])
        expect(catalog.playbooks.first.load_errors).to contain_exactly(a_string_including('Date'))
        expect(catalog.playbooks.last.load_errors).to eq([])
      end
    end
  end
end
# rubocop:enable Rails/DynamicFindBy
