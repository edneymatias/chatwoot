# Bulk reindex all messages with throttling to prevent DB overload
# This creates jobs slowly to avoid overwhelming the database connection pool
# Usage: RAILS_ENV=production POSTGRES_STATEMENT_TIMEOUT=6000s bundle exec rails runner script/bulk_reindex_messages.rb

JOBS_PER_MINUTE = 50  # Adjust based on your DB capacity
BATCH_SIZE = 1000     # Messages per job

batch_count = 0
total_batches = (Message.count / BATCH_SIZE.to_f).ceil
start_time = Time.zone.now

index_name = Message.searchkick_index.name

Rails.logger.debug '=' * 80
Rails.logger.debug { "Bulk Reindex Started at #{start_time}" }
Rails.logger.debug '=' * 80
Rails.logger.debug { "Total messages: #{Message.count}" }
Rails.logger.debug { "Batch size: #{BATCH_SIZE}" }
Rails.logger.debug { "Total batches: #{total_batches}" }
Rails.logger.debug { "Index name: #{index_name}" }
Rails.logger.debug { "Rate: #{JOBS_PER_MINUTE} jobs/minute (#{JOBS_PER_MINUTE * BATCH_SIZE} messages/minute)" }
Rails.logger.debug { "Estimated time: #{(total_batches / JOBS_PER_MINUTE.to_f / 60).round(2)} hours" }
Rails.logger.debug '=' * 80
Rails.logger.debug ''

sleep(15)

Message.find_in_batches(batch_size: BATCH_SIZE).with_index do |batch, index|
  batch_count += 1

  # Enqueue to low priority queue with proper format
  Searchkick::BulkReindexJob.set(queue: :bulk_reindex_low).perform_later(
    class_name: 'Message',
    index_name: index_name,
    batch_id: index,
    record_ids: batch.map(&:id)  # Keep as integers like Message.reindex does
  )

  # Throttle: wait after every N jobs
  if (batch_count % JOBS_PER_MINUTE).zero?
    elapsed = Time.zone.now - start_time
    progress = (batch_count.to_f / total_batches * 100).round(2)
    queue_size = Sidekiq::Queue.new('bulk_reindex_low').size

    Rails.logger.debug { "[#{Time.zone.now.strftime('%Y-%m-%d %H:%M:%S')}] Progress: #{batch_count}/#{total_batches} (#{progress}%)" }
    Rails.logger.debug { "  Queue size: #{queue_size}" }
    Rails.logger.debug { "  Elapsed: #{(elapsed / 3600).round(2)} hours" }
    Rails.logger.debug { "  ETA: #{((elapsed / batch_count * (total_batches - batch_count)) / 3600).round(2)} hours remaining" }
    Rails.logger.debug ''

    sleep(60)
  end
end

Rails.logger.debug '=' * 80
Rails.logger.debug { "Done! Created #{batch_count} jobs" }
Rails.logger.debug { "Total time: #{((Time.zone.now - start_time) / 3600).round(2)} hours" }
Rails.logger.debug '=' * 80
