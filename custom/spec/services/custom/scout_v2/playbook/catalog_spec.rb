# frozen_string_literal: true

require 'rails_helper'

# rubocop:disable Rails/DynamicFindBy
RSpec.describe Custom::ScoutV2::Playbook::Catalog do
  describe 'catalog queries' do
    let(:playbook_low) do
      Custom::ScoutV2::Playbook.new(
        name: 'low_priority',
        title: 'Low Priority Playbook',
        priority: 10,
        trigger: 'Low priority trigger',
        file_path: '/path/to/low.md'
      )
    end

    let(:playbook_high) do
      Custom::ScoutV2::Playbook.new(
        name: 'high_priority',
        title: 'High Priority Playbook',
        priority: 50,
        trigger: 'High priority trigger',
        file_path: '/path/to/high.md'
      )
    end

    let(:playbook_nil_priority) do
      Custom::ScoutV2::Playbook.new(
        name: 'nil_priority',
        title: 'Nil Priority Playbook',
        priority: nil,
        trigger: 'Nil priority trigger',
        file_path: '/path/to/nil.md'
      )
    end

    let(:catalog) { described_class.new([playbook_low, playbook_high, playbook_nil_priority]) }

    describe '#find_by_name' do
      it 'returns matching playbook when found by exact name' do
        expect(catalog.find_by_name('high_priority')).to eq(playbook_high)
      end

      it 'returns nil when name is not found' do
        expect(catalog.find_by_name('non_existent')).to be_nil
      end

      it 'is case-sensitive' do
        expect(catalog.find_by_name('High_Priority')).to be_nil
      end

      it 'is accessible via [] alias' do
        expect(catalog['high_priority']).to eq(playbook_high)
      end
    end

    describe '#ordered_by_priority' do
      it 'sorts playbooks in descending order by priority, placing nil priorities last' do
        expect(catalog.ordered_by_priority).to eq([playbook_high, playbook_low, playbook_nil_priority])
      end
    end

    describe 'Enumerable inclusion' do
      it 'allows iteration over playbooks' do
        names = catalog.map(&:name)
        expect(names).to eq(%w[low_priority high_priority nil_priority])
      end
    end
  end

  describe 'empty catalog' do
    let(:empty_catalog) { described_class.new([]) }

    it 'returns empty array for playbooks' do
      expect(empty_catalog.playbooks).to eq([])
    end

    it 'returns nil for find_by_name' do
      expect(empty_catalog.find_by_name('anything')).to be_nil
    end

    it 'returns empty array for ordered_by_priority' do
      expect(empty_catalog.ordered_by_priority).to eq([])
    end
  end

  describe 'shipped catalog (US1: identificacao and qualificacao)' do
    let(:shipped_catalog) { Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks')) }
    let(:identificacao) { shipped_catalog['identificacao'] }
    let(:qualificacao) { shipped_catalog['qualificacao'] }

    it 'loads identificacao with expected frontmatter and exits', :aggregate_failures do
      expect(identificacao).to be_present
      expect(identificacao.title).to eq('Identificação do contato')
      expect(identificacao.priority).to eq(30)
      expect(identificacao.when_state).to eq([
                                               ['contact_identity_incomplete', nil],
                                               %w[playbook_not_completed identificacao]
                                             ])
      expect(identificacao.tools).to eq(['update_contact'])
      expect(identificacao.exits.keys).to eq(['identificado'])

      exit_id = identificacao.exits['identificado']
      expect(exit_id.kind).to eq('transition')
      expect(exit_id.target).to eq('qualificacao')
    end

    it 'loads qualificacao with expected frontmatter, tools, and exits', :aggregate_failures do
      expect(qualificacao).to be_present
      expect(qualificacao.title).to eq('Qualificação comercial do lead')
      expect(qualificacao.priority).to eq(10)
      expect(qualificacao.when_state).to eq([
                                              ['in_qualification', nil],
                                              %w[playbook_not_completed qualificacao]
                                            ])
      expect(qualificacao.tools).to eq(['manage_opportunity'])
      expect(qualificacao.exits.keys).to include('desqualificado')

      exit_desq = qualificacao.exits['desqualificado']
      expect(exit_desq.kind).to eq('terminal')
      expect(exit_desq.stage).to eq('unqualified')
      expect(exit_desq.fields).to eq({ 'motivo' => 'string' })
    end

    it 'orders identificacao above qualificacao by priority' do
      expect(identificacao.priority).to be > qualificacao.priority
    end

    it 'does not declare a private-note tool in either playbook' do
      expect(identificacao.tools).not_to include('private_note')
      expect(qualificacao.tools).not_to include('private_note')
      expect(identificacao.body).not_to include('private_note')
      expect(qualificacao.body).not_to include('private_note')
    end

    it 'has a qualificacao trigger that does not require an open opportunity' do
      expect(qualificacao.trigger).to include('com ou sem oportunidade')
      expect(qualificacao.trigger).not_to include('com uma oportunidade em aberto')
    end

    it 'validates the shipped catalog clean without errors' do
      expect { Custom::ScoutV2::Playbook::Validator.call!(shipped_catalog) }.not_to raise_error
    end

    describe 'shipped catalog (US2: three situational playbooks)' do
      let(:shipped_catalog) { Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks')) }
      let(:fora_de_prospeccao) { shipped_catalog['fora_de_prospeccao'] }
      let(:duvida_comercial) { shipped_catalog['duvida_comercial'] }
      let(:pausa) { shipped_catalog['pausa'] }

      it 'loads the three situational playbooks with no when_state, tools, requires, needs, or exits' do
        [fora_de_prospeccao, duvida_comercial, pausa].each do |pb|
          expect(pb).to be_present
          expect(pb.when_state).to be_empty
          expect(pb.tools).to be_empty
          expect(pb.requires).to be_empty
          expect(pb.needs).to be_empty
          expect(pb.exits).to be_empty
        end
      end

      it 'assigns fora_de_prospeccao the highest priority in the catalog' do
        max_priority = shipped_catalog.map(&:priority).max
        expect(fora_de_prospeccao.priority).to eq(max_priority)
        expect(fora_de_prospeccao.priority).to eq(100)
      end

      it 'does not declare a private-note tool in any situational playbook' do
        [fora_de_prospeccao, duvida_comercial, pausa].each do |pb|
          expect(pb.tools).not_to include('private_note')
          expect(pb.body).not_to include('private_note')
        end
      end

      it 'has duvida_comercial and fora_de_prospeccao triggers that mutually exclude each other' do
        expect(fora_de_prospeccao.trigger).to include('duvida_comercial')
        expect(duvida_comercial.trigger).to include('fora_de_prospeccao')
      end
    end

    describe 'shipped catalog (US3: agendamento and whole catalog)' do
      let(:shipped_catalog) { Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks')) }
      let(:agendamento) { shipped_catalog['agendamento'] }
      let(:qualificacao) { shipped_catalog['qualificacao'] }

      it 'loads agendamento with expected frontmatter, requirements, and exits', :aggregate_failures do
        expect(agendamento).to be_present
        expect(agendamento.title).to eq('Agendamento do lead qualificado')
        expect(agendamento.priority).to eq(20)
        expect(agendamento.when_state).to eq([
                                               %w[opportunity_in_stage qualified],
                                               ['contact_has_phone', nil],
                                               %w[playbook_not_completed agendamento]
                                             ])
        expect(agendamento.tools).to be_empty
        expect(agendamento.requires).to eq(%w[scheduling customer_registry])
        expect(agendamento.needs).to be_empty

        expect(agendamento.exits.keys).to contain_exactly('agendado', 'sem_horario')
        exit_ag = agendamento.exits['agendado']
        expect(exit_ag.kind).to eq('terminal')
        expect(exit_ag.stage).to be_nil
        expect(exit_ag.fields).to eq({})
        expect(exit_ag.precondition).to eq('booking')
        exit_sh = agendamento.exits['sem_horario']
        expect(exit_sh.kind).to eq('terminal')
        expect(exit_sh.stage).to be_nil
        expect(exit_sh.fields).to eq({ 'motivo' => 'string' })
      end

      it 'has agendamento raw body carrying exactly four markers and no literal PENDENTE', :aggregate_failures do
        expect(agendamento).to be_present
        body = agendamento.body
        expect(body).not_to include('PENDENTE')
        expect(body.scan(/\[\[depends:\s*customer_registry\s*\]\]/).count).to eq(1)
        expect(body.scan(/\[\[depends:\s*scheduling\s*\]\]/).count).to eq(3)
        expect(body.scan(/\[\[depends:\s*politica_reagendamento\s*\]\]/).count).to eq(0)
        expect(body.scan(/\[\[depends:.*?\]\]/).count).to eq(4)
        expect(body).to include('customer_registry_find_by_phone')
        expect(body).to include('customer_registry_create')
        expect(body).to include('scheduling_list_slots')
        expect(body).to include('scheduling_book')
        expect(body).to include('exit_agendado')
        expect(body).to include('exit_sem_horario')
        expect(body).to include('exit_handoff')
      end

      it 'asserts agendamento body invariants per contracts/turn_assembly.md §4', :aggregate_failures do
        expect(agendamento).to be_present
        body = agendamento.body

        expect(body).to match(/not_found.*confirme o nome.*customer_registry_create/im)
        expect(body).to match(/duas.*ambíguas.*exit_handoff/im)
        expect(body).to match(/no máximo três horários/i)
        expect(body).to match(/linguagem natural/i)
        expect(body).to match(/slot_id/i)
        expect(body).to match(/scheduling_book.*exit_agendado/im)
        expect(body).to match(/scheduling_list_slots.*três dias seguintes/im)
        expect(body).to match(/exit_sem_horario.*nenhuma disponibilidade/im)
        expect(body).to match(/urgência clínica/i)
        expect(body).to match(/não prometa/i)
        expect(body).to match(/não repita a chamada/i)
        expect(body).to match(/não peça o telefone/i)
        expect(body).to match(/não chame ferramentas customer_registry_\*/i)
        expect(body).not_to match(/reagendamento|cancelamento/i)
      end

      it 'declares qualificado exit on qualificacao transitioning to agendamento with qualified stage' do
        expect(qualificacao.exits.keys).to include('qualificado')
        exit_qual = qualificacao.exits['qualificado']
        expect(exit_qual.kind).to eq('transition')
        expect(exit_qual.target).to eq('agendamento')
        expect(exit_qual.stage).to eq('qualified')
      end

      it 'contains exactly six playbooks in descending priority order' do
        expected_names = %w[fora_de_prospeccao duvida_comercial pausa identificacao agendamento qualificacao]
        expect(shipped_catalog.map(&:name)).to match_array(expected_names)

        ordered_names = shipped_catalog.ordered_by_priority.map(&:name)
        expect(ordered_names).to eq(expected_names)

        expected_priorities = {
          'fora_de_prospeccao' => 100,
          'duvida_comercial' => 60,
          'pausa' => 50,
          'identificacao' => 30,
          'agendamento' => 20,
          'qualificacao' => 10
        }
        expected_priorities.each do |name, prio|
          expect(shipped_catalog[name].priority).to eq(prio)
        end
      end

      it 'does not declare a private-note tool in any shipped playbook' do
        shipped_catalog.each do |pb|
          expect(pb.tools).not_to include('private_note')
          expect(pb.body).not_to include('private_note')
        end
      end
    end
  end
end
# rubocop:enable Rails/DynamicFindBy
