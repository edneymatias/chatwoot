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

    it 'generates and creates dated notes on contact (T010)' do
      notes = nil
      expect do
        notes = service.generate_and_update_notes
      end.to change { contact.notes.count }.by(2)

      expect(notes.size).to eq(2)
      # Both returned notes should start with [DD/MM/YYYY]
      expect(notes[0]).to match(%r{^\[\d{2}/\d{2}/\d{4}\] Lead precisa de 10 licenças})
      expect(notes[1]).to match(%r{^\[\d{2}/\d{2}/\d{4}\] Decisão em 15 dias})

      # Verify persisted content matches the returned dated array exactly
      persisted_content = contact.notes.pluck(:content)
      expect(persisted_content).to eq(notes)
    end

    it 'gracefully rescues and returns empty array on LLM error (T011, unchanged)' do
      allow(fake_chat).to receive(:ask).and_raise(StandardError.new('API timeout'))

      expect do
        notes = service.generate_and_update_notes
        expect(notes).to eq([])
      end.not_to change(contact.notes, :count)
    end

    it 'does not persist blank or empty generated summary (T012, unchanged)' do
      allow(fake_chat).to receive(:ask).and_return(
        instance_double(RubyLLM::Message, content: '{"notes": ["Valid note", "", "Another valid note"]}')
      )

      expect do
        notes = service.generate_and_update_notes
        # Only 2 non-blank notes should be returned and persisted
        expect(notes.size).to eq(2)
        expect(notes[0]).to match(%r{^\[\d{2}/\d{2}/\d{4}\] Valid note})
        expect(notes[1]).to match(%r{^\[\d{2}/\d{2}/\d{4}\] Another valid note})
      end.to change { contact.notes.count }.by(2)
    end

    it 'does not retroactively backfill dates to pre-existing notes (T012a)' do
      # Create a pre-existing note without a date (simulating a note from before this change)
      old_note_content = 'Legacy note from previous version'
      contact.notes.create!(content: old_note_content)

      allow(fake_chat).to receive(:ask).and_return(fake_response)

      expect do
        notes = service.generate_and_update_notes
        expect(notes.size).to eq(2)
      end.to change { contact.notes.count }.by(2)

      # Verify old note is unchanged (still has no date prefix)
      old_note = contact.notes.find { |n| n.content == old_note_content }
      expect(old_note).to be_present
      expect(old_note.content).to eq(old_note_content)
      expect(old_note.content).not_to match(%r{^\[\d{2}/\d{2}/\d{4}\]})

      # Verify new notes have dates
      new_notes = contact.notes.where.not(id: old_note.id)
      expect(new_notes.size).to eq(2)
      new_notes.each do |note|
        expect(note.content).to match(%r{^\[\d{2}/\d{2}/\d{4}\]})
      end
    end

    it 'uses account reporting_timezone when inbox timezone is not set (T029)' do
      # Unset the inbox timezone to fall through to account default
      inbox.update(timezone: nil)
      # Set account reporting_timezone to a non-default timezone (e.g., Asia/Tokyo is UTC+9)
      account.update(reporting_timezone: 'Asia/Tokyo')

      allow(fake_chat).to receive(:ask).and_return(fake_response)

      # Mock Time.current to a specific UTC time that results in a different date in Asia/Tokyo
      # 2026-09-23 03:00:00 UTC = 2026-09-23 12:00:00 JST (Japan Standard Time, UTC+9)
      fixed_time = Time.utc(2026, 9, 23, 3, 0, 0)
      allow(Time).to receive(:current).and_return(fixed_time)

      notes = service.generate_and_update_notes

      # Verify the date prefix uses the account timezone (Asia/Tokyo = UTC+9)
      # 2026-09-23 03:00:00 UTC in JST is 2026-09-23 12:00:00, so date should be 23/09/2026
      expect(notes[0]).to start_with('[23/09/2026]')
      expect(notes[1]).to start_with('[23/09/2026]')

      # Verify persisted notes have the same dated content
      persisted_content = contact.notes.pluck(:content)
      expect(persisted_content).to eq(notes)
    end
  end
end
