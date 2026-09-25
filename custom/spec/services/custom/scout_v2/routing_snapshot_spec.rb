# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::ScoutV2::RoutingSnapshot do
  describe 'defaults' do
    subject(:snapshot) { described_class.new }

    it 'defaults conversation to nil' do
      expect(snapshot.conversation).to be_nil
    end

    it 'defaults contact to nil' do
      expect(snapshot.contact).to be_nil
    end

    it 'defaults inbox to nil' do
      expect(snapshot.inbox).to be_nil
    end

    it 'defaults scout to nil' do
      expect(snapshot.scout).to be_nil
    end

    it 'defaults opportunity to nil' do
      expect(snapshot.opportunity).to be_nil
    end

    it 'defaults opportunity_stage_role to :none' do
      expect(snapshot.opportunity_stage_role).to eq(:none)
    end

    it 'defaults pending_fields to a frozen empty array' do
      expect(snapshot.pending_fields).to eq([])
      expect(snapshot.pending_fields).to be_frozen
    end

    it 'defaults active_playbook to nil' do
      expect(snapshot.active_playbook).to be_nil
    end

    it 'defaults transitions to 0' do
      expect(snapshot.transitions).to eq(0)
    end

    it 'defaults satisfied_capabilities to a frozen empty array' do
      expect(snapshot.satisfied_capabilities).to eq([])
      expect(snapshot.satisfied_capabilities).to be_frozen
    end
  end

  describe 'explicit values' do
    let(:conv) { Conversation.new }
    let(:cont) { Contact.new }
    let(:inb) { Inbox.new }
    let(:sc) { Scout.new }
    let(:opp) { Opportunity.new }
    let(:pb) { Custom::ScoutV2::Playbook.new(name: 'pb', title: 'PB', priority: 1, trigger: 'lead_optin') }
    let(:snapshot) do
      described_class.new(
        conversation: conv,
        contact: cont,
        inbox: inb,
        scout: sc,
        opportunity: opp,
        opportunity_stage_role: :qualified,
        pending_fields: %w[email phone],
        active_playbook: pb,
        transitions: 2,
        satisfied_capabilities: %w[search]
      )
    end

    it 'reads back core associations exactly as provided' do
      expect(snapshot.conversation).to eq(conv)
      expect(snapshot.contact).to eq(cont)
      expect(snapshot.inbox).to eq(inb)
      expect(snapshot.scout).to eq(sc)
      expect(snapshot.opportunity).to eq(opp)
    end

    it 'reads back routing properties exactly as provided' do
      expect(snapshot.opportunity_stage_role).to eq(:qualified)
      expect(snapshot.pending_fields).to eq(%w[email phone])
      expect(snapshot.active_playbook).to eq(pb)
      expect(snapshot.transitions).to eq(2)
      expect(snapshot.satisfied_capabilities).to eq(%w[search])
    end

    it 'freezes passed arrays' do
      fields = %w[email phone]
      caps = %w[search]
      snapshot = described_class.new(pending_fields: fields, satisfied_capabilities: caps)

      expect(snapshot.pending_fields).to be_frozen
      expect(snapshot.satisfied_capabilities).to be_frozen
    end

    it 'coerces nil arrays to frozen empty arrays' do
      snapshot = described_class.new(pending_fields: nil, satisfied_capabilities: nil)

      expect(snapshot.pending_fields).to eq([])
      expect(snapshot.pending_fields).to be_frozen
      expect(snapshot.satisfied_capabilities).to eq([])
      expect(snapshot.satisfied_capabilities).to be_frozen
    end
  end

  describe 'immutability' do
    subject(:snapshot) { described_class.new(opportunity_stage_role: :initial) }

    it 'is frozen and cannot be modified' do
      expect(snapshot).to be_frozen
    end

    it 'does not expose attribute writer methods' do
      expect { snapshot.transitions = 1 }.to raise_error(NoMethodError)
    end
  end
end
