# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'tempfile'

RSpec.describe SeasonParticipationReview do
  let(:season) { create(:season) }
  let(:team) { create(:team) }

  around do |example|
    original_rake = Rake.application
    original_env = ENV.to_h
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    load Rails.root.join('lib/tasks/season_participation.rake')
    example.run
  ensure
    Rake.application = original_rake
    ENV.replace(original_env)
  end

  def run_review(document)
    run_review_content(JSON.generate(document))
  end

  def run_review_content(content)
    Tempfile.create(['participation', '.json']) do |file|
      file.write(content)
      file.flush
      ENV['YEAR'] = season.year.to_s
      ENV['REVIEW_PATH'] = file.path
      Rake::Task['season:review_participation'].invoke
    end
  end

  def document
    {
      'evidence' => 'Test roster', 'reviewed_by' => 'Test operator',
      'dates' => { 'start_date' => season.start_date.iso8601, 'end_date' => season.end_date.iso8601, 'evidence' => 'Test dates' },
      'teams' => [{ 'team_id' => team.id, 'status' => 'included', 'reason' => 'Test participant' }],
      'unresolved_identities' => []
    }
  end

  it 'saves a complete review without publishing any outputs' do
    create(:team_season, team:, season:)
    create(:team_alias, team:, value: team.school)
    expect { run_review(document) }.to output(/Saved participation review.*coverage passed/m).to_stdout
    expect(season.reload.participation_review).to eq(document)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'saves an incomplete review and reports missing included rows and aliases with a nonzero exit' do
    payload = document
    expect do
      expect { run_review(payload) }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/season:prepare.*#{team.id}.*aliases.*#{team.id}/).to_stderr.and output(/Saved participation review/).to_stdout
    expect(season.reload.participation_review).to eq(payload)
  end

  it 'reports malformed JSON with a nonzero exit without changing the season' do
    original = season.attributes
    expect do
      expect { run_review_content('{broken') }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(/unexpected|expected/i).to_stderr
    expect(season.reload.attributes).to eq(original)
    expect(TeamRatingSnapshot.count).to eq(0)
  end

  it 'reports a missing review file with a nonzero exit without changing the season' do
    original = season.attributes
    Tempfile.create(['missing-participation', '.json']) do |file|
      ENV['YEAR'] = season.year.to_s
      ENV['REVIEW_PATH'] = file.path
      File.unlink(file.path)
      expect do
        expect { Rake::Task['season:review_participation'].invoke }
          .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end.to output(/No such file/).to_stderr
    end
    expect(season.reload.attributes).to eq(original)
    expect(TeamRatingSnapshot.count).to eq(0)
  end
end
