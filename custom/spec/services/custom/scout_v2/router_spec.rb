# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::Router do
  let(:open_opp) { Struct.new(:status).new('open') }
  let(:won_opp) { Struct.new(:status).new('won') }

  let(:pb_low) do
    Custom::ScoutV2::Playbook.new(
      name: 'pausa',
      title: 'Pausa',
      priority: 10,
      trigger: 't',
      when_state: [['opportunity_open', nil]],
      file_path: 'pausa.md'
    )
  end

  let(:pb_high) do
    Custom::ScoutV2::Playbook.new(
      name: 'qualificacao',
      title: 'Qualificação',
      priority: 50,
      trigger: 't',
      when_state: [['opportunity_open', nil]],
      file_path: 'qualificacao.md'
    )
  end

  let(:pb_mid) do
    Custom::ScoutV2::Playbook.new(
      name: 'agendamento',
      title: 'Agendamento',
      priority: 30,
      trigger: 't',
      when_state: [['opportunity_open', nil]],
      file_path: 'agendamento.md'
    )
  end

  let(:pb_trigger_only_highest) do
    Custom::ScoutV2::Playbook.new(
      name: 'trigger_only_high',
      title: 'Trigger Only High',
      priority: 100,
      trigger: 'intent_lead',
      when_state: [],
      file_path: 'trigger_only.md'
    )
  end

  describe '.call' do
    context 'when no playbook is currently active' do
      it 'picks the highest-priority matching playbook with confidence 1.0' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_low, pb_high, pb_mid])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_high)
        expect(decision.confidence).to eq(1.0)
      end

      it 'returns nil playbook and nil confidence when no playbook matches' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_low, pb_high])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: won_opp)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to be_nil
        expect(decision.confidence).to be_nil
      end

      it 'never selects trigger-only playbooks with empty when_state even if highest priority' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_trigger_only_highest, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_low)
        expect(decision.confidence).to eq(1.0)
      end

      it 'returns nil when catalog contains only trigger-only playbooks' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_trigger_only_highest])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to be_nil
        expect(decision.confidence).to be_nil
      end
    end

    context 'when a playbook is currently active (active_playbook is present)' do
      it 'continues with active playbook when active playbook is the highest-priority match' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_high, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: pb_high)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_high)
        expect(decision.confidence).to eq(1.0)
      end

      it 'continues with active playbook when no playbooks match when_state' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_high, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: won_opp, active_playbook: pb_mid)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_mid)
        expect(decision.confidence).to eq(1.0)
      end

      it 'interrupts active playbook when a candidate has strictly higher priority' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_high, pb_mid, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: pb_mid)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_high)
        expect(decision.confidence).to eq(1.0)
      end

      it 'retains active playbook when matching candidate has lower priority' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_mid, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: pb_mid)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_mid)
        expect(decision.confidence).to eq(1.0)
      end

      it 'retains active playbook when matching candidate has equal priority (non-strictly higher)' do
        # In practice priorities are unique, but non-strict winner rule guarantees active stays
        pb_equal = Custom::ScoutV2::Playbook.new(
          name: 'equal_priority',
          title: 'Equal Priority',
          priority: 30,
          trigger: 't',
          when_state: [['opportunity_open', nil]],
          file_path: 'equal.md'
        )
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_equal, pb_mid])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: pb_mid)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_mid)
        expect(decision.confidence).to eq(1.0)
      end

      it 'never allows a trigger-only playbook to interrupt active playbook regardless of priority' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_trigger_only_highest, pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp, active_playbook: pb_low)

        decision = described_class.call(ctx, catalog)

        expect(decision.playbook).to eq(pb_low)
        expect(decision.confidence).to eq(1.0)
      end
    end

    describe 'decision object structure and immutability' do
      it 'returns a Decision responding to #playbook and #confidence' do
        catalog = Custom::ScoutV2::Playbook::Catalog.new([pb_low])
        ctx = Custom::ScoutV2::RoutingSnapshot.new(opportunity: open_opp)

        decision = described_class.call(ctx, catalog)

        expect(decision).to respond_to(:playbook)
        expect(decision).to respond_to(:confidence)
      end
    end

    context 'with shipped catalog (US2: situational playbooks never win by state)' do
      let(:shipped_catalog) { Custom::ScoutV2::Playbook::Loader.load_all(Rails.root.join('custom/playbooks')) }
      let(:situational_names) { %w[fora_de_prospeccao duvida_comercial pausa] }
      let(:test_contacts) do
        [Struct.new(:name, :phone_number).new('lindo-peixe-123', nil), Struct.new(:name, :phone_number).new('Carlos Silva', '+5511999999999')]
      end
      let(:test_opportunities) do
        opportunity_statuses = [nil, 'open', 'lost']
        pending_field_options = [[], ['orcamento']]
        stage_roles = %i[none qualified unqualified initial]

        opportunity_statuses.each_with_object([]) do |status, combos|
          pending_field_options.product(stage_roles).each do |pending, role|
            combos << { opp: status.nil? ? nil : Struct.new(:status).new(status), pending: pending, role: role }
          end
        end
      end
      let(:completed_subsets) do
        playbook_names = %w[identificacao qualificacao agendamento]
        (0..playbook_names.size).flat_map { |n| playbook_names.combination(n).to_a }
      end

      it 'never routes to a situational playbook under any state combination' do
        situational_names.each do |name|
          expect(shipped_catalog[name]).to be_present, "Expected #{name} to be in the shipped catalog"
        end

        state_combinations.each do |ctx|
          decision = described_class.call(ctx, shipped_catalog)
          next if decision.playbook.blank?

          error_msg = "Situational playbook #{decision.playbook.name} won by state for #{ctx.inspect}"
          expect(situational_names).not_to include(decision.playbook.name), error_msg
        end
      end

      def state_combinations
        test_contacts.product([nil, '+5511999999999'], test_opportunities, completed_subsets).map do |contact_base, phone, opp_cfg, completed|
          contact = Struct.new(:name, :phone_number).new(contact_base.name, phone)
          Custom::ScoutV2::RoutingSnapshot.new(
            contact: contact,
            opportunity: opp_cfg&.dig(:opp),
            pending_fields: opp_cfg&.dig(:pending) || [],
            opportunity_stage_role: opp_cfg&.dig(:role) || :none,
            completed_playbooks: completed
          )
        end
      end
    end
  end
end
