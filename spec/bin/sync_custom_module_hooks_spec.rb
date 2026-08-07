require 'English'
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
    [output, $CHILD_STATUS.exitstatus]
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

  describe '--audit' do
    around do |example|
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          system('git init >/dev/null 2>&1')
          system('git config user.name "Test" && git config user.email "test@example.com"')
          system('git commit --allow-empty -m "Initial commit" >/dev/null 2>&1')
          system('git checkout -b develop >/dev/null 2>&1')
          example.run
        end
      end
    end

    def setup_files
      File.write('covered_file.js', 'content')
      File.write('gap_file.js', 'content')
      FileUtils.mkdir_p('db')
      File.write('db/schema.rb', 'schema')
      FileUtils.mkdir_p('spec')
      File.write('spec/test_spec.rb', 'test')
      FileUtils.mkdir_p('app/javascript/dashboard/i18n/locale/fr')
      File.write('app/javascript/dashboard/i18n/locale/fr/test.json', 'json')
      FileUtils.mkdir_p('app/models')
      File.write('app/models/user.rb', "# == Schema Information\n#\n# Table name: users\n#\nclass User; end")

      system('git add . && git commit -m "Base" >/dev/null 2>&1')
      @base_ref = `git rev-parse HEAD`.strip

      system('git checkout -b feature >/dev/null 2>&1')

      File.write('covered_file.js', 'modified')
      File.write('gap_file.js', 'modified')
      File.write('db/schema.rb', 'modified schema')
      File.write('spec/test_spec.rb', 'modified test')
      File.write('app/javascript/dashboard/i18n/locale/fr/test.json', 'modified json')
      File.write('app/models/user.rb', "# == Schema Information\n#\n# Table name: users\n#\n#  id :integer\nclass User; end")
      File.write('new_file.js', 'new')

      system('git add . && git commit -m "Modifications" >/dev/null 2>&1')
    end

    it 'fails on unresolvable BASE_REF' do
      output, status = run_script('--audit invalid_ref')
      expect(status).not_to eq(0)
      expect(output).to include('ERROR: Unresolvable BASE_REF')
    end

    it 'classifies files into covered and gap, ignoring newly added files' do
      setup_files
      env = { 'TEST_MANIFEST' => '[{"file": "covered_file.js"}]' }
      output, status = run_script("--audit #{@base_ref}", env)

      expect(status).to eq(0)
      expect(output).to include('covered   covered_file.js')
      expect(output).to include('gap       gap_file.js')
      expect(output).not_to include('new_file.js')
      expect(output).to include('1 gaps found.')
    end

    it 'applies path-based exclusions and annotate-gem exclusion' do
      setup_files
      env = { 'TEST_MANIFEST' => '[]' }
      output, status = run_script("--audit #{@base_ref}", env)

      expect(status).to eq(0)
      expect(output).not_to include('db/schema.rb')
      expect(output).not_to include('spec/test_spec.rb')
      expect(output).not_to include('app/javascript/dashboard/i18n/locale/fr/test.json')
      expect(output).not_to include('app/models/user.rb')
    end

    it 'flags model file if change is outside annotate-gem block' do
      setup_files
      File.write('app/models/user.rb', "# == Schema Information\n#\n# Table name: users\n#\n#  id :integer\nclass User\n  def hello; end\nend")
      system('git add . && git commit -m "Unrelated change" >/dev/null 2>&1')

      env = { 'TEST_MANIFEST' => '[]' }
      output, status = run_script("--audit #{@base_ref}", env)

      expect(status).to eq(0)
      expect(output).to include('gap       app/models/user.rb')
    end
  end
end
