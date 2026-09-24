# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

# rubocop:disable RSpec/DescribeClass
describe 'ScoutV2 Playbooks boot initializer' do
  # rubocop:enable RSpec/DescribeClass
  let(:initializer_path) { Rails.root.join('config/initializers/scout_v2_playbooks.rb') }
  let(:tmp_dir) { Dir.mktmpdir('scout_v2_boot_spec') }

  after do
    FileUtils.rm_rf(tmp_dir)
  end

  it 'boots without error when playbooks are valid' do
    File.write(File.join(tmp_dir, 'valid.md'), <<~MD)
      ---
      name: valid_playbook
      title: Valid Title
      priority: 10
      trigger: Valid trigger
      ---
      Body content
    MD

    expect do
      with_modified_env SCOUT_V2_PLAYBOOKS_DIR: tmp_dir do
        load initializer_path
      end
    end.not_to raise_error
  end

  it 'raises ValidationError when playbooks have broken references' do
    File.write(File.join(tmp_dir, 'dup1.md'), <<~MD)
      ---
      name: dup1
      title: Duplicate One
      priority: 20
      trigger: Trigger 1
      ---
      Body 1
    MD

    File.write(File.join(tmp_dir, 'dup2.md'), <<~MD)
      ---
      name: dup2
      title: Duplicate Two
      priority: 20
      trigger: Trigger 2
      ---
      Body 2
    MD

    expect { with_modified_env(SCOUT_V2_PLAYBOOKS_DIR: tmp_dir) { load initializer_path } }.to raise_error do |error|
      expect(error.class.name).to eq('Custom::ScoutV2::Playbook::Validator::ValidationError')
      expect(error.violations).to contain_exactly(a_string_including('dup1.md', 'dup2.md', '20'))
    end
  end

  it 'fails boot when the configured directory does not exist' do
    expect { with_modified_env(SCOUT_V2_PLAYBOOKS_DIR: File.join(tmp_dir, 'typo')) { load initializer_path } }
      .to(raise_error { |error| expect(error.class.name).to eq('Errno::ENOENT') })
  end
end
