# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Importer::Setup::TeamConferencesSynchronizer do
  let!(:alpha) { create(:team, school: 'Alpha') }
  let!(:beta) { create(:team, school: 'Beta') }
  let!(:old_conference) { create(:conference, name: 'Old Conference', slug: 'old') }
  let!(:new_conference) { create(:conference, name: 'New Conference', slug: 'new') }
  let!(:season2025) { create_season(2025) }
  let!(:season2026) { create_season(2026) }
  let(:season2027) { create_season(2027) }

  def create_season(year)
    create(
      :season,
      year:,
      name: "#{year - 1}-#{year.to_s.last(2)}",
      start_date: Date.new(year - 1, 11, 1),
      end_date: Date.new(year, 4, 10)
    )
  end

  def csv(*rows)
    "school,conference_slug,start_year,end_year\n#{rows.join("\n")}\n"
  end

  def synchronize(contents)
    Tempfile.create(['team-conferences', '.csv']) do |file|
      file.write(contents)
      file.flush
      return described_class.new(path: file.path).call
    end
  end

  def referenced_years(contents)
    Tempfile.create(['team-conferences', '.csv']) do |file|
      file.write(contents)
      file.flush
      return described_class.referenced_years(path: file.path)
    end
  end

  it 'creates a missing natural key' do
    result = synchronize(csv('Alpha,old,2025,'))

    expect(result.to_h).to eq(created: 1, updated: 0, unchanged: 0, deleted: 0)
    expect(TeamConference.find_by!(team: alpha, start_season: season2025)).to have_attributes(
      conference: old_conference,
      end_season: nil
    )
  end

  it 'updates a matching natural key while preserving the existing ID' do
    membership = create(:team_conference, team: alpha, conference: old_conference, start_season: season2025)

    result = synchronize(csv('Alpha,new,2025,2026'))

    expect(result.to_h).to eq(created: 0, updated: 1, unchanged: 0, deleted: 0)
    expect(membership.reload).to have_attributes(
      id: membership.id,
      conference: new_conference,
      end_season: season2026
    )
  end

  it 'leaves an identical row untouched' do
    membership = create(
      :team_conference,
      team: alpha,
      conference: old_conference,
      start_season: season2025,
      end_season: season2026
    )
    updated_at = membership.updated_at

    result = synchronize(csv('Alpha,old,2025,2026'))

    expect(result.to_h).to eq(created: 0, updated: 0, unchanged: 1, deleted: 0)
    expect(membership.reload.updated_at).to eq(updated_at)
  end

  it 'deletes stale admin-only natural keys absent from the CSV' do
    stale = create(:team_conference, team: alpha, conference: old_conference, start_season: season2025)

    result = synchronize(csv('Beta,new,2025,'))

    expect(result.to_h).to eq(created: 1, updated: 0, unchanged: 0, deleted: 1)
    expect(TeamConference.exists?(stale.id)).to be(false)
    expect(TeamConference.find_by!(team: beta, start_season: season2025)).to have_attributes(
      conference: new_conference,
      end_season: nil
    )
  end

  it 'overwrites an admin row with the same natural key' do
    membership = create(:team_conference, team: alpha, conference: old_conference, start_season: season2025)

    result = synchronize(csv('Alpha,new,2025,'))

    expect(result.to_h).to eq(created: 0, updated: 1, unchanged: 0, deleted: 0)
    expect(membership.reload.conference).to eq(new_conference)
  end

  it 'returns all referenced years with strict integer parsing' do
    expect(referenced_years(csv('Alpha,old,2025,2026', 'Beta,new,2027,'))).to eq([2025, 2026, 2027])

    expect do
      referenced_years(csv('Alpha,old,2025x,'))
    end.to raise_error(described_class::InvalidData, /row 2: start_year must be an integer/)
  end

  it 'rejects empty files and wrong headers' do
    expect do
      synchronize('')
    end.to raise_error(described_class::InvalidData, 'CSV must include headers and at least one data row')

    expect do
      synchronize("school,start_year,conference_slug,end_year\nAlpha,2025,old,\n")
    end.to raise_error(described_class::InvalidData, /CSV headers must be school, conference_slug, start_year, end_year/)
  end

  it 'wraps malformed CSV parser errors as invalid data' do
    expect do
      synchronize("school,conference_slug,start_year,end_year\n\"Alpha,old,2025,\n")
    end.to raise_error(described_class::InvalidData, /CSV is malformed:/)
  end

  it 'rejects invalid rows before writing' do
    season2027

    expect do
      synchronize(
        csv(
          'Missing,old,2025,',
          'Alpha,missing,2025,',
          'Alpha,old,2025x,',
          'Alpha,old,2027,2026'
        )
      )
    end.to raise_error(described_class::InvalidData) { |error|
      expect(error.message).to include('row 2: team not found for school Missing')
      expect(error.message).to include('row 3: conference not found for slug missing')
      expect(error.message).to include('row 4: start_year must be an integer')
      expect(error.message).to include('row 5: end_year must be the same as or later than start_year')
    }
  end

  it 'preserves existing rows when validation fails' do
    existing = create(:team_conference, team: alpha, conference: old_conference, start_season: season2025)

    expect do
      synchronize(csv('Missing,old,2025,'))
    end.to raise_error(described_class::InvalidData, /row 2: team not found/)

    expect(TeamConference.pluck(:id)).to eq([existing.id])
    expect(existing.reload.conference).to eq(old_conference)
  end

  it 'rejects duplicate natural keys and inclusive overlaps' do
    season2027

    expect do
      synchronize(csv('Alpha,old,2025,2026', 'Alpha,new,2025,2027'))
    end.to raise_error(described_class::InvalidData, /row 3: duplicate team and start_year/)

    expect do
      synchronize(csv('Alpha,old,2025,2026', 'Alpha,new,2026,2027'))
    end.to raise_error(described_class::InvalidData, /row 3: conference membership overlaps row 2/)
  end

  it 'rolls back deletions when a write fails' do
    stale = create(:team_conference, team: alpha, conference: old_conference, start_season: season2025)
    allow(TeamConference).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap do |membership|
        allow(membership).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(membership))
      end
    end

    expect do
      synchronize(csv('Beta,new,2025,'))
    end.to raise_error(ActiveRecord::RecordInvalid)

    expect(TeamConference.exists?(stale.id)).to be(true)
    expect(TeamConference.where(team: beta)).to be_empty
  end
end
