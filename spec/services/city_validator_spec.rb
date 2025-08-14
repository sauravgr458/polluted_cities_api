require "rails_helper"

RSpec.describe CityValidator do
  it "normalizes city names" do
    expect(described_class.normalize("  new   york! ")).to eq("New York")
    expect(described_class.normalize("saint-louis")).to eq("Saint-Louis")
  end

  it "rejects junk syntax" do
    expect(described_class.valid_city_name_syntax?("$%^")).to be false
    expect(described_class.valid_city_name_syntax?("A")).to be false
    expect(described_class.valid_city_name_syntax?("LA")).to be true
  end
end
