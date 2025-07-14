# frozen_string_literal: true

# Typically run a week or so into January. Reports on CRMS Core determinations with a
# now-expired renewal date for the current year that are still closed.
# 
# This is a postmortem report intended to be run in January after new rights
# from the PDD rollover have taken effect. There will generally be no reason to specify
# `PDD_RENEWAL_DATE_YEAR`; it is included here for debugging and preview purposes.
#
# The renDate fields that qualify are based on a current year minus 68 years scheme
# (see the magic constant EXPECTED_RENEWAL_EXPIRATION_YEARS). I will not attempt to derive
# that here except to note it relates to renewal terms in some not-particularly-obvious way;
# it is not an off-by-two derivation from 70 years but something more subtle. See Kristina
# for more information if this needs to be revisited.

require "date"
require "dotenv"
require "json"
require "set"

require "crms"

Dotenv.load
ENV["CRMS_LOGGER_LEVEL"] = Logger::WARN.to_s

EXPECTED_RENEWAL_SUNSET = 68 # years

year = ENV.fetch("PDD_RENEWAL_DATE_YEAR", Date.today.year)
target_year = year - EXPECTED_RENEWAL_SUNSET
target_year_digits = target_year.to_s[-2, 2] # "1957" => "57"

CRMS::Services.logger.info "checking renewals for #{target_year}, renDate pattern D[D]Mmm#{target_year_digits}"

# Emit header
columns = ["HTID", "renDate", "renNum", "Stanford ODAT", "Current Rights"]
puts columns.join "\t"

# Avoid duplicate entries per HTID
seen_htids = Set.new

CRMS::Services[:crms_database]
  .connection[:historicalreviews]
  .join(:exportdata, gid: :gid)
  .join(:projects, id: :project)
  .join(:reviewdata, id: Sequel[:historicalreviews][:data])
  .exclude(Sequel[:historicalreviews][:data] => nil)
  .where(Sequel[:historicalreviews][:validated] => 1)
  .where(Sequel[:projects][:name] => "Core")
  # FIXME: should look for renNum instead, and derive the other data from the
  # stanford table like we do for ODAT
  .where(Sequel.like(Sequel[:reviewdata][:data], "%renDate%"))
  .order(Sequel.asc(Sequel[:historicalreviews][:id]))
  .select(Sequel[:historicalreviews][:id], Sequel[:reviewdata][:data])
  .each do |row|
  htid = row[:id]
  next if seen_htids.include? htid

  json = JSON.parse row[:data]
  ren_date = json.fetch("renDate", "")&.strip || ""
  ren_num = json.fetch("renNum", "")&.strip || ""

  # Narrow results down to year of interest.
  # renDate as represented in Catalog of Copyright Entries is of the form D[D]mmmYY
  # e.g., "4Nov52" or "31Mar59"
  if ren_date.match?(/^\d{1,2}\D{3}\d{2}$/) && ren_date[-2, 2] == target_year_digits
    rights = CRMS::Rights.new(htid)
    unless rights.valid?
      CRMS::Services.logger.warn "could not get rights for #{htid}"
      next
    end

    if !rights.pd_or_pdus?
      odat = ''
      if !ren_num.empty?
        # TODO extract a stanford class
        odat = CRMS::Services[:crms_database]
          .connection[:stanford]
          .where(ID: ren_num)
          .select(:ODAT)
          .all
          .fetch(0, {})
          .fetch(:ODAT, "")
      end
      puts [htid, ren_date, ren_num, odat, rights.to_s].join("\t")
      seen_htids << htid
    end
  end
end
