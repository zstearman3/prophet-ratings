# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Reconciliation::Shadow do
  include_context 'with synthetic reconciliation'

  before do
    teams.each_with_index do |team, index|
      stats = observation.fetch(index.zero? ? 'home' : 'away').fetch('stats').transform_values { |stat| stat['value'] }
      create(:team_game, game:, team:, team_season: team.team_seasons.find_by!(season:), home: index.zero?, **stats)
    end
  end

  def mismatch(field)
    report['shadow']['mismatches'].find { |row| row['field'] == field }
  end

  it 'counts fields independently and accepts zero as a real observed value' do
    expect(report['shadow']).to include('games_compared' => 1, 'fields_compared' => 41, 'mismatches' => [])
  end

  it 'retains unknown missing statistics without inventing zero or assigning blame' do
    observation['home']['stats']['blocks'].merge!('value' => nil, 'reason' => 'source_null')
    expect(mismatch('home.blocks')).to include('source' => nil, 'local' => 0, 'category' => 'unresolved_evidence')
  end

  it 'reports uncertified rebound and turnover semantic differences without subtracting team totals' do
    game.home_team_game.update!(turnovers: 8)
    expect(mismatch('home.turnovers')).to include('source' => 10, 'local' => 8, 'category' => 'semantics')
  end

  it 'identifies invalid provider values from retained normalization evidence' do
    observation['home']['stats']['blocks'].merge!('value' => nil, 'reason' => 'invalid_nonnegative_integer', 'raw' => -1)
    expect(mismatch('home.blocks')['category']).to eq('likely_provider_defect')
  end

  it 'identifies a local defect only with independently inconsistent local components' do
    game.home_team_game.update!(rebounds: 99)
    expect(mismatch('home.rebounds')).to include('category' => 'likely_local_defect', 'source' => 30, 'local' => 99)
    expect(mismatch('home.rebounds')['evidence']).to include('local_team_game_id' => game.home_team_game.id)
  end

  it 'leaves an unexplained shooting discrepancy unresolved' do
    game.home_team_game.update!(assists: 99)
    expect(mismatch('home.assists')['category']).to eq('unresolved_evidence')
  end

  it 'aligns reversed neutral participants, scores and stats explicitly' do
    home = observation['home']
    observation['home'] = observation['away']
    observation['away'] = home
    observation['venue']['certainty'] = 'neutral'
    game.update!(venue_type: 'neutral', neutral: true, venue_confidence: 'confirmed')
    expect(report['shadow']['mismatches']).to eq([])
    expect(report['games'].first['candidates'].first['reversed']).to be(true)
  end

  it 'normalizes the local cancellation spelling without creating a status mismatch' do
    game.update!(status: 'canceled')
    observation['status'] = 'cancelled'
    expect(mismatch('status')).to be_nil
  end

  it 'retains actual invalid normalized score evidence and classifies it as a provider defect' do
    fixture['games'].first['homePoints'] = -1
    entry = ->(raw) { { 'raw' => raw, 'provenance' => { 'id' => 'synthetic-invalid-score' } } }
    replay['observations'] = [Ingestion::Cbbd::Normalizer.new(entry.call(fixture['games'].first), fixture['boxes'].map(&entry)).call]
    result = mismatch('home.score')
    expect(result).to include('source' => nil, 'local' => 65, 'category' => 'likely_provider_defect')
    expect(result['evidence']['source_stat']).to include('raw' => -1, 'reason' => 'invalid_nonnegative_integer')
  end

  %w[rebounds turnovers].each do |name|
    it "leaves missing source #{name} unresolved instead of asserting a semantics difference" do
      observation['home']['stats'][name].merge!('value' => nil, 'availability' => 'unknown', 'reason' => 'source_null')
      expect(mismatch("home.#{name}")['category']).to eq('unresolved_evidence')
    end

    it "leaves missing local #{name} unresolved instead of asserting a semantics difference" do
      game.home_team_game.update!(name => nil)
      expect(mismatch("home.#{name}")['category']).to eq('unresolved_evidence')
    end
  end

  it 'retains independently demonstrated local defects when the corresponding source total is missing' do
    game.home_team_game.update!(rebounds: 99)
    observation['home']['stats']['rebounds'].merge!('value' => nil, 'reason' => 'source_null')
    expect(mismatch('home.rebounds')['category']).to eq('likely_local_defect')
  end

  it 'uses only applicable field-specific real normalization failures as provider-defect evidence' do
    fixture['boxes'].each { |box| box['gameMinutes'] = 41 }
    entry = ->(raw) { { 'raw' => raw, 'provenance' => { 'id' => 'synthetic-invalid-minutes' } } }
    invalid = Ingestion::Cbbd::Normalizer.new(entry.call(fixture['games'].first), fixture['boxes'].map(&entry)).call
    expect(invalid['reasons']).to include('minutes: invalid regulation/overtime duration')
    replay['observations'] = [invalid]
    game.home_team_game.update!(assists: 99)
    result = mismatch('home.minutes')
    expect(result).to include('source' => 205, 'local' => 200, 'category' => 'likely_provider_defect')
    expect(result['evidence']['source_validation_reasons']).to eq(['minutes: invalid regulation/overtime duration'])
    expect(mismatch('home.assists')['category']).to eq('unresolved_evidence')
  end

  it 'does not classify nonfinal scheduled evidence as a provider defect' do
    observation['status'] = 'scheduled'
    observation['numeric_valid'] = false
    observation['reasons'] = ['source not confirmed final with unequal valid scores']
    game.home_team_game.update!(assists: 99)
    expect(mismatch('home.assists')['category']).to eq('unresolved_evidence')
    expect(mismatch('status')['category']).to eq('unresolved_evidence')
  end
end
