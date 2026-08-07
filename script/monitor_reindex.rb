# Monitor bulk reindex progress
# RAILS_ENV=production bundle exec rails runner script/monitor_reindex.rb

Rails.logger.debug 'Monitoring bulk reindex progress (Ctrl+C to stop)...'
Rails.logger.debug ''

loop do
  bulk_queue = Sidekiq::Queue.new('bulk_reindex_low')
  prod_queue = Sidekiq::Queue.new('async_database_migration')
  retry_set = Sidekiq::RetrySet.new

  Rails.logger.debug { "[#{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S')}]" }
  Rails.logger.debug { "  Bulk Reindex Queue: #{bulk_queue.size} jobs" }
  Rails.logger.debug { "  Production Queue: #{prod_queue.size} jobs" }
  Rails.logger.debug { "  Retry Queue: #{retry_set.size} jobs" }
  Rails.logger.debug { "  #{('-' * 60)}" }

  sleep(30)
end
