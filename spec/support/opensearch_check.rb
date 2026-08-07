# frozen_string_literal: true

require 'net/http'
require 'json'

RSpec.configure do |config|
  # Run OpenSearch connectivity check only for specs tagged with :opensearch
  config.before(:context, :opensearch) do
    opensearch_url = ENV.fetch('OPENSEARCH_URL', nil)

    next if opensearch_url.blank?

    Rails.logger.debug "\n==== OpenSearch Connectivity Check ===="
    Rails.logger.debug { "OPENSEARCH_URL: #{opensearch_url}" }

    begin
      uri = URI.parse("#{opensearch_url}/_cluster/health")
      response = Net::HTTP.get_response(uri)

      raise "OpenSearch is not reachable at #{opensearch_url}. HTTP Status: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      health = JSON.parse(response.body)
      status = health['status']

      Rails.logger.debug { "Cluster status: #{status}" }
      Rails.logger.debug { "Cluster name: #{health['cluster_name']}" }
      Rails.logger.debug { "Number of nodes: #{health['number_of_nodes']}" }

      raise "OpenSearch cluster is not healthy. Status: #{status}" unless %w[green yellow].include?(status)

      Rails.logger.debug '✓ OpenSearch is healthy and ready for tests'
      Rails.logger.debug "========================================\n\n"
    rescue StandardError => e
      Rails.logger.debug "\n❌ ERROR: Failed to connect to OpenSearch"
      Rails.logger.debug { "Message: #{e.message}" }
      Rails.logger.debug "========================================\n\n"
      raise "OpenSearch connectivity check failed: #{e.message}"
    end
  end
end
