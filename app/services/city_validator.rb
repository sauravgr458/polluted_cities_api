# frozen_string_literal: true

class CityValidator
  def self.normalize(raw)
    return nil if raw.blank?
    s = raw.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
             .gsub(/\s+/, " ")
             .gsub(/[^\p{L}\p{M}\-'\s]/u, "") # keep letters, diacritics, hyphen, apostrophe, space
             .strip
    return nil if s.blank?

    # Titleize but keep McDonald's-style words, hyphens, O'…
    s = s.split(/\s+/).map { |token| token.split("-").map { |t| smart_cap(t) }.join("-") }.join(" ")
    s
  end

  def self.valid_city_name_syntax?(name)
    return false if name.blank?
    # at least 2 letters
    name.gsub(/[^A-Za-z]/, "").size >= 2
  end

  def self.real_city?(name)
    # Caller may pass country to be stricter in future;
    # for now we only use Wikipedia summary heuristics.
    summary = WikiClient.summary_for(name)
    summary && summary[:is_cityish]
  end

  def self.smart_cap(word)
    return word if word =~ /^[A-Z]{2,}$/ # already acronym
    return word if word =~ /\A(?:Mc|Mac|O')/i && word[0] == word[0].upcase
    word[0].upcase + word[1..].to_s.downcase
  end
end
