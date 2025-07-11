# frozen_string_literal: true

require_relative "services"

module CRMS
  # Encapsulates the rights_current (eventually rights_history?) for an HT item
  class Rights
    # Could be populated with a single call to the Rights API
    ATTRIBUTES_BY_NAME = {}
    ATTRIBUTES_BY_ID = {}
    REASONS_BY_NAME = {}
    REASONS_BY_ID = {}

    def self.lookup_attribute(attribute)
      if ATTRIBUTES_BY_NAME.empty? || ATTRIBUTES_BY_ID.empty? || REASONS_BY_NAME.empty? || REASONS_BY_ID.empty?
        update_attribute_reason_mapping!
      end
      case attribute
      when String, Symbol
        ATTRIBUTES_BY_NAME[attribute.to_sym]
      when Integer
        ATTRIBUTES_BY_ID[attribute]
      end
    end

    def self.lookup_reason(reason)
      if ATTRIBUTES_BY_NAME.empty? || ATTRIBUTES_BY_ID.empty? || REASONS_BY_NAME.empty? || REASONS_BY_ID.empty?
        update_attribute_reason_mapping!
      end
      case reason
      when String, Symbol
        REASONS_BY_NAME[reason.to_sym]
      when Integer
        REASONS_BY_ID[reason]
      end
    end

    # Populates the lookup tables for the ubiquitous id <-> name lookups
    # for attributes and reasons.
    # Periodic refresh is highly unlikely to be needed
    def self.update_attribute_reason_mapping!
      Services[:ht_database].connection[:attributes].each do |row|
        transform_attribute_reason_keys! row
        ATTRIBUTES_BY_NAME[row[:name].to_sym] = row
        ATTRIBUTES_BY_ID[row[:id]] = row
      end
      ATTRIBUTES_BY_NAME.freeze
      ATTRIBUTES_BY_ID.freeze
      Services[:ht_database].connection[:reasons].each do |row|
        transform_attribute_reason_keys! row
        REASONS_BY_NAME[row[:name].to_sym] = row
        REASONS_BY_ID[row[:id]] = row
      end
      REASONS_BY_NAME.freeze
      REASONS_BY_ID.freeze
    end

    # de-abbreviate hash keys
    def self.transform_attribute_reason_keys!(hash)
      hash.transform_keys! do |key|
        (key == :dscr) ? :description : key
      end
    end

    private_class_method :update_attribute_reason_mapping!, :transform_attribute_reason_keys!

    def initialize(htid)
      (namespace, id) = htid.split(".", 2)
      @rights_data = Services[:ht_database]
        .connection[:rights_current]
        .where(id: id, namespace: namespace)
        .first || {}
    end

    def valid?
      @rights_data.any?
    end

    # Does the least surprising thing and returns standard "attr/reason"
    # Returns nil if not valid
    def to_s
      if attribute_name && reason_name
        [attribute_name, reason_name].join "/"
      end
    end

    def attribute_name
      @attribute_name ||= if valid?
        self.class.lookup_attribute(@rights_data[:attr])[:name]
      end
    end

    def reason_name
      @reason_name ||= if valid?
        self.class.lookup_reason(@rights_data[:reason])[:name]
      end
    end

    def pd_or_pdus?
      attribute_name&.match?(/^pd/) ? true : false
    end
  end
end
