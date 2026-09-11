# frozen_string_literal: true

class Custom::Scout::ReferralInterestClassifierSchema < RubyLLM::Schema
  def self.for_options(options)
    sanitized_options = Array(options).map(&:to_s).reject(&:blank?).uniq

    Class.new(RubyLLM::Schema) do
      name 'ReferralInterestClassifierSchema'

      any_of :interest, description: 'The matched interest option from the ad content, or null if ambiguous or not identified' do
        string enum: sanitized_options
        null
      end
    end
  end
end
