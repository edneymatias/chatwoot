class Meta::RateLimiter
  def initialize(account)
    @account = account
  end

  def within_limit?
    current_count < limit
  end

  def track_request
    request_key = build_request_key(SecureRandom.uuid)
    Redis::Alfred.set(request_key, '1', ex: window)
  end

  def current_count
    Redis::Alfred.keys_count(request_key_pattern)
  end

  private

  def limit
    200
  end

  def window
    1.minute.to_i
  end

  def request_key_pattern
    "meta_rate_limiter:#{@account.id}:*"
  end

  def build_request_key(request_id)
    "meta_rate_limiter:#{@account.id}:#{request_id}"
  end
end
