# rubocop:disable Metrics/BlockLength
namespace :meta_marketing do
  desc 'Backfill referral attribution from Whatsapp referral messages to existing Opportunities (including previews & organic posts)'
  task :backfill_referral_attribution, [:account_id] => :environment do |_t, args|
    target_account_ids = if args[:account_id].present?
                           [args[:account_id]]
                         else
                           CampaignAttributionSetting.where(enabled: true).pluck(:account_id)
                         end

    if target_account_ids.blank?
      puts 'No accounts found with campaign attribution enabled. Nothing to backfill.'
      next
    end

    puts "Starting backfill for WhatsApp referral attribution (Accounts: #{target_account_ids.join(', ')})..."

    ActiveRecord::Base.connection.execute("SET statement_timeout = '30min'")

    # 1. Find referral messages scoped by enabled accounts
    messages_with_referrals = Message
                              .where(account_id: target_account_ids)
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

      # Synchronous capture of organic or ad referral metadata
      Custom::AutomationRules::ActionService.process_campaign_attribution(opportunity, message)
      processed_count += 1

      opportunity.reload
      if opportunity.campaign_source_id.present? || opportunity.campaign_resolution_status == 'organic_post'
        enqueued_count += 1
      else
        skipped_no_data_count += 1
      end
    end

    # 2. Enrich previously resolved opportunities that lack creative previews
    Opportunity.where(account_id: target_account_ids)
               .where(campaign_resolution_status: 'resolved', campaign_thumbnail_url: [nil, ''])
               .where.not(campaign_source_id: [nil, ''])
               .find_each do |opportunity|
      next unless opportunity.account.campaign_attribution_setting&.enabled?

      Custom::CampaignResolutionJob.perform_later(opportunity.id, force: true)
    end

    puts 'Backfill complete!'
    puts "Processed opportunities: #{processed_count}"
    puts "Jobs enqueued / updated: #{enqueued_count}"
    puts "Skipped (no opportunity found): #{missing_opportunity_count}"
    puts "Skipped (account gated/not enabled): #{skipped_account_gated_count}"
    puts "Skipped (lacking recoverable data): #{skipped_no_data_count}"
  end

  desc 'Backfill and re-fetch creative preview thumbnails for opportunities that lack a thumbnail'
  task :backfill_missing_previews, [:account_id] => :environment do |_t, args|
    target_account_ids = if args[:account_id].present?
                           [args[:account_id]]
                         else
                           CampaignAttributionSetting.where(enabled: true).pluck(:account_id)
                         end

    if target_account_ids.blank?
      puts 'No accounts found with campaign attribution enabled.'
      next
    end

    puts "Scanning opportunities lacking creative thumbnails / previews (Accounts: #{target_account_ids.join(', ')})..."

    requeued_ads_count = 0
    attached_blobs_count = 0

    # 1. Opportunities with thumbnail URL but without ActiveStorage blob attached
    Opportunity.where(account_id: target_account_ids)
               .where.not(campaign_thumbnail_url: [nil, ''])
               .find_each do |opportunity|
      next if opportunity.campaign_thumbnail.attached?

      Meta::AttachCampaignThumbnailJob.perform_later(opportunity.id, opportunity.campaign_thumbnail_url)
      attached_blobs_count += 1
    end

    # 2. Resolved ads that don't have thumbnail_url populated
    Opportunity.where(account_id: target_account_ids)
               .where(campaign_resolution_status: 'resolved', campaign_thumbnail_url: [nil, ''])
               .where.not(campaign_source_id: [nil, ''])
               .find_each do |opportunity|
      setting = opportunity.account.campaign_attribution_setting
      next unless setting&.enabled? && setting.provider_config['access_token'].present?

      Custom::CampaignResolutionJob.perform_later(opportunity.id, force: true)
      requeued_ads_count += 1
    end

    puts 'Preview backfill complete!'
    puts "Thumbnail downloads enqueued: #{attached_blobs_count}"
    puts "Ad creative re-fetches enqueued: #{requeued_ads_count}"
  end

  desc 'Inject a sample organic Instagram post attribution into an Opportunity without enqueuing resolution job'
  task :inject_organic_sample, [:opportunity_id] => :environment do |_t, args|
    opportunity = if args[:opportunity_id].present?
                    Opportunity.find(args[:opportunity_id])
                  else
                    Opportunity.where(campaign_source_id: [nil, '']).last || Opportunity.last
                  end

    unless opportunity
      puts '❌ Nenhuma oportunidade encontrada.'
      next
    end

    opportunity.update!(
      campaign_platform: 'instagram',
      campaign_source_id: '17892348912',
      campaign_source_url: 'https://www.instagram.com/p/DTxa5L4DL_8/',
      campaign_headline: 'Novidades da Semana no Feed',
      campaign_body: 'Confira todos os detalhes do nosso novo procedimento e agende sua avaliação pelo direct ou WhatsApp.',
      campaign_thumbnail_url: 'https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=300',
      campaign_resolution_status: 'organic_post'
    )

    puts "✅ Oportunidade ##{opportunity.id} (#{opportunity.title}) atualizada diretamente no banco como 'organic_post' " \
         '(nenhum job de resolução enfileirado).'
  end
end
# rubocop:enable Metrics/BlockLength
