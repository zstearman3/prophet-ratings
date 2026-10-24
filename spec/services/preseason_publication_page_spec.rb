# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PreseasonPublicationPage do
  let(:season) { create(:season) }
  let(:model) { RatingsConfigVersion.publish! }
  let(:admin) { create(:user, :admin) }

  before { create(:team_season, season:) }

  it 'projects legacy reports inside SQL without returning raw evidence or replay operands' do
    report = PreseasonPublicationPreview.new(season, ratings_config_version: model, mode: 'initialize').call
    report['teams'].first['inputs']['reviewed_departures'] = { 'sources' => [{ 'rows' => ['raw-source-marker'] }],
                                                               'revision' => { 'id' => 42 } }
    publication = PreseasonPublication.create!(season:, reviewer: admin, ratings_config_version: model, mode: 'initialize',
                                               report:, fingerprint: report.fetch('fingerprint'))
    summary = described_class.summary(season.preseason_publications).find(publication.id)
    expect(summary.report).not_to have_key('teams')
    page = described_class.review(season.preseason_publications).find(publication.id)
    expect(page.report.to_json).not_to include('raw-source-marker')
    expect(page.report.dig('teams', 0, 'inputs', 'reviewed_departures', 'revision', 'id')).to eq(42)
    expect(page.report.dig('teams', 0, 'after')).to eq(report.dig('teams', 0, 'after'))
    expect(publication.reload.report.to_json).to include('raw-source-marker')
  end
end
