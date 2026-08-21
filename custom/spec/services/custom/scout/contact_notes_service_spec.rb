# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::ContactNotesService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Memory Scout',
      enabled: true,
      feature_memory: true
    )
  end
  let(:service) { described_class.new(scout, conversation) }

  describe '#generate_and_update_notes' do
    let(:fake_chat) { instance_double(RubyLLM::Chat) }
    let(:fake_response) { instance_double(RubyLLM::Message, content: '{"notes": ["Lead precisa de 10 licenças", "Decisão em 15 dias"]}') }

    before do
      allow(scout).to receive(:llm_chat).and_return(fake_chat)
      allow(fake_chat).to receive(:with_params).and_return(fake_chat)
      allow(fake_chat).to receive(:with_instructions).and_return(fake_chat)
      allow(fake_chat).to receive(:ask).and_return(fake_response)
    end

    it 'generates and creates notes on contact' do
      expect do
        notes = service.generate_and_update_notes
        expect(notes).to eq(['Lead precisa de 10 licenças', 'Decisão em 15 dias'])
      end.to change { contact.notes.count }.by(2)

      expect(contact.notes.pluck(:content)).to include('Lead precisa de 10 licenças', 'Decisão em 15 dias')
    end

    it 'gracefully rescues and returns empty array on LLM error' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError.new('API timeout'))

      expect do
        notes = service.generate_and_update_notes
        expect(notes).to eq([])
      end.not_to change(contact.notes, :count)
    end
  end
end
