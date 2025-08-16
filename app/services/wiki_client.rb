# frozen_string_literal: true

class WikiClient
  API_BASE = ENV.fetch("WIKI_API_BASE")
  TIMEOUT = 10

  # Summary docs:
  #
  # Returns:
  # {
  #   title, extract, description, is_cityish
  # }
  def self.summary_for(title)
    return nil if title.blank?

    cache_key = "wiki:action_summary:#{title.downcase}"
    Rails.cache.fetch(cache_key, expires_in: 24.hours) do
      Rails.logger.debug("[WikiClient] Fetching summary for #{title}...")
      resp = client.get("", {
        action: "query",
        prop: "extracts|description",
        titles: title,
        exintro: 1,
        explaintext: 1,
        redirects: 1,
        format: "json"
      })

      return nil unless resp.status == 200
      body = resp.body
      page = body.dig("query", "pages")&.values&.first
      Rails.logger.debug("[WikiClient] Fetched summary for #{title}. RESP TITLE::#{page["title"]}\n")
      next nil unless page

      {
        title:       page["title"],
        description: page["description"],
        extract:     page["extract"],
        is_cityish: cityish?(page)
      }
    end
  rescue => e
    Rails.logger.warn("[WikiClient] action summary error: #{e.class}: #{e.message}")
    nil
  end


  def self.cityish?(body)
    # Heuristics:
    #  - description contains "city", "town", "capital", "metropolis"
    #  - extract mentions city in the first sentence
    #  - avoid known non-places ("company", "film", "album", "person", etc.)
    desc = (body["description"] || "").downcase
    ext  = (body["extract"] || "").downcase

    positive = %w[city town capital metropolis municipality urban conurbation]
    negative = %w[company film album band software character person tv series song video game]

    return false if negative.any? { |w| desc.include?(w) || ext.include?(w) }
    return true  if positive.any? { |w| desc.include?(w) || ext.include?(w) }

    # Some pages don’t include a helpful “description” string; allow neutral truthiness
    # if the title or extract includes “city of …”
    ext.include?(" city ")
  end

  def self.client
    Faraday.new(API_BASE) do |f|
      f.options.timeout = TIMEOUT
      f.response :json, content_type: /\bjson$/
      f.adapter :net_http
    end
  end
end
