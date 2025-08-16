require "rails_helper"

RSpec.describe "GET /cities", type: :request do
  it "returns 200 and expected shape" do
    allow(GetMostPollutedCities).to receive(:call).and_return([
      { country: "India", city: "Delhi", pollution: 190.2, description: "..." }
    ])

    get "/cities"
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["count"]).to eq(1)
    expect(json["data"].first["city"]).to eq("Delhi")
  end
end
