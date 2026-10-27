# frozen_string_literal: true

class CreateDepartureValidations < ActiveRecord::Migration[8.1]
  INPUT_TABLES = %w[departure_batches departure_acquisitions seasons teams team_aliases team_external_identities
                    team_seasons team_offseason_profiles offseason_input_revisions].freeze
  CAPTURE_TABLES = %w[departure_source_captures departure_capture_observations].freeze

  GENERATION_FUNCTION_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION departure_dependency_changed() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      INSERT INTO departure_dependency_generations (id, generation) VALUES (1, 1)
      ON CONFLICT (id) DO UPDATE SET generation = departure_dependency_generations.generation + 1;
      RETURN NULL;
    END $$;
  SQL

  CERTIFICATE_TRIGGERS_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION departure_certificate_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'Verified departure certificate artifacts are immutable';
    END $$;
    CREATE TRIGGER departure_approval_immutable BEFORE UPDATE OR DELETE ON departure_approvals
      FOR EACH ROW EXECUTE FUNCTION departure_certificate_immutable();
    CREATE FUNCTION departure_proposal_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP <> 'INSERT' THEN
        RAISE EXCEPTION 'Departure proposal ownership and content are immutable';
      END IF;
      IF EXISTS (SELECT 1 FROM departure_validations WHERE id IN (NEW.departure_validation_id, OLD.departure_validation_id)
        AND (generation IS NOT NULL OR status <> 'running')) THEN
        RAISE EXCEPTION 'Verified departure proposals are immutable';
      END IF;
      IF NOT EXISTS (SELECT 1 FROM departure_validations v
        JOIN departure_batches b ON b.id = v.departure_batch_id
        JOIN team_seasons m ON m.season_id = b.season_id AND m.team_id = NEW.team_id
        WHERE v.id = NEW.departure_validation_id) THEN
        RAISE EXCEPTION 'Departure proposal requires a target season member';
      END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER departure_proposal_immutable BEFORE INSERT OR UPDATE OR DELETE ON departure_proposals
      FOR EACH ROW EXECUTE FUNCTION departure_proposal_immutable();
    CREATE FUNCTION departure_validation_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'DELETE' THEN
        IF OLD.generation IS NOT NULL THEN
          RAISE EXCEPTION 'Verified departure certificate is immutable';
        END IF;
        RETURN OLD;
      END IF;
      IF (NEW.departure_batch_id, NEW.departure_acquisition_id, NEW.validator_version) IS DISTINCT FROM
         (OLD.departure_batch_id, OLD.departure_acquisition_id, OLD.validator_version) THEN
        RAISE EXCEPTION 'Departure validation identity is immutable';
      END IF;
      IF OLD.status = 'published' AND (NEW.status <> 'published' OR
        NEW.offseason_input_revision_id IS DISTINCT FROM OLD.offseason_input_revision_id OR
        NEW.published_generation IS DISTINCT FROM OLD.published_generation) THEN
        RAISE EXCEPTION 'Published departure result is immutable';
      END IF;
      IF OLD.generation IS NOT NULL AND
        (NEW.departure_batch_id, NEW.departure_acquisition_id, NEW.departure_dataset_normalization_id,
         NEW.validator_version, NEW.generation, NEW.report::text, NEW.choices::text)
        IS DISTINCT FROM
        (OLD.departure_batch_id, OLD.departure_acquisition_id, OLD.departure_dataset_normalization_id,
         OLD.validator_version, OLD.generation, OLD.report::text, OLD.choices::text) THEN
        RAISE EXCEPTION 'Verified departure certificate is immutable';
      END IF;
      RETURN NEW;
    END $$;
    CREATE TRIGGER departure_validation_immutable BEFORE UPDATE OR DELETE ON departure_validations
      FOR EACH ROW EXECUTE FUNCTION departure_validation_immutable();
    CREATE FUNCTION departure_verified_rows_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      IF TG_OP = 'UPDATE' AND NEW.departure_dataset_normalization_id IS DISTINCT FROM OLD.departure_dataset_normalization_id THEN
        RAISE EXCEPTION 'Departure dataset row ownership is immutable';
      END IF;
      IF EXISTS (SELECT 1 FROM departure_validations WHERE departure_dataset_normalization_id IN
        (NEW.departure_dataset_normalization_id, OLD.departure_dataset_normalization_id)
        AND generation IS NOT NULL) THEN
        RAISE EXCEPTION 'Verified departure dataset is immutable';
      END IF;
      RETURN COALESCE(NEW, OLD);
    END $$;
    CREATE TRIGGER departure_verified_rows_immutable BEFORE INSERT OR UPDATE OR DELETE ON departure_dataset_rows
      FOR EACH ROW EXECUTE FUNCTION departure_verified_rows_immutable();
  SQL

  NORMALIZATION_TRIGGERS_SQL = <<~SQL.squish.freeze
    CREATE FUNCTION departure_normalization_changed() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE changed boolean;
    BEGIN
      IF TG_OP = 'DELETE' THEN
        changed := true;
      ELSIF TG_TABLE_NAME = 'departure_source_normalizations' THEN
        changed := OLD.status = 'completed' OR
          (NEW.identity, NEW.contract::text, NEW.departure_source_capture_id) IS DISTINCT FROM
          (OLD.identity, OLD.contract::text, OLD.departure_source_capture_id);
      ELSE
        changed := OLD.status = 'completed' OR
          (NEW.identity, NEW.header::text, NEW.source_normalization_ids::text) IS DISTINCT FROM
          (OLD.identity, OLD.header::text, OLD.source_normalization_ids::text);
      END IF;
      IF changed THEN
        UPDATE departure_dependency_generations SET generation = generation + 1 WHERE id = 1;
      END IF;
      RETURN NULL;
    END $$;
    CREATE TRIGGER departure_normalization_changed AFTER UPDATE OR DELETE ON departure_source_normalizations
      FOR EACH ROW EXECUTE FUNCTION departure_normalization_changed();
    CREATE TRIGGER departure_normalization_changed AFTER UPDATE OR DELETE ON departure_dataset_normalizations
      FOR EACH ROW EXECUTE FUNCTION departure_normalization_changed();
    CREATE FUNCTION departure_normalized_row_changed() RETURNS trigger LANGUAGE plpgsql AS $$
    DECLARE completed boolean;
    BEGIN
      IF TG_TABLE_NAME = 'departure_normalized_rows' THEN
        SELECT EXISTS (SELECT 1 FROM departure_source_normalizations
          WHERE id IN (NEW.departure_source_normalization_id, OLD.departure_source_normalization_id)
          AND status = 'completed') INTO completed;
      ELSE
        SELECT EXISTS (SELECT 1 FROM departure_dataset_normalizations
          WHERE id IN (NEW.departure_dataset_normalization_id, OLD.departure_dataset_normalization_id)
          AND status = 'completed') INTO completed;
      END IF;
      IF completed THEN
        UPDATE departure_dependency_generations SET generation = generation + 1 WHERE id = 1;
      END IF;
      RETURN NULL;
    END $$;
    CREATE TRIGGER departure_normalized_row_changed AFTER INSERT OR UPDATE OR DELETE ON departure_normalized_rows
      FOR EACH ROW EXECUTE FUNCTION departure_normalized_row_changed();
    CREATE TRIGGER departure_normalized_row_changed AFTER INSERT OR UPDATE OR DELETE ON departure_dataset_rows
      FOR EACH ROW EXECUTE FUNCTION departure_normalized_row_changed();
  SQL

  def up
    create_generations
    create_validations
    create_proposals
    create_approvals
    execute GENERATION_FUNCTION_SQL
    INPUT_TABLES.each { |table| generation_trigger(table, 'INSERT OR UPDATE OR DELETE') }
    CAPTURE_TABLES.each { |table| generation_trigger(table, 'UPDATE OR DELETE') }
    execute CERTIFICATE_TRIGGERS_SQL
    normalization_triggers
  end

  def normalization_triggers
    execute NORMALIZATION_TRIGGERS_SQL
  end

  def down
    execute 'DROP FUNCTION departure_normalized_row_changed() CASCADE'
    execute 'DROP FUNCTION departure_normalization_changed() CASCADE'
    execute 'DROP FUNCTION departure_verified_rows_immutable() CASCADE'
    execute 'DROP FUNCTION departure_validation_immutable() CASCADE'
    execute 'DROP FUNCTION departure_proposal_immutable() CASCADE'
    execute 'DROP FUNCTION departure_certificate_immutable() CASCADE'
    execute 'DROP FUNCTION departure_dependency_changed() CASCADE'
    drop_table :departure_approvals
    drop_table :departure_proposals
    drop_table :departure_validations
    drop_table :departure_dependency_generations
  end

  private

  def create_generations
    create_table :departure_dependency_generations do |t|
      t.bigint :generation, null: false, default: 0
      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end
    execute 'INSERT INTO departure_dependency_generations (id, generation) VALUES (1, 0)'
  end

  def create_validations
    create_table :departure_validations do |t|
      t.references :departure_batch, null: false, foreign_key: true
      t.references :departure_acquisition, null: false, foreign_key: true
      t.references :departure_dataset_normalization, foreign_key: true
      t.references :offseason_input_revision, foreign_key: true
      t.string :status, null: false, default: 'queued'
      t.string :validator_version, null: false
      t.bigint :generation
      t.bigint :published_generation
      t.jsonb :report, null: false, default: {}
      t.jsonb :choices, null: false, default: {}
      t.text :error
      t.timestamps
    end
  end

  def create_proposals
    create_table :departure_proposals do |t|
      t.references :departure_validation, null: false, foreign_key: true
      t.references :team, null: false, foreign_key: true
      t.jsonb :input, null: false
      t.timestamps
    end
    add_index :departure_proposals, %i[departure_validation_id team_id], unique: true
  end

  def create_approvals
    create_table :departure_approvals do |t|
      t.references :departure_validation, null: false, foreign_key: true, index: { unique: true }
      t.references :user, foreign_key: true
      t.string :reviewed_by, null: false
      t.datetime :reviewed_at, null: false
      t.jsonb :document, null: false
      t.string :review_hash, null: false
      t.bigint :predecessor_id
      t.timestamps
    end
  end

  def generation_trigger(table, events)
    execute "CREATE TRIGGER departure_dependency_changed AFTER #{events} ON #{table} " \
            'FOR EACH STATEMENT EXECUTE FUNCTION departure_dependency_changed()'
  end
end
