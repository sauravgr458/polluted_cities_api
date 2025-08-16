# frozen_string_literal: true

class PolluApiClient
  DEFAULT_TIMEOUT = 10 # seconds
  COUNTRIES = %w[PL DE ES FR].freeze
  DEFAULT_LIMIT = 50.freeze
  CACHE_TTL = 600 # 10 minutes
  TOKEN_SKEW = 30 # seconds early refresh
  RATELIMIT_PER_MIN = 5
  RATE_KEY = "pollu_api:rate_window"

  def initialize(
    base: ENV.fetch("POLLU_API_BASE"),
    username: ENV.fetch("POLLU_API_USERNAME"),
    password: ENV.fetch("POLLU_API_PASSWORD")
  )
    @base = base
    @username = username
    @password = password

    @conn = Faraday.new(@base) do |f|
      f.options.timeout = DEFAULT_TIMEOUT
      f.response :json, content_type: /\bjson$/
      f.adapter :net_http
    end
  end

  # Public: fetch every country, all pages, normalize rows
  def pollution_rows
    Rails.cache.fetch(cache_key("pollution_rows_v2"), expires_in: CACHE_TTL.seconds) do
      COUNTRIES.flat_map { |cc| fetch_country_rows(cc) }
               .map { |row| normalize_row(row) }
               .compact
    end
  end

  # ---- internals -----------------------------------------------------------

  def fetch_country_rows(country_code)
    key = cache_key("country:#{country_code}:pages_v1")
    Rails.cache.fetch(key, expires_in: CACHE_TTL.seconds) do
      page = 1
      all = []
      Rails.logger.debug("[PolluApiClient] Fetching #{country_code} countries pollution page records...")
      loop do
        response = get_pollution_page(country_code:, page:, limit: DEFAULT_LIMIT)
        break if response.nil?

        results = Array(response["results"])
        all.concat(results.map { |res| res.merge!("countryCode" => country_code) })

        total_pages = (response["meta"]["totalPages"] || 1).to_i
        Rails.logger.debug("[PolluApiClient] Page #{page} records")
        page >= total_pages ? break : page += 1
      end
      Rails.logger.debug("[PolluApiClient] Fetched #{country_code} countries pollution page records.\n")
      all
    end
  end

  def get_pollution_page(country_code:, page:, limit:)
    unless health_check
      Rails.logger.warn("[PolluApiClient] Health check failed, skipping /pollution request")
      return nil
    end

    ensure_token!

    ratelimit_guard!

    resp = @conn.get("/pollution") do |req|
      req.headers["Authorization"] = "Bearer #{access_token}"
      req.params["country"] = country_code
      req.params["page"] = page
      req.params["limit"] = limit
    end

    if resp.status == 401
      # try once with a refresh->login fallback
      force_refresh_token!
      ratelimit_guard!
      resp = @conn.get("/pollution") do |req|
        req.headers["Authorization"] = "Bearer #{access_token}"
        req.params["country"] = country_code
        req.params["page"] = page
        req.params["limit"] = limit
      end
    end

    return resp.body if resp.status == 200 && resp.body.is_a?(Hash)

    Rails.logger.warn("[PolluApiClient] GET /pollution #{country_code} p#{page} -> #{resp.status} #{resp.body.inspect}")
    nil
  rescue => e
    Rails.logger.warn("[PolluApiClient] GET /pollution error: #{e.class}: #{e.message}")
    nil
  end

  # ---- health check --------------------------------------------------------

  def health_check
    resp = @conn.get("/healthz")
    if resp.status == 200
      true
    else
      Rails.logger.warn("[PolluApiClient] GET /healthz -> #{resp.status} #{resp.body.inspect}")
      false
    end
  rescue => e
    Rails.logger.warn("[PolluApiClient] GET /healthz error: #{e.class}: #{e.message}")
    false
  end

  # ---- auth/token handling -------------------------------------------------

  def ensure_token!
    # fetch from cache
    tok = Rails.cache.read(cache_key("auth"))
    if tok && tok[:access_token] && (Time.now.to_i + TOKEN_SKEW) < tok[:access_expires_at].to_i
      @access_token = tok[:access_token]
      @refresh_token = tok[:refresh_token]
      @access_expires_at = tok[:access_expires_at]
      return
    end

    # try refresh first if we have a refresh_token
    if tok && tok[:refresh_token]
      if refresh_token!(tok[:refresh_token])
        persist_auth!
        return
      end
    end

    # fresh login
    login!
    persist_auth!
  end

  def force_refresh_token!
    tok = Rails.cache.read(cache_key("auth"))
    if tok && tok[:refresh_token] && refresh_token!(tok[:refresh_token])
      persist_auth!
    else
      login!
      persist_auth!
    end
  end

  def login!
    resp = @conn.post("/auth/login") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { username: @username, password: @password }.to_json
    end

    unless resp.status == 200 && resp.body.is_a?(Hash)
      raise "Login failed (status=#{resp.status})"
    end

    body = resp.body
    @access_token  = body["token"]
    @refresh_token = body["refreshToken"]
    @access_expires_at = Time.now.to_i + body.fetch("expiresIn", 900).to_i # seconds
  end

  def refresh_token!(refresh_token)
    resp = @conn.post("/auth/refresh") do |req|
      req.headers["Content-Type"] = "application/json"
      req.body = { refreshToken: refresh_token }.to_json
    end

    return false unless resp.status == 200 && resp.body.is_a?(Hash)

    body = resp.body
    @access_token  = body["accessToken"]
    @access_expires_at = Time.now.to_i + body.fetch("expiresIn", 900).to_i
    # keep existing @refresh_token
    true
  rescue
    false
  end

  def access_token = @access_token

  def persist_auth!
    Rails.cache.write(
      cache_key("auth"),
      {
        access_token: @access_token,
        refresh_token: @refresh_token,
        access_expires_at: @access_expires_at
      },
      expires_in: 12.hours
    )
  end

  # ---- helpers -------------------------------------------------------------

  def normalize_row(row)
    return nil unless row.is_a?(Hash)

    country = str(row["country"] || row["countryCode"])
    city = str(row["name"])
    pollution = row["pollution"]

    return nil if country.blank? || city.blank? || pollution.nil?

    {
      country: country,
      city: city,
      metric: pollution
    }
  rescue
    nil
  end

  def numeric?(v)
    true if Float(v) rescue false
  end

  def str(v)
    v.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "").strip
  end

  def cache_key(suffix) = "pollu_api:#{suffix}"

  # Simple sliding-window limiter for 5 req/min
  def ratelimit_guard!
    win = (Rails.cache.read(RATE_KEY) || []).select { |t| t > (Time.now.to_f - 60.0) }

    if win.size >= RATELIMIT_PER_MIN
      sleep_for = (win.first + 60.0) - Time.now.to_f
      sleep(sleep_for) if sleep_for.positive?
      win = win.drop(1)
    end

    win << Time.now.to_f
    Rails.cache.write(RATE_KEY, win, expires_in: 2.minutes)
  rescue
    # fail-open if cache not available
    nil
  end
end
