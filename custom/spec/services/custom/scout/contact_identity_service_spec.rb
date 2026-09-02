# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ContactIdentityService do
  let(:account) { create(:account) }

  describe '.placeholder_name?' do
    context 'with positive placeholder names' do
      it 'identifies standard 2-digit and 3-digit Haikunator placeholder patterns' do
        expect(described_class.placeholder_name?(Contact.new(name: 'empty-meadow-50'))).to be(true)
        expect(described_class.placeholder_name?(Contact.new(name: 'polished-forest-561'))).to be(true)
      end

      it 'identifies 1-digit boundary cases' do
        expect(described_class.placeholder_name?(Contact.new(name: 'summer-river-0'))).to be(true)
        expect(described_class.placeholder_name?(Contact.new(name: 'autumn-leaf-9'))).to be(true)
      end

      it 'identifies 3-digit boundary cases' do
        expect(described_class.placeholder_name?(Contact.new(name: 'silent-hill-100'))).to be(true)
        expect(described_class.placeholder_name?(Contact.new(name: 'bold-wave-999'))).to be(true)
      end
    end

    context 'with negative real names, handles, or non-matching formats' do
      it 'returns false for real names' do
        expect(described_class.placeholder_name?(Contact.new(name: 'Maria Silva'))).to be(false)
        expect(described_class.placeholder_name?(Contact.new(name: 'Ana'))).to be(false)
      end

      it 'returns false for single-word or non-hyphenated handles with numbers' do
        expect(described_class.placeholder_name?(Contact.new(name: 'joao123'))).to be(false)
        expect(described_class.placeholder_name?(Contact.new(name: 'primeirazinha11234'))).to be(false)
      end

      it 'returns false for names with more or fewer than two hyphen-separated word segments' do
        expect(described_class.placeholder_name?(Contact.new(name: 'one-two-three-50'))).to be(false)
        expect(described_class.placeholder_name?(Contact.new(name: 'single-50'))).to be(false)
      end

      it 'returns false for 4 or more digits' do
        expect(described_class.placeholder_name?(Contact.new(name: 'empty-meadow-5000'))).to be(false)
      end

      it 'returns false for uppercase letters in placeholder format' do
        expect(described_class.placeholder_name?(Contact.new(name: 'Empty-Meadow-50'))).to be(false)
      end

      it 'returns false for nil, blank, or missing contact' do
        expect(described_class.placeholder_name?(Contact.new(name: nil))).to be(false)
        expect(described_class.placeholder_name?(Contact.new(name: ''))).to be(false)
        expect(described_class.placeholder_name?(nil)).to be(false)
      end
    end

    describe 'regression guarantee (FR-008)' do
      it 'does not mutate contact.name during classification' do
        contact = Contact.new(name: 'empty-meadow-50')
        expect { described_class.placeholder_name?(contact) }.not_to change(contact, :name)

        real_contact = Contact.new(name: 'Maria Silva')
        expect { described_class.placeholder_name?(real_contact) }.not_to change(real_contact, :name)
      end
    end
  end
end
