# frozen_string_literal: true

require Rails.root.join('lib/rails_admin/config/actions/new_team_conference')

# rubocop:disable Metrics/BlockLength
RailsAdmin.config do |config|
  config.asset_source = :sprockets

  ### Popular gems integration

  config.authenticate_with do
    warden.authenticate!(scope: :user)
    redirect_to main_app.root_path unless current_user.admin?
  end
  config.current_user_method(&:current_user)

  config.model 'Team' do
    object_label_method :school

    show do
      fields :school, :nickname, :short_name, :slug, :url, :location, :home_venue,
             :primary_color, :the_odds_api_team_id, :team_aliases, :team_conferences
    end
  end

  config.model 'Conference' do
    show do
      fields :name, :abbreviation, :slug, :team_conferences
    end
  end

  config.model 'TeamConference' do # rubocop:disable Metrics/BlockLength
    object_label_method :admin_label

    list do
      items_per_page 50
      fields :team, :conference, :start_season, :end_season
    end

    show do
      fields :team, :conference, :start_season, :end_season
    end

    create do
      field :team do
        inline_add false
        inline_edit false
      end
      field :conference do
        inline_add false
        inline_edit false
      end
      field :start_season do
        inline_add false
        inline_edit false
      end
      field :end_season do
        inline_add false
        inline_edit false
      end
    end

    edit do
      field :team do
        inline_add false
        inline_edit false
      end
      field :conference do
        inline_add false
        inline_edit false
      end
      field :start_season do
        inline_add false
        inline_edit false
      end
      field :end_season do
        inline_add false
        inline_edit false
      end
    end
  end

  config.model 'CoachingChange' do
    list do
      fields :effective_year, :team, :destination_school, :coach_name, :status, :previous_team, :previous_year, :previous_role,
             :full_season_head_coach
    end
    show do
      fields :effective_year, :team, :destination_school, :coach_name, :status, :previous_team, :previous_school,
             :previous_year, :previous_role, :full_season_head_coach
    end
    edit do
      field :effective_year
      field :team do
        inline_add false
        inline_edit false
      end
      field :destination_school
      field :coach_name
      field :previous_team do
        inline_add false
        inline_edit false
      end
      field :previous_school
      field :previous_year
      field :previous_role, :enum do
        enum CoachingChange::PREVIOUS_ROLES
      end
      field :full_season_head_coach do
        help 'Only assert a verified full season as head coach at the resolved previous team/year.'
      end
      field :status, :enum do
        enum CoachingChange::STATUSES
        help 'Confirm or reject manually after reviewing the coaching facts.'
      end
      field :reconfirm, :boolean do
        help 'Check explicitly when correcting facts on a confirmed record; otherwise return it to pending.'
      end
    end
  end

  config.model 'CoachingReview' do
    list do
      fields :year, :ready, :updated_at
    end
    show do
      fields :year, :ready, :updated_at
    end
    edit do
      field :year
      field :ready do
        help 'Mark ready only after confirming or rejecting every pending candidate. An empty year is allowed.'
      end
    end
  end

  ## == CancanCan ==
  # config.authorize_with :cancancan

  ## == Pundit ==
  # config.authorize_with :pundit

  ## == PaperTrail ==
  # config.audit_with :paper_trail, 'User', 'PaperTrail::Version' # PaperTrail >= 3.0.0

  ### More at https://github.com/railsadminteam/rails_admin/wiki/Base-configuration

  ## == Gravatar integration ==
  ## To disable Gravatar integration in Navigation Bar set to false
  # config.show_gravatar = true

  config.actions do
    dashboard do
      statistics false
    end
    index # mandatory
    new do
      except ['TeamConference']
    end
    new_team_conference
    export
    bulk_delete do
      except ['TeamConference']
    end
    show
    edit
    delete
    show_in_app

    ## With an audit adapter, you can add:
    # history_index
    # history_show
  end
end
# rubocop:enable Metrics/BlockLength
