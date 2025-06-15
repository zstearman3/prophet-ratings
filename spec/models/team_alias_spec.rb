# frozen_string_literal: true

# == Schema Information
#
# Table name: team_aliases
#
#  id         :bigint           not null, primary key
#  source     :string
#  value      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  team_id    :bigint           not null
#
# Indexes
#
#  index_team_aliases_on_team_id           (team_id)
#  index_team_aliases_on_value_and_source  (value,source) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (team_id => teams.id)
#
require 'rails_helper'

RSpec.describe TeamAlias do
  pending "add some examples to (or delete) #{__FILE__}"
end
