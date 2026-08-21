# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutInbox, type: :model do
  before do
    ActiveRecord::Encryption.config.primary_key = 'test-primary-key-32-chars-length'
    ActiveRecord::Encryption.config.deterministic_key = 'test-determ-key-32-chars-length!'
    ActiveRecord::Encryption.config.key_derivation_salt = 'test-derivation-salt-32-chars!'
    ActiveRecord::Encryption.context.instance_variable_set(:@key_provider, nil)
  end

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Sales Scout'
    )
  end

  describe 'associations' do
    it 'belongs to scout and inbox' do
      scout_inbox = described_class.new(scout: scout, inbox: inbox)
      expect(scout_inbox.scout).to eq(scout)
      expect(scout_inbox.inbox).to eq(inbox)
    end
  end

  describe 'validations' do
    it 'is valid with valid attributes' do
      expect(described_class.new(scout: scout, inbox: inbox)).to be_valid
    end

    it 'validates presence of scout' do
      scout_inbox = described_class.new(scout: nil, inbox: inbox)
      expect(scout_inbox).not_to be_valid
      expect(scout_inbox.errors[:scout]).to be_present
    end

    it 'validates presence of inbox' do
      scout_inbox = described_class.new(scout: scout, inbox: nil)
      expect(scout_inbox).not_to be_valid
      expect(scout_inbox.errors[:inbox]).to be_present
    end

    it 'rejects attaching a second Scout to the same inbox' do
      described_class.create!(scout: scout, inbox: inbox)

      other_scout = Scout.create!(
        account: account,
        name: 'Support Scout'
      )

      duplicate_link = described_class.new(scout: other_scout, inbox: inbox)
      expect(duplicate_link).not_to be_valid
      expect(duplicate_link.errors[:inbox_id]).to include('has already been taken')
    end
  end
end
