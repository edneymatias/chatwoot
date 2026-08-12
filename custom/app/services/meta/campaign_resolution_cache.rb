module Meta
  class CampaignResolutionCache
    TTL = 12.hours.to_i

    def self.read(campaign_source_id)
      data = Redis::Alfred.get(cache_key(campaign_source_id))
      return nil unless data

      JSON.parse(data).with_indifferent_access
    end

    def self.write(campaign_source_id, payload)
      Redis::Alfred.set(cache_key(campaign_source_id), payload.to_json, ex: TTL)
    end

    def self.cache_key(campaign_source_id)
      "meta_campaign_resolution:#{campaign_source_id}"
    end
  end
end
