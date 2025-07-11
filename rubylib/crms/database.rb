# frozen_string_literal: true

require "sequel"

module CRMS
  # Backend for connection to MySQL database for production information about
  # holdings and institutions
  class Database
    attr_reader :connection

    def initialize(env_key)
      @connection = self.class.connection(env_key)
      # Check once every few seconds that we're actually connected and reconnect if necessary
      @connection.extension(:connection_validator)
      @connection.pool.connection_validation_timeout = 5
    end

    # Connection connects to the database using the connection information
    # specified by environment variables MARIADB_ENV_KEY_USERNAME, _PASSWORD,
    # _HOST, and _DATABASE.
    def self.connection(env_key)
      Sequel.connect(
        adapter: :mysql2,
        user: ENV["MARIADB_#{env_key}_USERNAME"],
        password: ENV["MARIADB_#{env_key}_PASSWORD"],
        host: ENV["MARIADB_#{env_key}_HOST"],
        database: ENV["MARIADB_#{env_key}_DATABASE"],
        encoding: "utf8mb4"
      )
    end
  end

  class CRMSDatabase < Database
    def initialize
      super("CRMS_RW")
    end
  end

  class HTDatabase < Database
    def initialize
      super("HT_RO")
    end
  end
end
