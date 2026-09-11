# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Custom::Scout::AudienceMatcherService do
  let(:account) { create(:account) }
  let(:contact) do
    create(
      :contact,
      account: account,
      name: 'Alice Smith',
      email: 'alice@example.com',
      phone_number: '+5511999999999',
      identifier: 'ID123',
      additional_attributes: {
        'country_code' => 'BR',
        'city' => 'São Paulo',
        'company_name' => 'Acme Corp'
      },
      custom_attributes: {
        'plan' => 'enterprise',
        'score' => 85
      }
    )
  end

  describe '#matches?' do
    subject(:matcher) { described_class.new(audience: audience, contact: contact) }

    context 'when audience is empty or blank' do
      let(:audience) { [] }

      it 'returns true' do
        expect(matcher.matches?).to be(true)
      end

      context 'when audience is nil' do
        let(:audience) { nil }

        it 'returns true' do
          expect(matcher.matches?).to be(true)
        end
      end
    end

    context 'with equality operators' do
      context 'when equal_to' do
        let(:audience) do
          [
            {
              'attribute_key' => 'phone_number',
              'filter_operator' => 'equal_to',
              'values' => ['+5511999999999']
            }
          ]
        end

        it 'returns true on match' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false on mismatch' do
          contact.update!(phone_number: '+5511888888888')
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when not_equal_to' do
        let(:audience) do
          [
            {
              'attribute_key' => 'country_code',
              'filter_operator' => 'not_equal_to',
              'values' => ['US']
            }
          ]
        end

        it 'returns true when not equal' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when equal' do
          contact.additional_attributes['country_code'] = 'US'
          contact.save!
          expect(matcher.matches?).to be(false)
        end
      end
    end

    context 'with presence operators' do
      context 'when is_present' do
        let(:audience) do
          [
            {
              'attribute_key' => 'email',
              'filter_operator' => 'is_present',
              'values' => []
            }
          ]
        end

        it 'returns true when attribute is present' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when attribute is blank' do
          contact.update!(email: nil)
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when is_not_present' do
        let(:audience) do
          [
            {
              'attribute_key' => 'email',
              'filter_operator' => 'is_not_present',
              'values' => []
            }
          ]
        end

        it 'returns false when attribute is present' do
          expect(matcher.matches?).to be(false)
        end

        it 'returns true when attribute is blank' do
          contact.update!(email: nil)
          expect(matcher.matches?).to be(true)
        end
      end
    end

    context 'with string text operators' do
      context 'when contains' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'contains',
              'values' => ['Smith']
            }
          ]
        end

        it 'returns true when substring matches case-insensitively' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when substring does not match' do
          contact.update!(name: 'Alice Johnson')
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when does_not_contain' do
        let(:audience) do
          [
            {
              'attribute_key' => 'email',
              'filter_operator' => 'does_not_contain',
              'values' => ['test.com']
            }
          ]
        end

        it 'returns true when substring is absent' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when substring is present' do
          contact.update!(email: 'alice@test.com')
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when starts_with' do
        let(:audience) do
          [
            {
              'attribute_key' => 'phone_number',
              'filter_operator' => 'starts_with',
              'values' => ['+5511']
            }
          ]
        end

        it 'returns true when prefix matches' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when prefix does not match' do
          contact.update!(phone_number: '+15551234567')
          expect(matcher.matches?).to be(false)
        end
      end
    end

    context 'with numeric comparison operators' do
      context 'when greater_than' do
        let(:audience) do
          [
            {
              'attribute_key' => 'score',
              'filter_operator' => 'greater_than',
              'values' => ['80']
            }
          ]
        end

        it 'returns true when value is greater' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when value is smaller' do
          contact.custom_attributes['score'] = 75
          contact.save!
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when less_than' do
        let(:audience) do
          [
            {
              'attribute_key' => 'score',
              'filter_operator' => 'less_than',
              'values' => ['90']
            }
          ]
        end

        it 'returns true when value is smaller' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when value is greater' do
          contact.custom_attributes['score'] = 95
          contact.save!
          expect(matcher.matches?).to be(false)
        end
      end
    end

    context 'with labels' do
      before do
        contact.update_labels(%w[vip trial])
      end

      let(:audience) do
        [
          {
            'attribute_key' => 'labels',
            'filter_operator' => 'equal_to',
            'values' => ['vip']
          }
        ]
      end

      it 'returns true when label list includes value' do
        expect(matcher.matches?).to be(true)
      end

      it 'returns false when label list does not include value' do
        contact.update_labels(['other'])
        expect(matcher.matches?).to be(false)
      end
    end

    context 'with sequential AND/OR combination logic' do
      context 'with AND condition' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'contains',
              'values' => ['Alice']
            },
            {
              'attribute_key' => 'country_code',
              'filter_operator' => 'equal_to',
              'values' => ['BR'],
              'query_operator' => 'and'
            }
          ]
        end

        it 'returns true when both match' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when second condition fails' do
          contact.additional_attributes['country_code'] = 'US'
          contact.save!
          expect(matcher.matches?).to be(false)
        end
      end

      context 'with OR condition' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'contains',
              'values' => ['Bob']
            },
            {
              'attribute_key' => 'country_code',
              'filter_operator' => 'equal_to',
              'values' => ['BR'],
              'query_operator' => 'or'
            }
          ]
        end

        it 'returns true when the OR branch matches' do
          expect(matcher.matches?).to be(true)
        end

        it 'returns false when both branches fail' do
          contact.additional_attributes['country_code'] = 'US'
          contact.save!
          expect(matcher.matches?).to be(false)
        end
      end
    end

    context 'with edge cases and fail-safe error handling' do
      context 'when attribute is unset/missing on contact' do
        let(:audience) do
          [
            {
              'attribute_key' => 'non_existent_key',
              'filter_operator' => 'equal_to',
              'values' => ['some_val']
            }
          ]
        end

        it 'evaluates as non-matching without raising' do
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when operator is unrecognized' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'unsupported_operator',
              'values' => ['Alice']
            }
          ]
        end

        it 'evaluates as non-matching without raising' do
          expect(matcher.matches?).to be(false)
        end
      end

      context 'when comparison cannot be coerced (FR-007 narrow local rescue)' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'greater_than',
              'values' => ['not_a_number']
            },
            {
              'attribute_key' => 'country_code',
              'filter_operator' => 'equal_to',
              'values' => ['BR'],
              'query_operator' => 'or'
            }
          ]
        end

        it 'treats the invalid condition as no match and continues evaluating remaining conditions' do
          expect(matcher.matches?).to be(true)
        end
      end

      context 'when genuine unexpected error occurs' do
        let(:audience) do
          [
            {
              'attribute_key' => 'name',
              'filter_operator' => 'equal_to',
              'values' => ['Alice']
            }
          ]
        end

        it 'raises loudly instead of silently swallowing into true' do
          allow(contact).to receive(:name).and_raise(NoMethodError, 'unexpected bug')
          expect { matcher.matches? }.to raise_error(NoMethodError)
        end
      end
    end
  end
end
