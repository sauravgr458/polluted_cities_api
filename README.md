# Polluted Cities API (Rails)

**Endpoint:** `GET /cities`  
Returns the most polluted city **per country**, filtered to real cities and enriched with Wikipedia descriptions.

## How to run

# Install
ruby -v  # 3.3.x

rails -v # 7.x

# Run
`bundle install`

# set env vars
```
export POLLU_API_BASE=https://be-recruitment-task.onrender.com
export POLLU_API_USERNAME=testuser
export POLLU_API_PASSWORD=testpass
export WIKI_API_BASE=https://en.wikipedia.org/api/rest_v1
```

# start
`bin/rails server`

GET http://localhost:3000/cities

# Response shape
```
{
  "generated_at": "2025-08-15T08:10:00Z",
  "count": 2,
  "data": [
    {
      "country": "India",
      "city": "Delhi",
      "pollution_index": 190.2,
      "description": "Delhi is the capital city of India..."
    },
    {
      "country": "France",
      "city": "Paris",
      "pollution_index": 80.1,
      "description": "Paris is the capital and most populous city of France..."
    }
  ]
}
```

# How we decide whether something is a real city
We combine syntax checks + Wikipedia verification:

    1. Normalization: strip weird chars, title-case with support for hyphens/apostrophes.
    2. Syntactic checks: at least 2 letters present.
    3. Wikipedia summary check (cached 24h): we fetch API endpoint and mark it city-ish if:
        - The description or first extract sentence includes any of: city, town, capital, metropolis, municipality, urban, or
        - The extract contains “ city ”, and
        - It does not look like a non-place (company, film, album, person, etc.).
Only rows passing all three gates are considered “actual cities”.

# Upstream data cleanup
The upstream feed can have typos/corruption. We handle it by:
- Ignoring rows missing country, city, or a numeric pollution metric.
- Normalizing country/city text (UTF-8 clean, whitespace, punctuation).
- Deduplicating by (country, city) and taking the max metric for that pair.

# Enrichment & Rate limits
- Wikipedia summaries are cached for 24h per city in Rails.cache (memory by default; use Redis in prod).
- Upstream pollution rows are cached 10 minutes to avoid hammering the mock API.
- Enrichment is sequential and cache-first to avoid bursts.

# Tests

```
bundle exec rspec
```
