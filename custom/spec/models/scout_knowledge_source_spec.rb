# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ScoutKnowledgeSource, type: :model do
  let(:account) { create(:account) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Knowledge Scout',
      provider: :gemini,
      model_name: 'gemini-2.5-flash',
      responses_quota: 10,
      responses_consumed: 0,
      enabled: true
    )
  end

  describe 'validations' do
    it 'validates URL presence and format for url kind' do
      source = described_class.new(scout: scout, account: account, kind: :url, url: 'invalid-url')
      expect(source).not_to be_valid
      expect(source.errors[:url]).to be_present

      source.url = 'https://example.com/pricing'
      expect(source).to be_valid
    end

    it 'validates FAQ question and answer for faq kind' do
      faq = described_class.new(scout: scout, account: account, kind: :faq)
      expect(faq).not_to be_valid
      expect(faq.errors[:question]).to be_present
      expect(faq.errors[:answer]).to be_present

      faq.question = 'What is the pricing?'
      faq.answer = 'It is $99/mo'
      expect(faq).to be_valid
    end
  end
end
