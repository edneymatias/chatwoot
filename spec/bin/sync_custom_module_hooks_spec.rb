require 'rails_helper'
require 'tempfile'
require 'fileutils'

RSpec.describe 'sync-custom-module-hooks' do
  let(:script_path) { Rails.root.join('bin/sync-custom-module-hooks') }

  before do
    # Ensure the script is executable
    FileUtils.chmod('+x', script_path) if File.exist?(script_path)
  end

  def run_script(args, env = {})
    # Need to escape env vars properly for shell
    env_str = env.map { |k, v| "#{k}='#{v}'" }.join(' ')
    output = `#{env_str} #{script_path} #{args} 2>&1`
    [output, $?.exitstatus]
  end

  it 'returns 0 and reports present on --check for clean checkout' do
    # We will test the actual script with a mock manifest
    Tempfile.open('test_file.js') do |f|
      f.write("anchor_line\ninsert_line\n")
      f.flush

      env = { 'TEST_MANIFEST' => "[{\"file\": \"#{f.path}\", \"anchor\": \"anchor_line\", \"insert\": \"insert_line\"}]" }
      output, status = run_script('--check', env)

      expect(status).to eq(0)
      expect(output).to include('All 1 wiring points present')
    end
  end

  it 'inserts on --apply and is idempotent' do
    Tempfile.open('test_file.js') do |f|
      f.write("anchor_line\n")
      f.flush

      env = { 'TEST_MANIFEST' => "[{\"file\": \"#{f.path}\", \"anchor\": \"anchor_line\", \"insert\": \"insert_line\"}]" }

      # First run
      _, status = run_script('--apply', env)
      expect(status).to eq(0)
      expect(File.read(f.path)).to include("anchor_line\ninsert_line")

      # Second run
      _, status2 = run_script('--apply', env)
      expect(status2).to eq(0)
    end
  end

  it 'fails if anchor is not found' do
    Tempfile.open('test_file.js') do |f|
      f.write("wrong_anchor\n")
      f.flush

      env = { 'TEST_MANIFEST' => "[{\"file\": \"#{f.path}\", \"anchor\": \"anchor_line\", \"insert\": \"insert_line\"}]" }
      output, status = run_script('--apply', env)

      expect(status).not_to eq(0)
      expect(output).to include("ERROR: anchor not found in #{f.path}: `anchor_line`")
    end
  end
end
