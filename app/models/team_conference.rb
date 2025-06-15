# frozen_string_literal: true

# == Schema Information
#
# Table name: team_conferences
#
#  id              :bigint           not null, primary key
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  conference_id   :bigint           not null
#  end_season_id   :bigint
#  start_season_id :bigint           not null
#  team_id         :bigint           not null
#
# Indexes
#
#  index_team_conferences_on_conference_id          (conference_id)
#  index_team_conferences_on_end_season_id          (end_season_id)
#  index_team_conferences_on_start_season_id        (start_season_id)
#  index_team_conferences_on_team_and_season_range  (team_id,start_season_id,end_season_id) UNIQUE
#  index_team_conferences_on_team_id                (team_id)
#
# Foreign Keys
#
#  fk_rails_...  (conference_id => conferences.id)
#  fk_rails_...  (end_season_id => seasons.id)
#  fk_rails_...  (start_season_id => seasons.id)
#  fk_rails_...  (team_id => teams.id)
#
class TeamConference < ApplicationRecord
  belongs_to :team
  belongs_to :conference

  belongs_to :start_season, class_name: 'Season'
  belongs_to :end_season, class_name: 'Season', optional: true
end
