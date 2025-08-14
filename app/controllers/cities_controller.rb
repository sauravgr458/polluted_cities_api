class CitiesController < ApplicationController
  def index
    result = GetMostPollutedCities.call

    render json: {
      generated_at: Time.now.utc.iso8601,
      count: result.size,
      data: result
    }
  rescue => e
    Rails.logger.error("[Cities#index] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
    render json: { error: "internal_error" }, status: :internal_server_error
  end
end
