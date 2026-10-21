# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ingestion::Cbbd::Normalizer do
  let(:fixture) { JSON.parse(Rails.root.join('spec/fixtures/ingestion/cbbd/final.json').read) }
  let(:game) { fixture['games'].first }
  let(:boxes) { fixture['boxes'] }

  def entry(raw, index)
    { 'raw' => raw, 'provenance' => { 'id' => "synthetic-#{index}", 'sha256' => 'synthetic', 'row_index' => index } }
  end

  def normalized
    described_class.new(entry(game, 0), boxes.each_with_index.map { |box, index| entry(box, index + 1) }).call
  end

  it 'normalizes overtime once using independent period evidence' do
    boxes.each { |box| box['gameMinutes'] = 45 }
    game.merge!('homePeriodPoints' => [25, 25, 15], 'awayPeriodPoints' => [25, 25, 14])
    expect(normalized['numeric_valid']).to be(true)
    expect(normalized['home']['stats']['minutes']['value']).to eq(225)
  end

  it 'rejects disagreement between period evidence and side duration' do
    boxes.first['gameMinutes'] = 45
    expect(normalized['reasons']).to include('side minutes disagree', 'home period duration disagreement')
    expect(normalized['numeric_valid']).to be(false)
  end

  { 'scheduled' => 'scheduled', 'in_progress' => 'live', 'final' => 'final', 'postponed' => 'postponed',
    'cancelled' => 'cancelled', 'canceled' => 'cancelled', 'suspended' => 'unknown', nil => 'unknown' }.each do |source, canonical|
    it "maps source status #{source.inspect} without guessing completion" do
      game['status'] = source
      expect(normalized['status']).to eq(canonical)
      expect(normalized['source_completed']).to eq(source == 'final')
    end
  end

  it 'retains a malformed final claim without source confirmation' do
    game['homePoints'] = game['awayPoints']
    expect(normalized).to include('status' => 'final', 'source_completed' => false, 'numeric_valid' => false)
  end

  it 'refuses contradictory box status even alongside a literal final schedule' do
    boxes.first['status'] = 'in_progress'
    expect(normalized['source_completed']).to be(false)
    expect(normalized['conflicts']).to include('box metadata conflict: status')
    expect(normalized['status']).to eq('unknown')
  end

  it 'retains missing side instead of using opponent totals to fill it' do
    boxes.pop
    expect(normalized['away']['stats']['points']).to include('value' => nil, 'reason' => 'absent')
    expect(normalized['numeric_valid']).to be(false)
  end

  it 'allows absent mirrored fields without adding completeness requirements' do
    boxes.each { |box| box.delete('opponentStats') }
    expect(normalized['numeric_valid']).to be(true)
  end

  [-99, 1.5, true].each do |invalid|
    it "rejects supplied invalid mirrored assists #{invalid.inspect}" do
      boxes.first['opponentStats']['assists'] = invalid
      observation = normalized
      expect(observation['numeric_valid']).to be(false)
      expect(observation['conflicts']).to include('mirror conflict: assists (synthetic-1, synthetic-2)')
    end
  end

  [nil, ' '].each do |missing|
    it "allows unavailable mirrored assists #{missing.inspect}" do
      boxes.first['opponentStats']['assists'] = missing
      expect(normalized['numeric_valid']).to be(true)
    end
  end

  it 'rejects misorientation, opponent, venue and date disagreements' do
    boxes.first.merge!('isHome' => false, 'opponentId' => 30, 'neutralSite' => true, 'startDate' => '2025-11-02T23:00:00Z')
    expect(normalized['conflicts']).to include('box metadata conflict: isHome', 'box metadata conflict: opponentId',
                                               'box metadata conflict: neutralSite', 'box metadata conflict: startDate')
  end

  it 'retains neutral certainty only from literal true' do
    game['neutralSite'] = true
    boxes.each { |box| box['neutralSite'] = true }
    expect(normalized['venue']['certainty']).to eq('neutral')
  end

  it 'refuses exact instants without timezone and retains raw timestamp' do
    game['startDate'] = '2025-11-01T23:00:00'
    expect(normalized).to include('start_time' => nil, 'schedule_date' => nil, 'time_precision' => 'unknown',
                                  'raw_start_time' => '2025-11-01T23:00:00')
  end

  it 'validates all 18 canonical fields with consistent units and paths' do
    stats = normalized['home']['stats']
    expect(stats.keys.map(&:to_sym)).to match_array(Importer::GamesImporter::TEAM_STAT_KEYS)
    expect(stats.values).to all(include('availability' => 'observed', 'reason' => nil))
    expect(stats['minutes']).to include('units' => 'summed_player_minutes', 'source_path' => 'gameMinutes')
  end

  it 'rejects shooting and rebound component disagreements with actionable field reasons' do
    boxes.first['teamStats']['fieldGoals']['made'] = 56
    boxes.first['teamStats']['rebounds']['total'] = 31
    expect(normalized['numeric_valid']).to be(false)
    expect(normalized['reasons']).to include('field_goals: made exceeds attempts',
                                             'field_goals_made: component mismatch', 'rebounds: component mismatch')
  end

  it 'rejects nonpositive independently calculated possessions' do
    boxes.first['teamStats']['rebounds'].merge!('offensive' => 100, 'defensive' => 0, 'total' => 100)
    expect(normalized['reasons']).to include('possessions must be positive')
  end
end
