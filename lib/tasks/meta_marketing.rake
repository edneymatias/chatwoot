namespace :meta_marketing do
  desc "Backfill referral attribution from Whatsapp referral messages to existing Opportunities"
  task backfill_referral_attribution: :environment do
    puts "Starting backfill for WhatsApp referral attribution..."

    # `content_attributes` has no index, so this scan can exceed the default
    # statement_timeout on large messages tables; extend it for this session.
    ActiveRecord::Base.connection.execute("SET statement_timeout = '30min'")

    # 1. Find all messages with referral content
    messages_with_referrals = Message
                                .where(message_type: :incoming)
                                .where("(content_attributes #>> '{}')::jsonb -> 'referral' IS NOT NULL")
                                .order(created_at: :asc)

    processed_count = 0
    enqueued_count = 0
    missing_opportunity_count = 0
    skipped_account_gated_count = 0
    skipped_no_data_count = 0

    messages_with_referrals.find_each do |message|
      opportunity = Opportunity.find_by(origin_conversation_id: message.conversation_id)
      
      if opportunity.nil?
        missing_opportunity_count += 1
        next
      end

      # Account gating check (FR-013 / FR-012)
      unless opportunity.account.campaign_attribution_setting&.enabled?
        skipped_account_gated_count += 1
        next
      end

      # Call the extracted synchronous capture logic
      Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, message)
      processed_count += 1
      
      # Re-fetch to check if campaign_source_id is set
      opportunity.reload
      if opportunity.campaign_source_id.present?
        enqueued_count += 1
      else
        skipped_no_data_count += 1
      end
    end
    
    puts "Backfill complete!"
    puts "Processed opportunities: #{processed_count}"
    puts "Jobs enqueued (resolution): #{enqueued_count}"
    puts "Skipped (no opportunity found): #{missing_opportunity_count}"
    puts "Skipped (account gated/not enabled): #{skipped_account_gated_count}"
    puts "Skipped (lacking recoverable data): #{skipped_no_data_count}"
  end
end
