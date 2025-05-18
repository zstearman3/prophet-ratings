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
require 'rails_helper'

RSpec.describe TeamConference, type: :model do
  pending "add some examples to (or delete) #{__FILE__}"
end
