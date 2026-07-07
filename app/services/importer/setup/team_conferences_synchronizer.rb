# frozen_string_literal: true

require 'csv'

module Importer
  module Setup
    class TeamConferencesSynchronizer
      EXPECTED_HEADERS = %w[school conference_slug start_year end_year].freeze
      OPEN_ENDED_YEAR = 2_147_483_647

      class InvalidData < StandardError; end

      Result = Data.define(:created, :updated, :unchanged, :deleted)
      ParsedRow = Data.define(:number, :school, :conference_slug, :start_year, :end_year)
      References = Data.define(:teams_by_school, :conferences_by_slug, :seasons_by_year)
      ResolvedRowReferences = Data.define(:team, :conference, :start_season, :end_season)
      Counts = Data.define(:created, :updated, :unchanged)
      Row = Data.define(:number, :team, :conference, :start_season, :end_season, :start_year, :end_year) do
        def natural_key
          [team.id, start_season.id]
        end
      end

      def self.referenced_years(path:)
        new(path:).referenced_years
      end

      def initialize(path:)
        @path = path
      end

      def call
        desired_rows = validated_rows

        TeamConference.transaction do
          reconcile(desired_rows)
        end
      end

      def referenced_years
        parsed_rows, errors = parse_csv_rows
        raise InvalidData, errors.join("\n") if errors.any?

        parsed_rows.flat_map { |row| [row.start_year, row.end_year] }.compact.uniq.sort
      end

      private

      attr_reader :path

      def validated_rows
        parsed_rows, errors = parse_csv_rows
        rows = resolve_rows(parsed_rows, errors)
        validate_duplicate_natural_keys(rows, errors)
        validate_overlaps(rows, errors)
        raise InvalidData, errors.join("\n") if errors.any?

        rows
      end

      def parse_csv_rows
        contents = File.read(path)
        raise InvalidData, 'CSV must include headers and at least one data row' if contents.blank?

        table = CSV.parse(contents, headers: true)
        validate_headers!(table)

        errors = []
        rows = table.each.with_index(2).map do |csv_row, number|
          build_parsed_row(csv_row, number, errors)
        end

        [rows, errors]
      end

      def validate_headers!(table)
        raise InvalidData, 'CSV must include headers and at least one data row' if table.headers.blank? || table.empty?

        return if table.headers == EXPECTED_HEADERS

        raise InvalidData, "CSV headers must be #{EXPECTED_HEADERS.join(', ')}"
      end

      def build_parsed_row(csv_row, number, errors)
        start_year = parse_year(csv_row['start_year'], number, 'start_year', errors)
        end_year = parse_optional_year(csv_row['end_year'], number, errors)

        errors << "row #{number}: end_year must be the same as or later than start_year" if invalid_range?(start_year, end_year)

        ParsedRow.new(
          number:,
          school: csv_row['school'],
          conference_slug: csv_row['conference_slug'],
          start_year:,
          end_year:
        )
      end

      def parse_optional_year(value, number, errors)
        return nil if value.blank?

        parse_year(value, number, 'end_year', errors)
      end

      def parse_year(value, number, field, errors)
        Integer(value, 10)
      rescue ArgumentError, TypeError
        errors << "row #{number}: #{field} must be an integer"
        nil
      end

      def resolve_rows(parsed_rows, errors)
        references = references_for(parsed_rows)

        parsed_rows.filter_map do |parsed_row|
          build_row(parsed_row, references, errors)
        end
      end

      def references_for(parsed_rows)
        References.new(
          teams_by_school: Team.where(school: parsed_rows.map(&:school)).index_by(&:school),
          conferences_by_slug: Conference.where(slug: parsed_rows.map(&:conference_slug)).index_by(&:slug),
          seasons_by_year: Season.where(year: parsed_rows.flat_map { |row| [row.start_year, row.end_year] }.compact)
                                 .index_by(&:year)
        )
      end

      def build_row(parsed_row, references, errors)
        resolved = ResolvedRowReferences.new(
          team: references.teams_by_school[parsed_row.school],
          conference: references.conferences_by_slug[parsed_row.conference_slug],
          start_season: references.seasons_by_year[parsed_row.start_year],
          end_season: parsed_row.end_year ? references.seasons_by_year[parsed_row.end_year] : nil
        )

        add_missing_reference_errors(parsed_row, resolved, errors)
        return unless resolved.team && resolved.conference && resolved.start_season &&
                      (parsed_row.end_year.blank? || resolved.end_season)

        Row.new(
          number: parsed_row.number,
          team: resolved.team,
          conference: resolved.conference,
          start_season: resolved.start_season,
          end_season: resolved.end_season,
          start_year: parsed_row.start_year,
          end_year: parsed_row.end_year
        )
      end

      def add_missing_reference_errors(parsed_row, resolved, errors)
        errors << "row #{parsed_row.number}: team not found for school #{parsed_row.school}" unless resolved.team
        errors << "row #{parsed_row.number}: conference not found for slug #{parsed_row.conference_slug}" unless resolved.conference
        if parsed_row.start_year && !resolved.start_season
          errors << "row #{parsed_row.number}: start season not found for year #{parsed_row.start_year}"
        end
        return if parsed_row.end_year.blank? || resolved.end_season

        errors << "row #{parsed_row.number}: end season not found for year #{parsed_row.end_year}"
      end

      def invalid_range?(start_year, end_year)
        start_year && end_year && end_year < start_year
      end

      def validate_duplicate_natural_keys(rows, errors)
        first_row_by_key = {}

        rows.each do |row|
          previous_row = first_row_by_key[row.natural_key]
          if previous_row
            errors << "row #{row.number}: duplicate team and start_year (matches row #{previous_row.number})"
          else
            first_row_by_key[row.natural_key] = row
          end
        end
      end

      def validate_overlaps(rows, errors)
        rows.group_by(&:team).each_value do |team_rows|
          team_rows.sort_by(&:start_year).each_cons(2) do |previous_row, row|
            next if row.start_year > (previous_row.end_year || OPEN_ENDED_YEAR)

            errors << "row #{row.number}: conference membership overlaps row #{previous_row.number}"
          end
        end
      end

      def reconcile(desired_rows)
        existing_by_key = TeamConference.all.index_by { |membership| [membership.team_id, membership.start_season_id] }
        deleted = delete_stale_memberships(existing_by_key, desired_rows)
        counts = apply_desired_rows(existing_by_key, desired_rows)

        Result.new(created: counts.created, updated: counts.updated, unchanged: counts.unchanged, deleted:)
      end

      def delete_stale_memberships(existing_by_key, desired_rows)
        stale_ids = existing_by_key.except(*desired_rows.map(&:natural_key)).values.map(&:id)
        return 0 if stale_ids.empty?

        TeamConference.where(id: stale_ids).delete_all
      end

      def apply_desired_rows(existing_by_key, desired_rows)
        desired_rows.sort_by { |row| [row.team.id, row.start_year] }.reduce(Counts.new(0, 0, 0)) do |counts, row|
          apply_desired_row(row, existing_by_key, counts)
        end
      end

      def apply_desired_row(row, existing_by_key, counts)
        membership = existing_by_key[row.natural_key] || TeamConference.new(
          team: row.team,
          start_season: row.start_season
        )

        membership.assign_attributes(
          conference: row.conference,
          end_season: row.end_season
        )

        save_membership(membership, counts)
      end

      def save_membership(membership, counts)
        if membership.new_record?
          membership.save!
          counts.with(created: counts.created + 1)
        elsif membership.changed?
          membership.save!
          counts.with(updated: counts.updated + 1)
        else
          counts.with(unchanged: counts.unchanged + 1)
        end
      end
    end
  end
end
