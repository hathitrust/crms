# frozen_string_literal: true

require "canister"
require "logger"

require_relative "database"

module CRMS
  Services = Canister.new

  Services.register(:logger) do
    Logger.new($stdout, level: ENV.fetch("CRMS_LOGGER_LEVEL", Logger::INFO).to_i)
  end

  Services.register(:crms_database) do
    CRMSDatabase.new.tap do |db|
      db.connection.logger = Services[:logger]
    end
  end

  Services.register(:ht_database) do
    HTDatabase.new.tap do |db|
      db.connection.logger = Services[:logger]
    end
  end
end
