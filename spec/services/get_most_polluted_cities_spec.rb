require "rails_helper"

RSpec.describe GetMostPollutedCities do
  let(:client) do
    double("PolluApiClient",
      pollution_rows: [
        { country: "India", city: "Delhi", metric: 190.2 },
        { country: "India", city: "NotACityCorp", metric: 999.0 },
        { country: "France", city: "Paris", metric: 80.1 }
      ]
    )
  end

  before do
    allow(WikiClient).to receive(:summary_for).with("Delhi")
      .and_return({ is_cityish: true, extract: "Delhi is a city..." })
    allow(WikiClient).to receive(:summary_for).with("Paris")
      .and_return({ is_cityish: true, extract: "Paris is a city..." })
    allow(WikiClient).to receive(:summary_for).with("Notacitycorp")
      .and_return({ is_cityish: false })
  end

  it "returns worst city per country enriched with wiki" do
    data = described_class.new(client: client).call
    expect(data.map { |h| h[:country] }).to match_array(%w[France India])
    expect(data.find { |h| h[:country] == "India" }[:city]).to eq("Delhi")
  end
end
