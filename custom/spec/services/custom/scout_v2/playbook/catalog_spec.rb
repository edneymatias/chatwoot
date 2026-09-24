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
end
# rubocop:enable Rails/DynamicFindBy
