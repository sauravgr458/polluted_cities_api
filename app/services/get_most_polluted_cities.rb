# frozen_string_literal: true

class GetMostPollutedCities
  # Public entry point
  def self.call
    new.call
  end

  def initialize(client: PolluApiClient.new)
    @client = client
  end

  def call
    rows = @client.pollution_rows

    # 1) Normalize + prefilter rows that look like cities
    normalized = rows.map { |r| normalize_record(r) }.compact

    # 2) Keep the worst (max metric) per country per city, then pick top per country
    by_country_city = normalized.group_by { |r| [r[:country], r[:city]] }.transform_values do |list|
      list.max_by { |r| r[:metric] }
    end.values

    by_country = by_country_city.group_by { |r| r[:country] }
    worst_by_country = by_country.map do |country, list|
      list.max_by { |r| r[:metric] }.merge(country: country)
    end

    # 3) Enrich with Wikipedia descriptions (cached)
    #    To respect rate limits, do this sequentially with short-circuit caching (already handled by client).
    result = worst_by_country.map do |rec|
      wiki = WikiClient.summary_for(rec[:city])
      next unless wiki&.dig(:is_cityish)

      {
        country: rec[:country],
        city: rec[:city],
        pollution_index: rec[:metric].round(2),
        description: wiki[:extract] || wiki[:description] || "No description available."
      }
    end.compact

    # 4) Sort predictably
    result.sort_by { |h| h[:country] }
  end

  private

  def normalize_record(r)
    country = tidy_country(r[:country])
    city    = CityValidator.normalize(r[:city])
    metric  = r[:metric].to_f

    return nil if country.blank? || city.blank?
    return nil unless CityValidator.valid_city_name_syntax?(city)

    # Gate with a quick cache-backed Wikipedia check to weed out non-city items
    return nil unless CityValidator.real_city?(city)

    { country: country, city: city, metric: metric }
  end

  def tidy_country(raw)
    s = raw.to_s.strip
    # Keep it simple: trim, titleize common all-caps, remove stray punctuation
    s = s.gsub(/\s+/, " ").gsub(/[^\p{L}\p{M}\s\-']/u, "")
    s.split(/\s+/).map { |t| t[0].upcase + t[1..].downcase }.join(" ")
  end
end
