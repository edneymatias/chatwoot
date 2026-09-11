# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::Tools::UpdateContact do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Old Name', email: 'old@example.com') }
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
    it 'updates contact attributes and merges custom attributes' do
      result = tool.execute(
        name: 'New Name',
        email: 'new@example.com',
        phone: '+5511999999999',
        custom_attributes: { 'budget' => '10000', 'decision_maker' => true }
      )

      expect(result).to include('successfully')
      contact.reload
      expect(contact.name).to eq('New Name')
      expect(contact.email).to eq('new@example.com')
      expect(contact.phone_number).to eq('+5511999999999')
      expect(contact.custom_attributes['budget']).to eq('10000')
      expect(contact.custom_attributes['decision_maker']).to be(true)
    end

    it 'includes a scoped confirmation reminder naming only the fields sent in this call' do
      result = tool.execute(name: 'New Name', custom_attributes: { 'budget' => '10000' })
      expect(result).to include('Dados registrados nesta chamada: Nome, Budget')
      expect(result).to include('não repita dados já confirmados em mensagens anteriores desta conversa')
    end

    it 'omits the confirmation reminder when no field was actually sent in this call' do
      result = tool.execute
      expect(result).not_to include('Dados registrados nesta chamada')
    end

    it 'parses a JSON-encoded String custom_attributes into a Hash instead of dropping it (observed OpenAI function-calling behavior)' do
      result = tool.execute(custom_attributes: '{"budget":"10000","decision_maker":true}')

      expect(result).to include('successfully')
      contact.reload
      expect(contact.custom_attributes['budget']).to eq('10000')
      expect(contact.custom_attributes['decision_maker']).to be(true)
    end

    it 'ignores a String custom_attributes value that is not valid JSON instead of raising' do
      result = tool.execute(custom_attributes: '{not valid json')

      expect(result).to include('successfully')
      contact.reload
      expect(contact.custom_attributes).to eq({})
    end

    describe 'phone normalization (follows Maria do Carmo/#61 crash: raw local numbers failed Contact validation and crashed save!)' do
      context 'when phone already starts with +' do
        it 'strips extra formatting but keeps the country code as given' do
          result = tool.execute(phone: '+55 41 99988-7766')

          expect(result).to include('successfully')
          expect(contact.reload.phone_number).to eq('+5541999887766')
        end
      end

      context 'when phone has only digits with an area code already (10-11 digits)' do
        it 'prepends the scout default_country_code' do
          result = tool.execute(phone: '(41) 99988-7766')

          expect(result).to include('successfully')
          expect(contact.reload.phone_number).to eq('+5541999887766')
        end

        it 'also handles an 8-digit landline with area code (10 digits total)' do
          result = tool.execute(phone: '41 3513-5000')

          expect(result).to include('successfully')
          expect(contact.reload.phone_number).to eq('+554135135000')
        end
      end

      context 'when phone has only digits with no area code (8-9 digits) and the scout has a default_area_code configured' do
        before { scout.update!(default_country_code: '+55', default_area_code: '41') }

        it 'prepends country code + default area code for a 9-digit mobile number' do
          result = tool.execute(phone: '999220122')

          expect(result).to include('successfully')
          expect(contact.reload.phone_number).to eq('+5541999220122')
        end

        it 'prepends country code + default area code for an 8-digit landline number' do
          result = tool.execute(phone: '35135000')

          expect(result).to include('successfully')
          expect(contact.reload.phone_number).to eq('+554135135000')
        end
      end

      context 'when phone has no area code (8-9 digits) and the scout has no default_area_code configured' do
        before { scout.update!(default_area_code: nil) }

        it 'skips the phone field, still saves the rest, and asks the model for the area code instead of crashing' do
          result = tool.execute(name: 'Maria do Carmo', phone: '999220122')

          expect(result).to include('successfully')
          expect(result).to include('DDD')
          contact.reload
          expect(contact.name).to eq('Maria do Carmo')
          expect(contact.phone_number).to be_blank
        end
      end

      context 'when the digit count is not a plausible phone number length' do
        it 'skips the phone field, still saves the rest, and asks the model to confirm the number' do
          result = tool.execute(name: 'Maria do Carmo', phone: '123')

          expect(result).to include('successfully')
          expect(result).to include('DDD')
          contact.reload
          expect(contact.name).to eq('Maria do Carmo')
          expect(contact.phone_number).to be_blank
        end
      end

      context 'when phone is the only field sent and normalization fails' do
        it 'still returns the base success message (matching existing no-op behavior) plus the phone note' do
          result = tool.execute(phone: '123')

          expect(result).to include('successfully')
          expect(result).to include('DDD')
          expect(contact.reload.phone_number).to be_blank
        end
      end

      context 'when the normalized phone already belongs to a different contact in the account (follows conversation #63 crash)' do
        before { scout.update!(default_country_code: '+55', default_area_code: '41') }

        let!(:other_contact) { create(:contact, account: account, name: 'Maria das Dores', phone_number: '+554199220122') }

        it 'merges this conversation onto the existing contact instead of crashing or refusing to save ' \
           '(reuses core ContactIdentifyAction/ContactMergeAction — the same flow the website widget itself ' \
           'uses when a visitor identifies with an already-known phone/email)' do
          mergee_id = contact.id

          result = tool.execute(name: 'Jana', phone: '99220122')

          expect(result).to include('successfully')
          expect(Contact.exists?(mergee_id)).to be(false)
          other_contact.reload
          expect(other_contact.name).to eq('Jana')
          expect(other_contact.phone_number).to eq('+554199220122')
          expect(conversation.reload.contact_id).to eq(other_contact.id)
        end

        it 'leaves a private note flagging the merge for human review' do
          mergee_id = contact.id

          tool.execute(name: 'Jana', phone: '99220122')

          note = conversation.reload.messages.where(private: true).last
          expect(note.content).to include('Contato mesclado automaticamente')
          expect(note.content).to include("ID #{mergee_id}")
          expect(note.content).to include("ID #{other_contact.id}")
        end
      end

      context 'when the contact re-sends its own already-saved phone number (no conflict with itself)' do
        before do
          scout.update!(default_country_code: '+55', default_area_code: '41')
          contact.update!(phone_number: '+554199220122')
        end

        it 'does not merge or destroy anything and keeps saving normally' do
          contact_id = contact.id

          result = tool.execute(name: 'Jana Renamed', phone: '99220122')

          expect(result).to include('successfully')
          expect(Contact.exists?(contact_id)).to be(true)
          expect(contact.reload.phone_number).to eq('+554199220122')
          expect(contact.name).to eq('Jana Renamed')
          expect(conversation.reload.messages.where(private: true)).to be_empty
        end
      end

      context 'when save! raises a validation error not specifically anticipated by phone handling (defense in depth)' do
        it 'rescues ActiveRecord::RecordInvalid, reports the validation errors, and does not crash the tool call' do
          allow(contact).to receive(:save!) do
            contact.errors.add(:email, 'é inválido')
            raise ActiveRecord::RecordInvalid, contact
          end

          result = tool.execute(name: 'Jana', email: 'not-an-email')

          expect(result).to include('Não foi possível salvar')
          expect(result).to include('Email')
        end
      end
    end
  end
end
