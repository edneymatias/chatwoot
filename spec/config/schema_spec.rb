# frozen_string_literal: true

require 'rails_helper'

# Regression guard: this dev DB was seeded from a production dump that carried n8n-managed
# LISTEN/NOTIFY triggers on channel_api (see commit 125778020f and AGENTS.md's "Direct Upstream
# Patches"/local DB hygiene notes). Because db/schema.rb is auto-regenerated from whatever
# database `db:schema:dump`/`db:migrate` last ran against, a locally re-contaminated dev DB
# silently reintroduces these triggers into the committed schema on the next dump. This spec
# fails loudly the moment that happens again, instead of only surfacing as a cryptic
# `PG::UndefinedFunction` on the next fresh `db:test:prepare`/`db:schema:load`.
# rubocop:disable RSpec/DescribeClass
describe 'db/schema.rb' do
  # rubocop:enable RSpec/DescribeClass
  it 'does not contain leaked n8n LISTEN/NOTIFY triggers or functions' do
    schema_source = Rails.root.join('db/schema.rb').read

    expect(schema_source).not_to match(/n8n/i)
  end
end
