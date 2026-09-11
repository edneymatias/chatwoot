# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::CreatePrivateNote do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:scout) do
    Scout.create!(
      account: account,
      name: 'Test Scout',
      enabled: true
    )
  end
  let(:tool) { described_class.new(scout, conversation) }

  describe '#execute' do
    it 'creates a private activity note in the conversation' do
      expect do
        result = tool.execute(content: 'Test internal note content')
        expect(result).to include('successfully')
      end.to change { conversation.messages.where(private: true).count }.by(1)

      last_message = conversation.messages.last
      expect(last_message.content).to eq('Test internal note content')
      expect(last_message.private).to be(true)
    end
  end
end
