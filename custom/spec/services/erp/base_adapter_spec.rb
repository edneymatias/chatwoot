# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::BaseAdapter do
  let(:hook) { instance_double(Integrations::Hook, settings: { 'token' => 'abc' }) }
  let(:test_adapter_class) do
    Class.new(described_class) do
      def self.erp_name
        'TestErp'
      end

      def phone_from(data)
        data['phone']
      end

      def external_id_from(data)
        data['id']&.to_s
      end

      def find_by_id(id); end

      def search_by_phone(phone); end
    end
  end

  describe '#initialize' do
    it 'stores the hook and defaults settings to an empty hash when nil' do
      subclass = Class.new(described_class) do
        def configured_hook
          @hook
        end

        def configured_settings
          @settings
        end
      end

      adapter = subclass.new(hook)
      expect(adapter.configured_hook).to eq(hook)
      expect(adapter.configured_settings).to eq({ 'token' => 'abc' })

      nil_settings_hook = instance_double(Integrations::Hook, settings: nil)
      adapter_with_nil_settings = subclass.new(nil_settings_hook)
      expect(adapter_with_nil_settings.configured_settings).to eq({})
    end
  end

  describe '.erp_name' do
    it 'raises NotImplementedError naming the class and method when not overridden' do
      expect { described_class.erp_name }.to raise_error(NotImplementedError, 'Erp::BaseAdapter must implement self.erp_name')
    end
  end

  describe '#test_connection' do
    it 'raises NotImplementedError naming the class and method when not overridden' do
      adapter = described_class.new(hook)
      expect { adapter.test_connection }.to raise_error(NotImplementedError, 'Erp::BaseAdapter must implement #test_connection')
    end
  end

  describe '#phone_matches?' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'matches exact phone digits (U12)' do
      contact = instance_double(Contact, phone_number: '(11) 98765-4321')
      erp_data = { 'phone' => '11987654321' }

      expect(adapter.phone_matches?(contact, erp_data)).to be(true)
    end

    it 'matches contact phone stripping country code 55 prefix (U13)' do
      contact = instance_double(Contact, phone_number: '+5511987654321')
      erp_data = { 'phone' => '11987654321' }

      expect(adapter.phone_matches?(contact, erp_data)).to be(true)
    end

    it 'matches erp phone stripping country code 55 prefix (U14)' do
      contact = instance_double(Contact, phone_number: '11987654321')
      erp_data = { 'phone' => '+5511987654321' }

      expect(adapter.phone_matches?(contact, erp_data)).to be(true)
    end

    it 'returns false for mismatched phone digits (U15)' do
      contact = instance_double(Contact, phone_number: '11987654321')
      erp_data = { 'phone' => '11911112222' }

      expect(adapter.phone_matches?(contact, erp_data)).to be(false)
    end

    it 'returns false for nil or blank phone numbers (U16)' do
      contact_with_nil = instance_double(Contact, phone_number: nil)
      contact_with_blank = instance_double(Contact, phone_number: '   ')
      erp_with_phone = { 'phone' => '11987654321' }

      expect(adapter.phone_matches?(contact_with_nil, erp_with_phone)).to be(false)
      expect(adapter.phone_matches?(contact_with_blank, erp_with_phone)).to be(false)

      contact_with_phone = instance_double(Contact, phone_number: '11987654321')
      expect(adapter.phone_matches?(contact_with_phone, { 'phone' => nil })).to be(false)
      expect(adapter.phone_matches?(contact_with_phone, { 'phone' => '' })).to be(false)
      expect(adapter.phone_matches?(nil, erp_with_phone)).to be(false)
      expect(adapter.phone_matches?(contact_with_phone, nil)).to be(false)
    end
  end

  describe '#external_id_key' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'computes external_id_key from erp_name (U17)' do
      expect(adapter.external_id_key).to eq('testerp_id')
    end
  end

  describe '#get_external_id' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'reads external id from contact additional attributes (U18)' do
      contact = instance_double(
        Contact,
        additional_attributes: { 'external' => { 'testerp_id' => 'cust-99' } }
      )

      expect(adapter.get_external_id(contact)).to eq('cust-99')

      contact_without_attrs = instance_double(Contact, additional_attributes: nil)
      expect(adapter.get_external_id(contact_without_attrs)).to be_nil

      expect(adapter.get_external_id(nil)).to be_nil
    end
  end

  describe '#store_external_id' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'stores external id in contact additional attributes and saves (U19)' do
      contact = instance_double(Contact, additional_attributes: {})
      allow(contact).to receive(:additional_attributes=)
      allow(contact).to receive(:save!)

      adapter.store_external_id(contact, 'cust-42')

      expect(contact).to have_received(:additional_attributes=).with(
        { 'external' => { 'testerp_id' => 'cust-42' } }
      )
      expect(contact).to have_received(:save!)
    end
  end

  describe '#clear_external_id' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'clears external id from contact and saves (U20)' do
      contact = instance_double(
        Contact,
        additional_attributes: { 'external' => { 'testerp_id' => 'cust-42', 'other_id' => '123' } }
      )
      allow(contact).to receive(:additional_attributes=)
      allow(contact).to receive(:save!)

      adapter.clear_external_id(contact)

      expect(contact).to have_received(:additional_attributes=).with(
        { 'external' => { 'other_id' => '123' } }
      )
      expect(contact).to have_received(:save!)
    end
  end

  describe '#fetch_data' do
    let(:adapter) { test_adapter_class.new(hook) }

    it 'short-circuits to not_found when contact phone is blank (U21)' do
      contact = instance_double(Contact, phone_number: '')
      allow(adapter).to receive(:find_by_id)
      allow(adapter).to receive(:search_by_phone)

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'not_found' })
      expect(adapter).not_to have_received(:find_by_id)
      expect(adapter).not_to have_received(:search_by_phone)
    end

    it 'uses direct id lookup when cached id phone matches (U22)' do
      contact = instance_double(
        Contact,
        phone_number: '+5511987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'cust-123' } }
      )
      record = { 'id' => 'cust-123', 'phone' => '11987654321', 'name' => 'Maria' }

      allow(adapter).to receive(:find_by_id).with('cust-123').and_return(record)
      allow(adapter).to receive(:search_by_phone)

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'found', data: record, multiple_matches: false })
      expect(adapter).to have_received(:find_by_id).with('cust-123')
      expect(adapter).not_to have_received(:search_by_phone)
    end

    it 'invalidates cached id and falls back to phone search on phone mismatch (U23)' do
      contact = instance_double(
        Contact,
        phone_number: '+5511987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'stale-id' } }
      )
      mismatched_record = { 'id' => 'stale-id', 'phone' => '11999990000', 'name' => 'Other' }
      fresh_record = { 'id' => 'new-id', 'phone' => '11987654321', 'name' => 'Maria' }

      allow(adapter).to receive(:find_by_id).with('stale-id').and_return(mismatched_record)
      allow(adapter).to receive(:clear_external_id).with(contact)
      allow(adapter).to receive(:search_by_phone).with('11987654321').and_return({ record: fresh_record, multiple_matches: false })
      allow(adapter).to receive(:store_external_id).with(contact, 'new-id')

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'found', data: fresh_record, multiple_matches: false })
      expect(adapter).to have_received(:clear_external_id).with(contact)
      expect(adapter).to have_received(:search_by_phone).with('11987654321')
      expect(adapter).to have_received(:store_external_id).with(contact, 'new-id')
    end

    it 'invalidates cached id and falls back to phone search on id not found (U24)' do
      contact = instance_double(
        Contact,
        phone_number: '+5511987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'deleted-id' } }
      )
      fresh_record = { 'id' => 'fresh-id', 'phone' => '11987654321', 'name' => 'Maria' }

      allow(adapter).to receive(:find_by_id).with('deleted-id').and_return(nil)
      allow(adapter).to receive(:clear_external_id).with(contact)
      allow(adapter).to receive(:search_by_phone).with('11987654321').and_return({ record: fresh_record, multiple_matches: false })
      allow(adapter).to receive(:store_external_id).with(contact, 'fresh-id')

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'found', data: fresh_record, multiple_matches: false })
      expect(adapter).to have_received(:clear_external_id).with(contact)
      expect(adapter).to have_received(:search_by_phone).with('11987654321')
      expect(adapter).to have_received(:store_external_id).with(contact, 'fresh-id')
    end

    it 'does not re-save external id when fallback search resolves the same cached id' do
      contact = instance_double(
        Contact,
        phone_number: '+5511987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'same-id' } }
      )
      same_record = { 'id' => 'same-id', 'phone' => '11987654321', 'name' => 'Maria' }

      allow(adapter).to receive(:find_by_id).with('same-id').and_return(nil)
      allow(adapter).to receive(:clear_external_id)
      allow(adapter).to receive(:search_by_phone).with('11987654321').and_return({ record: same_record, multiple_matches: false })
      allow(adapter).to receive(:store_external_id)

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'found', data: same_record, multiple_matches: false })
      expect(adapter).not_to have_received(:clear_external_id)
      expect(adapter).not_to have_received(:store_external_id)
    end

    it 'clears cached id and returns not_found when fallback search returns nil (U25)' do
      contact = instance_double(
        Contact,
        phone_number: '+5511987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'stale-id' } }
      )

      allow(adapter).to receive(:find_by_id).with('stale-id').and_return(nil)
      allow(adapter).to receive(:clear_external_id).with(contact)
      allow(adapter).to receive(:search_by_phone).with('11987654321').and_return(nil)

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'not_found' })
      expect(adapter).to have_received(:clear_external_id).with(contact)
      expect(adapter).to have_received(:search_by_phone).with('11987654321')
    end

    it 'caches first record and returns multiple_matches true on multiple results (U26)' do
      contact = instance_double(
        Contact,
        phone_number: '11987654321',
        additional_attributes: {}
      )
      first_record = { 'id' => 'first-id', 'phone' => '11987654321', 'name' => 'First Match' }

      allow(adapter).to receive(:search_by_phone).with('11987654321').and_return({ record: first_record, multiple_matches: true })
      allow(adapter).to receive(:store_external_id).with(contact, 'first-id')

      result = adapter.fetch_data(contact)

      expect(result).to eq({ status: 'found', data: first_record, multiple_matches: true })
      expect(adapter).to have_received(:store_external_id).with(contact, 'first-id')
    end

    it 'propagates adapter exceptions on remote failure (U27)' do
      contact = instance_double(
        Contact,
        phone_number: '11987654321',
        additional_attributes: { 'external' => { 'testerp_id' => 'cust-1' } }
      )

      allow(adapter).to receive(:find_by_id).with('cust-1')
                                            .and_raise(Erp::AuthenticationError, 'Invalid credentials')
      expect { adapter.fetch_data(contact) }
        .to raise_error(Erp::AuthenticationError, 'Invalid credentials')

      allow(adapter).to receive(:find_by_id).with('cust-1')
                                            .and_raise(Erp::ApiError, 'Server error')
      expect { adapter.fetch_data(contact) }
        .to raise_error(Erp::ApiError, 'Server error')
    end
  end
end
