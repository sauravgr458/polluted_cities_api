class PolluCacheWorker
  include Sidekiq::Worker

  def perform
    rows = GetMostPollutedCities.call
    Rails.cache.write("pollu_api:daily_rows", rows, expires_in: 24.hours)
    Rails.logger.info("[PolluCacheWorker] Cached #{rows.size} rows")
  end
end
