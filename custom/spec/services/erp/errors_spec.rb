# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Erp::Error do
  it 'inherits expected error hierarchies' do
    expect(described_class.ancestors).to include(StandardError)
    expect(Erp::AuthenticationError.ancestors).to include(described_class)
    expect(Erp::ApiError.ancestors).to include(described_class)
  end
end
