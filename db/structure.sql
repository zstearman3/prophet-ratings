SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: departure_certificate_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_certificate_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN RAISE EXCEPTION 'Verified departure certificate artifacts are immutable'; END $$;


--
-- Name: departure_dependency_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_dependency_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN INSERT INTO departure_dependency_generations (id, generation) VALUES (1, 1) ON CONFLICT (id) DO UPDATE SET generation = departure_dependency_generations.generation + 1; RETURN NULL; END $$;


--
-- Name: departure_normalization_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_normalization_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE changed boolean; BEGIN IF TG_OP = 'DELETE' THEN changed := true; ELSIF TG_TABLE_NAME = 'departure_source_normalizations' THEN changed := OLD.status = 'completed' OR (NEW.identity, NEW.contract::text, NEW.departure_source_capture_id) IS DISTINCT FROM (OLD.identity, OLD.contract::text, OLD.departure_source_capture_id); ELSE changed := OLD.status = 'completed' OR (NEW.identity, NEW.header::text, NEW.source_normalization_ids::text) IS DISTINCT FROM (OLD.identity, OLD.header::text, OLD.source_normalization_ids::text); END IF; IF changed THEN UPDATE departure_dependency_generations SET generation = generation + 1 WHERE id = 1; END IF; RETURN NULL; END $$;


--
-- Name: departure_normalized_row_changed(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_normalized_row_changed() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE completed boolean; BEGIN IF TG_TABLE_NAME = 'departure_normalized_rows' THEN SELECT EXISTS (SELECT 1 FROM departure_source_normalizations WHERE id IN (NEW.departure_source_normalization_id, OLD.departure_source_normalization_id) AND status = 'completed') INTO completed; ELSE SELECT EXISTS (SELECT 1 FROM departure_dataset_normalizations WHERE id IN (NEW.departure_dataset_normalization_id, OLD.departure_dataset_normalization_id) AND status = 'completed') INTO completed; END IF; IF completed THEN UPDATE departure_dependency_generations SET generation = generation + 1 WHERE id = 1; END IF; RETURN NULL; END $$;


--
-- Name: departure_proposal_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_proposal_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'Departure proposal ownership and content are immutable'; END IF; IF EXISTS (SELECT 1 FROM departure_validations WHERE id IN (NEW.departure_validation_id, OLD.departure_validation_id) AND (generation IS NOT NULL OR status <> 'running')) THEN RAISE EXCEPTION 'Verified departure proposals are immutable'; END IF; IF NOT EXISTS (SELECT 1 FROM departure_validations v JOIN departure_batches b ON b.id = v.departure_batch_id JOIN team_seasons m ON m.season_id = b.season_id AND m.team_id = NEW.team_id WHERE v.id = NEW.departure_validation_id) THEN RAISE EXCEPTION 'Departure proposal requires a target season member'; END IF; RETURN NEW; END $$;


--
-- Name: departure_validation_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_validation_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF TG_OP = 'DELETE' THEN IF OLD.generation IS NOT NULL THEN RAISE EXCEPTION 'Verified departure certificate is immutable'; END IF; RETURN OLD; END IF; IF (NEW.departure_batch_id, NEW.departure_acquisition_id, NEW.validator_version) IS DISTINCT FROM (OLD.departure_batch_id, OLD.departure_acquisition_id, OLD.validator_version) THEN RAISE EXCEPTION 'Departure validation identity is immutable'; END IF; IF OLD.status = 'published' AND (NEW.status <> 'published' OR NEW.offseason_input_revision_id IS DISTINCT FROM OLD.offseason_input_revision_id OR NEW.published_generation IS DISTINCT FROM OLD.published_generation) THEN RAISE EXCEPTION 'Published departure result is immutable'; END IF; IF OLD.generation IS NOT NULL AND (NEW.departure_batch_id, NEW.departure_acquisition_id, NEW.departure_dataset_normalization_id, NEW.validator_version, NEW.generation, NEW.report::text, NEW.choices::text) IS DISTINCT FROM (OLD.departure_batch_id, OLD.departure_acquisition_id, OLD.departure_dataset_normalization_id, OLD.validator_version, OLD.generation, OLD.report::text, OLD.choices::text) THEN RAISE EXCEPTION 'Verified departure certificate is immutable'; END IF; RETURN NEW; END $$;


--
-- Name: departure_verified_rows_immutable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.departure_verified_rows_immutable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF TG_OP = 'UPDATE' AND NEW.departure_dataset_normalization_id IS DISTINCT FROM OLD.departure_dataset_normalization_id THEN RAISE EXCEPTION 'Departure dataset row ownership is immutable'; END IF; IF EXISTS (SELECT 1 FROM departure_validations WHERE departure_dataset_normalization_id IN (NEW.departure_dataset_normalization_id, OLD.departure_dataset_normalization_id) AND generation IS NOT NULL) THEN RAISE EXCEPTION 'Verified departure dataset is immutable'; END IF; RETURN COALESCE(NEW, OLD); END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bet_recommendations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bet_recommendations (
    id bigint NOT NULL,
    game_id bigint NOT NULL,
    prediction_id bigint NOT NULL,
    game_odd_id bigint NOT NULL,
    bet_type character varying NOT NULL,
    team character varying,
    vegas_line double precision,
    vegas_odds integer NOT NULL,
    model_value double precision NOT NULL,
    ev double precision NOT NULL,
    confidence double precision,
    recommended boolean DEFAULT false NOT NULL,
    result character varying,
    payout double precision,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ratings_config_version_id bigint,
    current boolean DEFAULT false
);


--
-- Name: COLUMN bet_recommendations.bet_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.bet_type IS '''moneyline'', ''spread'', or ''total''';


--
-- Name: COLUMN bet_recommendations.team; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.team IS '''home'', ''away'', ''over'', ''under''';


--
-- Name: COLUMN bet_recommendations.vegas_line; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.vegas_line IS 'point spread or total; nil for moneyline';


--
-- Name: COLUMN bet_recommendations.vegas_odds; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.vegas_odds IS 'payout in American odds (e.g. -110, +150)';


--
-- Name: COLUMN bet_recommendations.model_value; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.model_value IS 'model-predicted value (spread, total, or win %)';


--
-- Name: COLUMN bet_recommendations.ev; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.ev IS 'expected value (unit-neutral, e.g. +0.07 = +7%)';


--
-- Name: COLUMN bet_recommendations.confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.confidence IS 'optional: model confidence (0.0–1.0 or 0–100 scale)';


--
-- Name: COLUMN bet_recommendations.recommended; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.recommended IS 'whether the bet is actionable';


--
-- Name: COLUMN bet_recommendations.result; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.result IS '''win'', ''loss'', ''push''';


--
-- Name: COLUMN bet_recommendations.payout; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.bet_recommendations.payout IS 'net return in units, e.g. +0.91, -1.00';


--
-- Name: bet_recommendations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bet_recommendations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bet_recommendations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bet_recommendations_id_seq OWNED BY public.bet_recommendations.id;


--
-- Name: bookmaker_odds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookmaker_odds (
    id bigint NOT NULL,
    game_id bigint NOT NULL,
    bookmaker character varying NOT NULL,
    fetched_at timestamp(6) without time zone NOT NULL,
    market character varying NOT NULL,
    team_name character varying,
    team_side character varying,
    value numeric,
    odds integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: bookmaker_odds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.bookmaker_odds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: bookmaker_odds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.bookmaker_odds_id_seq OWNED BY public.bookmaker_odds.id;


--
-- Name: cbbd_review_captures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cbbd_review_captures (
    id bigint NOT NULL,
    cbbd_review_run_id bigint NOT NULL,
    capture_id character varying NOT NULL,
    body bytea NOT NULL,
    metadata jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cbbd_review_captures_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cbbd_review_captures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cbbd_review_captures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cbbd_review_captures_id_seq OWNED BY public.cbbd_review_captures.id;


--
-- Name: cbbd_review_comparisons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cbbd_review_comparisons (
    id bigint NOT NULL,
    cbbd_review_run_id bigint NOT NULL,
    version integer NOT NULL,
    replay jsonb NOT NULL,
    report jsonb NOT NULL,
    artifact_digest character varying NOT NULL,
    draft jsonb DEFAULT '{}'::jsonb NOT NULL,
    draft_revision integer DEFAULT 0 NOT NULL,
    identity_mapping_decision_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cbbd_review_comparisons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cbbd_review_comparisons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cbbd_review_comparisons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cbbd_review_comparisons_id_seq OWNED BY public.cbbd_review_comparisons.id;


--
-- Name: cbbd_review_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cbbd_review_runs (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    maximum_requests integer NOT NULL,
    retries integer NOT NULL,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    failure character varying,
    manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
    normalized_replay jsonb,
    evidence_digest character varying,
    active_comparison_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cbbd_review_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cbbd_review_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cbbd_review_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cbbd_review_runs_id_seq OWNED BY public.cbbd_review_runs.id;


--
-- Name: cbbd_sync_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cbbd_sync_runs (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    ratings_config_version_id bigint NOT NULL,
    season_start_date date NOT NULL,
    season_end_date date NOT NULL,
    schedule_date date NOT NULL,
    bucket timestamp(6) without time zone NOT NULL,
    maximum_requests integer NOT NULL,
    retries integer NOT NULL,
    past_acquisition_id bigint,
    past_status character varying DEFAULT 'pending'::character varying NOT NULL,
    past_report jsonb DEFAULT '{}'::jsonb NOT NULL,
    future_acquisition_id bigint,
    future_status character varying DEFAULT 'pending'::character varying NOT NULL,
    future_report jsonb DEFAULT '{}'::jsonb NOT NULL,
    analytics_status character varying DEFAULT 'pending'::character varying NOT NULL,
    analytics_job_id character varying,
    analytics_error character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: cbbd_sync_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.cbbd_sync_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: cbbd_sync_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.cbbd_sync_runs_id_seq OWNED BY public.cbbd_sync_runs.id;


--
-- Name: coaching_changes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coaching_changes (
    id bigint NOT NULL,
    team_id bigint,
    effective_year integer NOT NULL,
    coach_name character varying,
    destination_school character varying,
    previous_team_id bigint,
    previous_school character varying,
    previous_year integer,
    previous_role character varying,
    full_season_head_coach boolean DEFAULT false NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    previous_season_d1 boolean DEFAULT false NOT NULL,
    discovery_school character varying,
    discovery_coach_name character varying,
    discovery_former_coach character varying,
    discovery_present boolean,
    discovery_team_id bigint,
    discovery_previous_team_id bigint,
    CONSTRAINT coaching_effective_year CHECK (((effective_year >= 1) AND (effective_year <= 9999))),
    CONSTRAINT coaching_previous_year CHECK (((previous_year >= 1) AND (previous_year <= 9999))),
    CONSTRAINT coaching_status CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('confirmed'::character varying)::text, ('rejected'::character varying)::text])))
);


--
-- Name: coaching_changes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.coaching_changes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: coaching_changes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.coaching_changes_id_seq OWNED BY public.coaching_changes.id;


--
-- Name: coaching_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.coaching_reviews (
    id bigint NOT NULL,
    year integer NOT NULL,
    ready boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discovery_status character varying DEFAULT 'idle'::character varying NOT NULL,
    discovered_at timestamp(6) without time zone,
    discovery_error text,
    CONSTRAINT coaching_review_year CHECK (((year >= 1) AND (year <= 9999)))
);


--
-- Name: coaching_reviews_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.coaching_reviews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: coaching_reviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.coaching_reviews_id_seq OWNED BY public.coaching_reviews.id;


--
-- Name: conference_external_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conference_external_identities (
    id bigint NOT NULL,
    conference_id bigint NOT NULL,
    provider character varying NOT NULL,
    external_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: conference_external_identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conference_external_identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conference_external_identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conference_external_identities_id_seq OWNED BY public.conference_external_identities.id;


--
-- Name: conferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.conferences (
    id bigint NOT NULL,
    name character varying NOT NULL,
    abbreviation character varying,
    slug character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    sports_reference_slugs character varying[] DEFAULT '{}'::character varying[] NOT NULL
);


--
-- Name: conferences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.conferences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: conferences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.conferences_id_seq OWNED BY public.conferences.id;


--
-- Name: departure_acquisitions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_acquisitions (
    id bigint NOT NULL,
    departure_batch_id bigint NOT NULL,
    predecessor_id bigint,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    plan jsonb DEFAULT '{}'::jsonb NOT NULL,
    manifest jsonb DEFAULT '{}'::jsonb NOT NULL,
    dataset jsonb DEFAULT '{}'::jsonb NOT NULL,
    evidence jsonb DEFAULT '{}'::jsonb NOT NULL,
    failure character varying,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departure_acquisitions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_acquisitions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_acquisitions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_acquisitions_id_seq OWNED BY public.departure_acquisitions.id;


--
-- Name: departure_approvals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_approvals (
    id bigint NOT NULL,
    departure_validation_id bigint NOT NULL,
    user_id bigint,
    reviewed_by character varying NOT NULL,
    reviewed_at timestamp(6) without time zone NOT NULL,
    document jsonb NOT NULL,
    review_hash character varying NOT NULL,
    predecessor_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departure_approvals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_approvals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_approvals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_approvals_id_seq OWNED BY public.departure_approvals.id;


--
-- Name: departure_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_batches (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    revision_id bigint,
    predecessor_id bigint,
    status character varying DEFAULT 'draft'::character varying NOT NULL,
    plan jsonb DEFAULT '{}'::jsonb NOT NULL,
    decisions jsonb DEFAULT '[]'::jsonb NOT NULL,
    acknowledgement jsonb DEFAULT '{}'::jsonb NOT NULL,
    correction_reason character varying,
    reviewed_by character varying,
    reviewed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departure_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_batches_id_seq OWNED BY public.departure_batches.id;


--
-- Name: departure_capture_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_capture_observations (
    id bigint NOT NULL,
    departure_source_capture_id bigint NOT NULL,
    departure_acquisition_id bigint NOT NULL,
    source_id character varying NOT NULL,
    metadata jsonb NOT NULL,
    extraction_version character varying NOT NULL
);


--
-- Name: departure_capture_observations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_capture_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_capture_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_capture_observations_id_seq OWNED BY public.departure_capture_observations.id;


--
-- Name: departure_dataset_normalizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_dataset_normalizations (
    id bigint NOT NULL,
    identity character varying NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    header jsonb NOT NULL,
    source_normalization_ids jsonb DEFAULT '{}'::jsonb NOT NULL,
    dataset_revision character varying,
    summary jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: departure_dataset_normalizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_dataset_normalizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_dataset_normalizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_dataset_normalizations_id_seq OWNED BY public.departure_dataset_normalizations.id;


--
-- Name: departure_dataset_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_dataset_rows (
    id bigint NOT NULL,
    departure_dataset_normalization_id bigint NOT NULL,
    kind character varying NOT NULL,
    ordinal integer NOT NULL,
    fact json NOT NULL
);


--
-- Name: departure_dataset_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_dataset_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_dataset_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_dataset_rows_id_seq OWNED BY public.departure_dataset_rows.id;


--
-- Name: departure_dependency_generations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_dependency_generations (
    id bigint NOT NULL,
    generation bigint DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL
);


--
-- Name: departure_dependency_generations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_dependency_generations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_dependency_generations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_dependency_generations_id_seq OWNED BY public.departure_dependency_generations.id;


--
-- Name: departure_normalized_rows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_normalized_rows (
    id bigint NOT NULL,
    departure_source_normalization_id bigint NOT NULL,
    ordinal integer NOT NULL,
    row_key character varying NOT NULL,
    provider_team_id bigint,
    provider_player_id bigint,
    fact json NOT NULL
);


--
-- Name: departure_normalized_rows_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_normalized_rows_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_normalized_rows_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_normalized_rows_id_seq OWNED BY public.departure_normalized_rows.id;


--
-- Name: departure_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_proposals (
    id bigint NOT NULL,
    departure_validation_id bigint NOT NULL,
    team_id bigint NOT NULL,
    input jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departure_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_proposals_id_seq OWNED BY public.departure_proposals.id;


--
-- Name: departure_source_captures; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_source_captures (
    id bigint NOT NULL,
    sha256 character varying NOT NULL,
    byte_size bigint NOT NULL,
    body bytea NOT NULL
);


--
-- Name: departure_source_captures_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_source_captures_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_source_captures_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_source_captures_id_seq OWNED BY public.departure_source_captures.id;


--
-- Name: departure_source_normalizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_source_normalizations (
    id bigint NOT NULL,
    departure_source_capture_id bigint NOT NULL,
    identity character varying NOT NULL,
    contract jsonb NOT NULL,
    status character varying DEFAULT 'running'::character varying NOT NULL,
    rows_digest character varying,
    row_count integer DEFAULT 0 NOT NULL,
    failure text
);


--
-- Name: departure_source_normalizations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_source_normalizations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_source_normalizations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_source_normalizations_id_seq OWNED BY public.departure_source_normalizations.id;


--
-- Name: departure_validations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.departure_validations (
    id bigint NOT NULL,
    departure_batch_id bigint NOT NULL,
    departure_acquisition_id bigint NOT NULL,
    departure_dataset_normalization_id bigint,
    offseason_input_revision_id bigint,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    validator_version character varying NOT NULL,
    generation bigint,
    published_generation bigint,
    report jsonb DEFAULT '{}'::jsonb NOT NULL,
    choices jsonb DEFAULT '{}'::jsonb NOT NULL,
    error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: departure_validations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.departure_validations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: departure_validations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.departure_validations_id_seq OWNED BY public.departure_validations.id;


--
-- Name: game_external_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_external_identities (
    id bigint NOT NULL,
    game_id bigint NOT NULL,
    provider character varying NOT NULL,
    external_id character varying NOT NULL,
    superseded_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_external_identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_external_identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_external_identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_external_identities_id_seq OWNED BY public.game_external_identities.id;


--
-- Name: game_observations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_observations (
    id bigint NOT NULL,
    game_id bigint,
    provider character varying,
    external_game_id character varying,
    semantic_profile character varying,
    outcome character varying NOT NULL,
    reason text,
    accepted boolean DEFAULT false NOT NULL,
    normalized_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    raw_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    payload_digest character varying,
    captured_at timestamp(6) without time zone,
    source_updated_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    scoring_review_id bigint
);


--
-- Name: game_observations_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_observations_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_observations_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_observations_id_seq OWNED BY public.game_observations.id;


--
-- Name: game_odds; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_odds (
    id bigint NOT NULL,
    game_id bigint NOT NULL,
    fetched_at timestamp(6) without time zone NOT NULL,
    moneyline_home integer,
    moneyline_away integer,
    spread_point numeric,
    spread_home_odds integer,
    spread_away_odds integer,
    total_points numeric,
    total_over_odds integer,
    total_under_odds integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_odds_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_odds_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_odds_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_odds_id_seq OWNED BY public.game_odds.id;


--
-- Name: game_scoring_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_scoring_reviews (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    schedule_refresh_run_id bigint NOT NULL,
    source_observation_id bigint NOT NULL,
    reviewed_by_id bigint NOT NULL,
    source_fingerprint character varying NOT NULL,
    reason character varying DEFAULT 'Approved by admin'::character varying NOT NULL,
    choices jsonb DEFAULT '{}'::jsonb NOT NULL,
    approved_payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    participants jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: game_scoring_reviews_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_scoring_reviews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_scoring_reviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_scoring_reviews_id_seq OWNED BY public.game_scoring_reviews.id;


--
-- Name: game_sync_dates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.game_sync_dates (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    schedule_date date NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    attempts integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    imported_rows integer,
    last_error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    provider character varying DEFAULT 'sports_reference'::character varying NOT NULL,
    contract_version character varying DEFAULT 'legacy-unscoped'::character varying NOT NULL,
    semantic_profile character varying DEFAULT 'sports-reference-legacy-v1'::character varying NOT NULL,
    adapter_revision character varying DEFAULT 'legacy-unscoped'::character varying NOT NULL
);


--
-- Name: game_sync_dates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.game_sync_dates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: game_sync_dates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.game_sync_dates_id_seq OWNED BY public.game_sync_dates.id;


--
-- Name: games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.games (
    id bigint NOT NULL,
    url character varying NOT NULL,
    start_time timestamp(6) without time zone NOT NULL,
    season_id bigint NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    home_team_name character varying NOT NULL,
    away_team_name character varying NOT NULL,
    home_team_score integer,
    away_team_score integer,
    possessions numeric(4,1),
    neutral boolean,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    minutes integer,
    in_conference boolean DEFAULT false,
    venue_type character varying DEFAULT 'unknown'::character varying NOT NULL,
    venue_source character varying,
    venue_confidence character varying DEFAULT 'unknown'::character varying NOT NULL,
    venue_name character varying
);


--
-- Name: games_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: games_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.games_id_seq OWNED BY public.games.id;


--
-- Name: good_job_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.good_job_batches (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    description text,
    serialized_properties jsonb,
    on_finish text,
    on_success text,
    on_discard text,
    callback_queue_name text,
    callback_priority integer,
    enqueued_at timestamp(6) without time zone,
    discarded_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    jobs_finished_at timestamp(6) without time zone
);


--
-- Name: good_job_executions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.good_job_executions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active_job_id uuid NOT NULL,
    job_class text,
    queue_name text,
    serialized_params jsonb,
    scheduled_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    error text,
    error_event smallint,
    error_backtrace text[],
    process_id uuid,
    duration interval
);


--
-- Name: good_job_processes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.good_job_processes (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    state jsonb,
    lock_type smallint
);


--
-- Name: good_job_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.good_job_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    key text,
    value jsonb
);


--
-- Name: good_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.good_jobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    queue_name text,
    priority integer,
    serialized_params jsonb,
    scheduled_at timestamp(6) without time zone,
    performed_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    error text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    active_job_id uuid,
    concurrency_key text,
    cron_key text,
    retried_good_job_id uuid,
    cron_at timestamp(6) without time zone,
    batch_id uuid,
    batch_callback_id uuid,
    is_discrete boolean,
    executions_count integer,
    job_class text,
    error_event smallint,
    labels text[],
    locked_by_id uuid,
    locked_at timestamp(6) without time zone
);


--
-- Name: identity_mapping_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.identity_mapping_decisions (
    id bigint NOT NULL,
    request_digest character varying NOT NULL,
    comparison_fingerprint character varying NOT NULL,
    post_apply_fingerprint character varying NOT NULL,
    reviewer character varying NOT NULL,
    reason text NOT NULL,
    request jsonb NOT NULL,
    result jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: identity_mapping_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.identity_mapping_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: identity_mapping_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.identity_mapping_decisions_id_seq OWNED BY public.identity_mapping_decisions.id;


--
-- Name: offseason_input_revisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offseason_input_revisions (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    kind character varying NOT NULL,
    version character varying NOT NULL,
    input_hash character varying NOT NULL,
    dataset_hash character varying NOT NULL,
    review_hash character varying NOT NULL,
    predecessor_id bigint,
    reason text NOT NULL,
    payload jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: offseason_input_revisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.offseason_input_revisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: offseason_input_revisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.offseason_input_revisions_id_seq OWNED BY public.offseason_input_revisions.id;


--
-- Name: offseason_readiness_reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.offseason_readiness_reviews (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    ratings_config_version_id bigint,
    reviewer_id bigint NOT NULL,
    fingerprint character varying NOT NULL,
    report jsonb NOT NULL,
    acknowledgement jsonb DEFAULT '{}'::jsonb NOT NULL,
    deferrals jsonb DEFAULT '{}'::jsonb NOT NULL,
    results jsonb DEFAULT '{}'::jsonb NOT NULL,
    attempts jsonb DEFAULT '[]'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: offseason_readiness_reviews_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.offseason_readiness_reviews_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: offseason_readiness_reviews_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.offseason_readiness_reviews_id_seq OWNED BY public.offseason_readiness_reviews.id;


--
-- Name: predictions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.predictions (
    id bigint NOT NULL,
    home_offensive_efficiency numeric(6,3),
    home_defensive_efficiency numeric(6,3),
    away_offensive_efficiency numeric(6,3),
    away_defensive_efficiency numeric(6,3),
    pace numeric(6,3),
    home_score numeric(6,3),
    away_score numeric(6,3),
    home_offensive_efficiency_error numeric(6,3),
    home_defensive_efficiency_error numeric(6,3),
    away_offensive_efficiency_error numeric(6,3),
    away_defensive_efficiency_error numeric(6,3),
    pace_error numeric(6,3),
    game_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    home_team_snapshot_id bigint,
    away_team_snapshot_id bigint,
    home_win_probability double precision,
    vegas_spread numeric(6,3),
    vegas_total numeric(6,3),
    ratings_config_version_id bigint,
    calculation_context jsonb DEFAULT '{}'::jsonb NOT NULL,
    forecast_kind character varying DEFAULT 'legacy_unverified'::character varying NOT NULL,
    generated_at timestamp(6) without time zone,
    forecast_start_time timestamp(6) without time zone,
    input_cutoff date,
    revision_key character varying
);


--
-- Name: predictions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.predictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: predictions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.predictions_id_seq OWNED BY public.predictions.id;


--
-- Name: preseason_priors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.preseason_priors (
    id bigint NOT NULL,
    team_season_id bigint NOT NULL,
    ratings_config_version_id bigint NOT NULL,
    inputs jsonb NOT NULL,
    outputs jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: preseason_priors_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.preseason_priors_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: preseason_priors_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.preseason_priors_id_seq OWNED BY public.preseason_priors.id;


--
-- Name: preseason_publications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.preseason_publications (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    ratings_config_version_id bigint NOT NULL,
    reviewer_id bigint NOT NULL,
    mode character varying NOT NULL,
    status character varying DEFAULT 'review'::character varying NOT NULL,
    fingerprint character varying NOT NULL,
    report jsonb NOT NULL,
    acknowledgement jsonb DEFAULT '{}'::jsonb NOT NULL,
    result jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    queued_at timestamp(6) without time zone,
    started_at timestamp(6) without time zone,
    published_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: preseason_publications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.preseason_publications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: preseason_publications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.preseason_publications_id_seq OWNED BY public.preseason_publications.id;


--
-- Name: ratings_config_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ratings_config_versions (
    id bigint NOT NULL,
    config jsonb NOT NULL,
    description character varying,
    name character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    current boolean DEFAULT false
);


--
-- Name: ratings_config_versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ratings_config_versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ratings_config_versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ratings_config_versions_id_seq OWNED BY public.ratings_config_versions.id;


--
-- Name: recruiting_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recruiting_batches (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    revision_id bigint,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    source_year integer NOT NULL,
    source_status character varying,
    dataset_revision character varying,
    extract_bytes text,
    snapshot_bytes text,
    coverage_note text,
    failure_message text,
    next_url text,
    page_count integer DEFAULT 0 NOT NULL,
    reviewed_by character varying,
    reviewed_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recruiting_batches_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recruiting_batches_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recruiting_batches_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recruiting_batches_id_seq OWNED BY public.recruiting_batches.id;


--
-- Name: recruiting_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recruiting_entries (
    id bigint NOT NULL,
    recruiting_batch_id bigint NOT NULL,
    team_id bigint,
    row_number integer NOT NULL,
    source_label character varying,
    provider_team_id character varying,
    source_url text,
    source_rank numeric,
    class_points numeric,
    average_rating numeric,
    commit_count numeric,
    source_row jsonb,
    source_errors jsonb DEFAULT '[]'::jsonb NOT NULL,
    excluded boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recruiting_entries_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.recruiting_entries_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: recruiting_entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.recruiting_entries_id_seq OWNED BY public.recruiting_entries.id;


--
-- Name: schedule_deferrals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedule_deferrals (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    requested_by_id bigint NOT NULL,
    reason text NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schedule_deferrals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.schedule_deferrals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_deferrals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.schedule_deferrals_id_seq OWNED BY public.schedule_deferrals.id;


--
-- Name: schedule_refresh_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedule_refresh_runs (
    id bigint NOT NULL,
    season_id bigint NOT NULL,
    requested_by_id bigint NOT NULL,
    retry_of_id bigint,
    provider character varying NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    requested_dates jsonb DEFAULT '[]'::jsonb NOT NULL,
    max_requests integer,
    retries integer,
    status character varying DEFAULT 'queued'::character varying NOT NULL,
    report jsonb DEFAULT '{}'::jsonb NOT NULL,
    error text,
    started_at timestamp(6) without time zone,
    finished_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    mode character varying DEFAULT 'upcoming'::character varying NOT NULL,
    rescan boolean DEFAULT false NOT NULL
);


--
-- Name: schedule_refresh_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.schedule_refresh_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: schedule_refresh_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.schedule_refresh_runs_id_seq OWNED BY public.schedule_refresh_runs.id;


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: seasons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.seasons (
    id bigint NOT NULL,
    year integer NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    average_efficiency numeric(6,3),
    average_pace numeric(6,3),
    efficiency_std_deviation numeric(6,3),
    pace_std_deviation numeric(6,3),
    avg_adj_offensive_efficiency numeric(6,3),
    stddev_adj_offensive_efficiency numeric(6,3),
    avg_adj_defensive_efficiency numeric(6,3),
    stddev_adj_defensive_efficiency numeric(6,3),
    avg_adj_effective_fg_percentage numeric(6,5),
    stddev_adj_effective_fg_percentage numeric(6,5),
    avg_adj_turnover_rate numeric(6,5),
    stddev_adj_turnover_rate numeric(6,5),
    avg_adj_offensive_rebound_rate numeric(6,5),
    stddev_adj_offensive_rebound_rate numeric(6,5),
    avg_adj_free_throw_rate numeric(6,5),
    stddev_adj_free_throw_rate numeric(6,5),
    avg_adj_effective_fg_percentage_allowed numeric(6,5),
    stddev_adj_effective_fg_percentage_allowed numeric(6,5),
    avg_adj_turnover_rate_forced numeric(6,5),
    stddev_adj_turnover_rate_forced numeric(6,5),
    avg_adj_defensive_rebound_rate numeric(6,5),
    stddev_adj_defensive_rebound_rate numeric(6,5),
    avg_adj_free_throw_rate_allowed numeric(6,5),
    stddev_adj_free_throw_rate_allowed numeric(6,5),
    avg_adj_three_pt_proficiency numeric(6,5),
    stddev_adj_three_pt_proficiency numeric(6,5),
    current boolean DEFAULT false,
    name character varying,
    participation_review jsonb DEFAULT '{}'::jsonb NOT NULL,
    preseason_revision_id bigint,
    membership_proposal jsonb DEFAULT '{}'::jsonb NOT NULL,
    membership_corrections jsonb DEFAULT '[]'::jsonb NOT NULL,
    selected_preseason_model_id bigint,
    preseason_selection_generation integer DEFAULT 0 NOT NULL
);


--
-- Name: seasons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.seasons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: seasons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.seasons_id_seq OWNED BY public.seasons.id;


--
-- Name: team_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_aliases (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    value character varying NOT NULL,
    source character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: team_aliases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_aliases_id_seq OWNED BY public.team_aliases.id;


--
-- Name: team_conferences; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_conferences (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    conference_id bigint NOT NULL,
    start_season_id bigint NOT NULL,
    end_season_id bigint,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: team_conferences_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_conferences_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_conferences_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_conferences_id_seq OWNED BY public.team_conferences.id;


--
-- Name: team_external_identities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_external_identities (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    provider character varying NOT NULL,
    external_id character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: team_external_identities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_external_identities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_external_identities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_external_identities_id_seq OWNED BY public.team_external_identities.id;


--
-- Name: team_games; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_games (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    game_id bigint NOT NULL,
    home boolean DEFAULT false,
    minutes integer,
    field_goals_made integer,
    field_goals_attempted integer,
    field_goals_percentage numeric(6,5),
    two_pt_made integer,
    two_pt_attempted integer,
    two_pt_percentage numeric(6,5),
    three_pt_made integer,
    three_pt_attempted integer,
    three_pt_percentage numeric(6,5),
    free_throws_made integer,
    free_throws_attempted integer,
    free_throws_percentage numeric(6,5),
    offensive_rebounds integer,
    defensive_rebounds integer,
    rebounds integer,
    assists integer,
    steals integer,
    blocks integer,
    turnovers integer,
    fouls integer,
    points integer,
    true_shooting_percentage numeric(6,5),
    effective_fg_percentage numeric(6,5),
    three_pt_attempt_rate numeric(6,5),
    free_throw_rate numeric(6,5),
    offensive_rebound_rate numeric(6,5),
    defensive_rebound_rate numeric(6,5),
    rebound_rate numeric(6,5),
    assist_rate numeric(6,5),
    steal_rate numeric(6,5),
    block_rate numeric(6,5),
    turnover_rate numeric(6,5),
    offensive_rating numeric(6,3),
    defensive_rating numeric(6,3),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    team_season_id bigint NOT NULL,
    opponent_team_season_id bigint,
    three_pt_proficiency numeric(6,5)
);


--
-- Name: team_games_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_games_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_games_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_games_id_seq OWNED BY public.team_games.id;


--
-- Name: team_offseason_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_offseason_profiles (
    id bigint NOT NULL,
    team_season_id bigint NOT NULL,
    recruiting_class_rank integer,
    recruiting_score double precision,
    returning_minutes_pct double precision,
    returning_bpm_total double precision,
    lost_starters integer,
    coaching_change boolean,
    manual_adjustment double precision,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    source_reference text,
    observed_on date,
    input_units jsonb DEFAULT '{}'::jsonb NOT NULL,
    manual_adjustment_reason text,
    recruiting_revision_id bigint,
    departure_revision_id bigint
);


--
-- Name: team_offseason_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_offseason_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_offseason_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_offseason_profiles_id_seq OWNED BY public.team_offseason_profiles.id;


--
-- Name: team_rating_snapshots; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_rating_snapshots (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    season_id bigint NOT NULL,
    team_season_id bigint NOT NULL,
    snapshot_date date NOT NULL,
    rating numeric(6,3),
    adj_offensive_efficiency numeric(6,3),
    adj_defensive_efficiency numeric(6,3),
    adj_pace numeric(6,3),
    stats jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    ratings_config_version_id bigint
);


--
-- Name: team_rating_snapshots_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_rating_snapshots_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_rating_snapshots_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_rating_snapshots_id_seq OWNED BY public.team_rating_snapshots.id;


--
-- Name: team_seasons; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_seasons (
    id bigint NOT NULL,
    team_id bigint NOT NULL,
    season_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    offensive_efficiency numeric(6,3),
    defensive_efficiency numeric(6,3),
    pace numeric(6,3),
    adj_offensive_efficiency numeric(6,3),
    adj_defensive_efficiency numeric(6,3),
    adj_pace numeric(6,3),
    rating numeric(6,3),
    effective_fg_percentage numeric(6,5),
    turnover_rate numeric(6,5),
    offensive_rebound_rate numeric(6,5),
    free_throw_rate numeric(6,5),
    three_pt_attempt_rate numeric(6,5),
    adj_effective_fg_percentage numeric(6,5),
    adj_effective_fg_percentage_allowed numeric(6,5),
    adj_turnover_rate numeric(6,5),
    adj_turnover_rate_forced numeric(6,5),
    adj_offensive_rebound_rate numeric(6,5),
    adj_defensive_rebound_rate numeric(6,5),
    adj_free_throw_rate numeric(6,5),
    adj_free_throw_rate_allowed numeric(6,5),
    home_offense_boost numeric(6,3),
    home_defense_boost numeric(6,3),
    away_offense_penalty numeric(6,3),
    away_defense_penalty numeric(6,3),
    offensive_efficiency_std_dev numeric(6,3),
    defensive_efficiency_std_dev numeric(6,3),
    preseason_adj_offensive_efficiency numeric(6,3),
    preseason_adj_defensive_efficiency numeric(6,3),
    preseason_adj_pace numeric(6,3),
    offensive_efficiency_volatility numeric(6,3),
    defensive_efficiency_volatility numeric(6,3),
    pace_volatility numeric(6,3),
    overall_rank integer,
    pace_rank integer,
    adj_offensive_efficiency_rank integer,
    adj_defensive_efficiency_rank integer,
    adj_effective_fg_percentage_rank integer,
    adj_turnover_rate_rank integer,
    adj_offensive_rebound_rate_rank integer,
    adj_free_throw_rate_rank integer,
    adj_effective_fg_percentage_allowed_rank integer,
    adj_turnover_rate_forced_rank integer,
    adj_defensive_rebound_rate_rank integer,
    adj_free_throw_rate_allowed_rank integer,
    total_home_boost numeric(6,3),
    total_volatility numeric(6,3),
    wins integer DEFAULT 0,
    losses integer DEFAULT 0,
    adj_pace_rank integer,
    adj_three_pt_proficiency numeric(6,5),
    adj_three_pt_proficiency_allowed numeric(6,5),
    adj_three_pt_proficiency_rank integer,
    adj_three_pt_proficiency_allowed_rank integer,
    three_pt_proficiency numeric(6,5),
    conference_wins integer DEFAULT 0,
    conference_losses integer DEFAULT 0,
    ratings_config_version_id bigint,
    preseason_prior_id bigint,
    rating_anchors jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: team_seasons_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.team_seasons_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: team_seasons_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.team_seasons_id_seq OWNED BY public.team_seasons.id;


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id bigint NOT NULL,
    school character varying,
    nickname character varying,
    url character varying,
    location character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    home_venue character varying,
    slug character varying,
    primary_color character varying,
    short_name character varying,
    the_odds_api_team_id character varying
);


--
-- Name: teams_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.teams_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: teams_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.teams_id_seq OWNED BY public.teams.id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    email character varying DEFAULT ''::character varying NOT NULL,
    encrypted_password character varying DEFAULT ''::character varying NOT NULL,
    reset_password_token character varying,
    reset_password_sent_at timestamp(6) without time zone,
    remember_created_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    admin boolean DEFAULT false
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: bet_recommendations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations ALTER COLUMN id SET DEFAULT nextval('public.bet_recommendations_id_seq'::regclass);


--
-- Name: bookmaker_odds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookmaker_odds ALTER COLUMN id SET DEFAULT nextval('public.bookmaker_odds_id_seq'::regclass);


--
-- Name: cbbd_review_captures id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_captures ALTER COLUMN id SET DEFAULT nextval('public.cbbd_review_captures_id_seq'::regclass);


--
-- Name: cbbd_review_comparisons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_comparisons ALTER COLUMN id SET DEFAULT nextval('public.cbbd_review_comparisons_id_seq'::regclass);


--
-- Name: cbbd_review_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_runs ALTER COLUMN id SET DEFAULT nextval('public.cbbd_review_runs_id_seq'::regclass);


--
-- Name: cbbd_sync_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs ALTER COLUMN id SET DEFAULT nextval('public.cbbd_sync_runs_id_seq'::regclass);


--
-- Name: coaching_changes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes ALTER COLUMN id SET DEFAULT nextval('public.coaching_changes_id_seq'::regclass);


--
-- Name: coaching_reviews id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_reviews ALTER COLUMN id SET DEFAULT nextval('public.coaching_reviews_id_seq'::regclass);


--
-- Name: conference_external_identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conference_external_identities ALTER COLUMN id SET DEFAULT nextval('public.conference_external_identities_id_seq'::regclass);


--
-- Name: conferences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conferences ALTER COLUMN id SET DEFAULT nextval('public.conferences_id_seq'::regclass);


--
-- Name: departure_acquisitions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_acquisitions ALTER COLUMN id SET DEFAULT nextval('public.departure_acquisitions_id_seq'::regclass);


--
-- Name: departure_approvals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_approvals ALTER COLUMN id SET DEFAULT nextval('public.departure_approvals_id_seq'::regclass);


--
-- Name: departure_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_batches ALTER COLUMN id SET DEFAULT nextval('public.departure_batches_id_seq'::regclass);


--
-- Name: departure_capture_observations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_capture_observations ALTER COLUMN id SET DEFAULT nextval('public.departure_capture_observations_id_seq'::regclass);


--
-- Name: departure_dataset_normalizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dataset_normalizations ALTER COLUMN id SET DEFAULT nextval('public.departure_dataset_normalizations_id_seq'::regclass);


--
-- Name: departure_dataset_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dataset_rows ALTER COLUMN id SET DEFAULT nextval('public.departure_dataset_rows_id_seq'::regclass);


--
-- Name: departure_dependency_generations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dependency_generations ALTER COLUMN id SET DEFAULT nextval('public.departure_dependency_generations_id_seq'::regclass);


--
-- Name: departure_normalized_rows id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_normalized_rows ALTER COLUMN id SET DEFAULT nextval('public.departure_normalized_rows_id_seq'::regclass);


--
-- Name: departure_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_proposals ALTER COLUMN id SET DEFAULT nextval('public.departure_proposals_id_seq'::regclass);


--
-- Name: departure_source_captures id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_source_captures ALTER COLUMN id SET DEFAULT nextval('public.departure_source_captures_id_seq'::regclass);


--
-- Name: departure_source_normalizations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_source_normalizations ALTER COLUMN id SET DEFAULT nextval('public.departure_source_normalizations_id_seq'::regclass);


--
-- Name: departure_validations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations ALTER COLUMN id SET DEFAULT nextval('public.departure_validations_id_seq'::regclass);


--
-- Name: game_external_identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_external_identities ALTER COLUMN id SET DEFAULT nextval('public.game_external_identities_id_seq'::regclass);


--
-- Name: game_observations id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_observations ALTER COLUMN id SET DEFAULT nextval('public.game_observations_id_seq'::regclass);


--
-- Name: game_odds id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_odds ALTER COLUMN id SET DEFAULT nextval('public.game_odds_id_seq'::regclass);


--
-- Name: game_scoring_reviews id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews ALTER COLUMN id SET DEFAULT nextval('public.game_scoring_reviews_id_seq'::regclass);


--
-- Name: game_sync_dates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_sync_dates ALTER COLUMN id SET DEFAULT nextval('public.game_sync_dates_id_seq'::regclass);


--
-- Name: games id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games ALTER COLUMN id SET DEFAULT nextval('public.games_id_seq'::regclass);


--
-- Name: identity_mapping_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_mapping_decisions ALTER COLUMN id SET DEFAULT nextval('public.identity_mapping_decisions_id_seq'::regclass);


--
-- Name: offseason_input_revisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_input_revisions ALTER COLUMN id SET DEFAULT nextval('public.offseason_input_revisions_id_seq'::regclass);


--
-- Name: offseason_readiness_reviews id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_readiness_reviews ALTER COLUMN id SET DEFAULT nextval('public.offseason_readiness_reviews_id_seq'::regclass);


--
-- Name: predictions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predictions ALTER COLUMN id SET DEFAULT nextval('public.predictions_id_seq'::regclass);


--
-- Name: preseason_priors id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_priors ALTER COLUMN id SET DEFAULT nextval('public.preseason_priors_id_seq'::regclass);


--
-- Name: preseason_publications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_publications ALTER COLUMN id SET DEFAULT nextval('public.preseason_publications_id_seq'::regclass);


--
-- Name: ratings_config_versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ratings_config_versions ALTER COLUMN id SET DEFAULT nextval('public.ratings_config_versions_id_seq'::regclass);


--
-- Name: recruiting_batches id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_batches ALTER COLUMN id SET DEFAULT nextval('public.recruiting_batches_id_seq'::regclass);


--
-- Name: recruiting_entries id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_entries ALTER COLUMN id SET DEFAULT nextval('public.recruiting_entries_id_seq'::regclass);


--
-- Name: schedule_deferrals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_deferrals ALTER COLUMN id SET DEFAULT nextval('public.schedule_deferrals_id_seq'::regclass);


--
-- Name: schedule_refresh_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_refresh_runs ALTER COLUMN id SET DEFAULT nextval('public.schedule_refresh_runs_id_seq'::regclass);


--
-- Name: seasons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons ALTER COLUMN id SET DEFAULT nextval('public.seasons_id_seq'::regclass);


--
-- Name: team_aliases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_aliases ALTER COLUMN id SET DEFAULT nextval('public.team_aliases_id_seq'::regclass);


--
-- Name: team_conferences id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences ALTER COLUMN id SET DEFAULT nextval('public.team_conferences_id_seq'::regclass);


--
-- Name: team_external_identities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_external_identities ALTER COLUMN id SET DEFAULT nextval('public.team_external_identities_id_seq'::regclass);


--
-- Name: team_games id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_games ALTER COLUMN id SET DEFAULT nextval('public.team_games_id_seq'::regclass);


--
-- Name: team_offseason_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_offseason_profiles ALTER COLUMN id SET DEFAULT nextval('public.team_offseason_profiles_id_seq'::regclass);


--
-- Name: team_rating_snapshots id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots ALTER COLUMN id SET DEFAULT nextval('public.team_rating_snapshots_id_seq'::regclass);


--
-- Name: team_seasons id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_seasons ALTER COLUMN id SET DEFAULT nextval('public.team_seasons_id_seq'::regclass);


--
-- Name: teams id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams ALTER COLUMN id SET DEFAULT nextval('public.teams_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: bet_recommendations bet_recommendations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations
    ADD CONSTRAINT bet_recommendations_pkey PRIMARY KEY (id);


--
-- Name: bookmaker_odds bookmaker_odds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookmaker_odds
    ADD CONSTRAINT bookmaker_odds_pkey PRIMARY KEY (id);


--
-- Name: cbbd_review_captures cbbd_review_captures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_captures
    ADD CONSTRAINT cbbd_review_captures_pkey PRIMARY KEY (id);


--
-- Name: cbbd_review_comparisons cbbd_review_comparisons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_comparisons
    ADD CONSTRAINT cbbd_review_comparisons_pkey PRIMARY KEY (id);


--
-- Name: cbbd_review_runs cbbd_review_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_runs
    ADD CONSTRAINT cbbd_review_runs_pkey PRIMARY KEY (id);


--
-- Name: cbbd_sync_runs cbbd_sync_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs
    ADD CONSTRAINT cbbd_sync_runs_pkey PRIMARY KEY (id);


--
-- Name: coaching_changes coaching_changes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes
    ADD CONSTRAINT coaching_changes_pkey PRIMARY KEY (id);


--
-- Name: coaching_reviews coaching_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_reviews
    ADD CONSTRAINT coaching_reviews_pkey PRIMARY KEY (id);


--
-- Name: conference_external_identities conference_external_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conference_external_identities
    ADD CONSTRAINT conference_external_identities_pkey PRIMARY KEY (id);


--
-- Name: conferences conferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conferences
    ADD CONSTRAINT conferences_pkey PRIMARY KEY (id);


--
-- Name: departure_acquisitions departure_acquisitions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_acquisitions
    ADD CONSTRAINT departure_acquisitions_pkey PRIMARY KEY (id);


--
-- Name: departure_approvals departure_approvals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_approvals
    ADD CONSTRAINT departure_approvals_pkey PRIMARY KEY (id);


--
-- Name: departure_batches departure_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_batches
    ADD CONSTRAINT departure_batches_pkey PRIMARY KEY (id);


--
-- Name: departure_capture_observations departure_capture_observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_capture_observations
    ADD CONSTRAINT departure_capture_observations_pkey PRIMARY KEY (id);


--
-- Name: departure_dataset_normalizations departure_dataset_normalizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dataset_normalizations
    ADD CONSTRAINT departure_dataset_normalizations_pkey PRIMARY KEY (id);


--
-- Name: departure_dataset_rows departure_dataset_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dataset_rows
    ADD CONSTRAINT departure_dataset_rows_pkey PRIMARY KEY (id);


--
-- Name: departure_dependency_generations departure_dependency_generations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dependency_generations
    ADD CONSTRAINT departure_dependency_generations_pkey PRIMARY KEY (id);


--
-- Name: departure_normalized_rows departure_normalized_rows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_normalized_rows
    ADD CONSTRAINT departure_normalized_rows_pkey PRIMARY KEY (id);


--
-- Name: departure_proposals departure_proposals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_proposals
    ADD CONSTRAINT departure_proposals_pkey PRIMARY KEY (id);


--
-- Name: departure_source_captures departure_source_captures_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_source_captures
    ADD CONSTRAINT departure_source_captures_pkey PRIMARY KEY (id);


--
-- Name: departure_source_normalizations departure_source_normalizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_source_normalizations
    ADD CONSTRAINT departure_source_normalizations_pkey PRIMARY KEY (id);


--
-- Name: departure_validations departure_validations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations
    ADD CONSTRAINT departure_validations_pkey PRIMARY KEY (id);


--
-- Name: game_external_identities game_external_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_external_identities
    ADD CONSTRAINT game_external_identities_pkey PRIMARY KEY (id);


--
-- Name: game_observations game_observations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_observations
    ADD CONSTRAINT game_observations_pkey PRIMARY KEY (id);


--
-- Name: game_odds game_odds_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_odds
    ADD CONSTRAINT game_odds_pkey PRIMARY KEY (id);


--
-- Name: game_scoring_reviews game_scoring_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews
    ADD CONSTRAINT game_scoring_reviews_pkey PRIMARY KEY (id);


--
-- Name: game_sync_dates game_sync_dates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_sync_dates
    ADD CONSTRAINT game_sync_dates_pkey PRIMARY KEY (id);


--
-- Name: games games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.games
    ADD CONSTRAINT games_pkey PRIMARY KEY (id);


--
-- Name: good_job_batches good_job_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.good_job_batches
    ADD CONSTRAINT good_job_batches_pkey PRIMARY KEY (id);


--
-- Name: good_job_executions good_job_executions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.good_job_executions
    ADD CONSTRAINT good_job_executions_pkey PRIMARY KEY (id);


--
-- Name: good_job_processes good_job_processes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.good_job_processes
    ADD CONSTRAINT good_job_processes_pkey PRIMARY KEY (id);


--
-- Name: good_job_settings good_job_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.good_job_settings
    ADD CONSTRAINT good_job_settings_pkey PRIMARY KEY (id);


--
-- Name: good_jobs good_jobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.good_jobs
    ADD CONSTRAINT good_jobs_pkey PRIMARY KEY (id);


--
-- Name: identity_mapping_decisions identity_mapping_decisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.identity_mapping_decisions
    ADD CONSTRAINT identity_mapping_decisions_pkey PRIMARY KEY (id);


--
-- Name: offseason_input_revisions offseason_input_revisions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_input_revisions
    ADD CONSTRAINT offseason_input_revisions_pkey PRIMARY KEY (id);


--
-- Name: offseason_readiness_reviews offseason_readiness_reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_readiness_reviews
    ADD CONSTRAINT offseason_readiness_reviews_pkey PRIMARY KEY (id);


--
-- Name: predictions predictions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT predictions_pkey PRIMARY KEY (id);


--
-- Name: preseason_priors preseason_priors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_priors
    ADD CONSTRAINT preseason_priors_pkey PRIMARY KEY (id);


--
-- Name: preseason_publications preseason_publications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_publications
    ADD CONSTRAINT preseason_publications_pkey PRIMARY KEY (id);


--
-- Name: ratings_config_versions ratings_config_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ratings_config_versions
    ADD CONSTRAINT ratings_config_versions_pkey PRIMARY KEY (id);


--
-- Name: recruiting_batches recruiting_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_batches
    ADD CONSTRAINT recruiting_batches_pkey PRIMARY KEY (id);


--
-- Name: recruiting_entries recruiting_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_entries
    ADD CONSTRAINT recruiting_entries_pkey PRIMARY KEY (id);


--
-- Name: schedule_deferrals schedule_deferrals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_deferrals
    ADD CONSTRAINT schedule_deferrals_pkey PRIMARY KEY (id);


--
-- Name: schedule_refresh_runs schedule_refresh_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_refresh_runs
    ADD CONSTRAINT schedule_refresh_runs_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: seasons seasons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons
    ADD CONSTRAINT seasons_pkey PRIMARY KEY (id);


--
-- Name: team_aliases team_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_aliases
    ADD CONSTRAINT team_aliases_pkey PRIMARY KEY (id);


--
-- Name: team_conferences team_conferences_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences
    ADD CONSTRAINT team_conferences_pkey PRIMARY KEY (id);


--
-- Name: team_external_identities team_external_identities_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_external_identities
    ADD CONSTRAINT team_external_identities_pkey PRIMARY KEY (id);


--
-- Name: team_games team_games_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_games
    ADD CONSTRAINT team_games_pkey PRIMARY KEY (id);


--
-- Name: team_offseason_profiles team_offseason_profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_offseason_profiles
    ADD CONSTRAINT team_offseason_profiles_pkey PRIMARY KEY (id);


--
-- Name: team_rating_snapshots team_rating_snapshots_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots
    ADD CONSTRAINT team_rating_snapshots_pkey PRIMARY KEY (id);


--
-- Name: team_seasons team_seasons_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_seasons
    ADD CONSTRAINT team_seasons_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: idx_departure_dataset_row_order; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_departure_dataset_row_order ON public.departure_dataset_rows USING btree (departure_dataset_normalization_id, kind, ordinal);


--
-- Name: idx_departure_dataset_row_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departure_dataset_row_parent ON public.departure_dataset_rows USING btree (departure_dataset_normalization_id);


--
-- Name: idx_departure_normalization_capture; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departure_normalization_capture ON public.departure_source_normalizations USING btree (departure_source_capture_id);


--
-- Name: idx_departure_observation_capture; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departure_observation_capture ON public.departure_capture_observations USING btree (departure_source_capture_id);


--
-- Name: idx_departure_observation_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_departure_observation_identity ON public.departure_capture_observations USING btree (departure_acquisition_id, source_id);


--
-- Name: idx_departure_observation_origin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departure_observation_origin ON public.departure_capture_observations USING btree (departure_acquisition_id);


--
-- Name: idx_departure_row_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_departure_row_identity ON public.departure_normalized_rows USING btree (departure_source_normalization_id, row_key);


--
-- Name: idx_departure_row_order; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_departure_row_order ON public.departure_normalized_rows USING btree (departure_source_normalization_id, ordinal);


--
-- Name: idx_departure_row_source; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_departure_row_source ON public.departure_normalized_rows USING btree (departure_source_normalization_id);


--
-- Name: idx_on_cbbd_review_run_id_capture_id_29ffd9cbe6; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_cbbd_review_run_id_capture_id_29ffd9cbe6 ON public.cbbd_review_captures USING btree (cbbd_review_run_id, capture_id);


--
-- Name: idx_on_cbbd_review_run_id_version_0c5d8e333d; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_cbbd_review_run_id_version_0c5d8e333d ON public.cbbd_review_comparisons USING btree (cbbd_review_run_id, version);


--
-- Name: idx_on_departure_dataset_normalization_id_e41300d490; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_departure_dataset_normalization_id_e41300d490 ON public.departure_validations USING btree (departure_dataset_normalization_id);


--
-- Name: idx_on_departure_validation_id_team_id_9e7285e173; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_departure_validation_id_team_id_9e7285e173 ON public.departure_proposals USING btree (departure_validation_id, team_id);


--
-- Name: idx_on_provider_external_id_4998627b48; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_provider_external_id_4998627b48 ON public.conference_external_identities USING btree (provider, external_id);


--
-- Name: idx_trs_on_team_season_date_rcv_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_trs_on_team_season_date_rcv_unique ON public.team_rating_snapshots USING btree (team_id, season_id, snapshot_date, ratings_config_version_id);


--
-- Name: index_bet_recommendations_on_game_and_type_current_true; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bet_recommendations_on_game_and_type_current_true ON public.bet_recommendations USING btree (game_id, bet_type) WHERE (current IS TRUE);


--
-- Name: index_bet_recommendations_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bet_recommendations_on_game_id ON public.bet_recommendations USING btree (game_id);


--
-- Name: index_bet_recommendations_on_game_odd_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bet_recommendations_on_game_odd_id ON public.bet_recommendations USING btree (game_odd_id);


--
-- Name: index_bet_recommendations_on_prediction_game_odd_bet_type; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_bet_recommendations_on_prediction_game_odd_bet_type ON public.bet_recommendations USING btree (prediction_id, game_odd_id, bet_type);


--
-- Name: index_bet_recommendations_on_prediction_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bet_recommendations_on_prediction_id ON public.bet_recommendations USING btree (prediction_id);


--
-- Name: index_bet_recommendations_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bet_recommendations_on_ratings_config_version_id ON public.bet_recommendations USING btree (ratings_config_version_id);


--
-- Name: index_bookmaker_odds_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_bookmaker_odds_on_game_id ON public.bookmaker_odds USING btree (game_id);


--
-- Name: index_cbbd_review_captures_on_cbbd_review_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_review_captures_on_cbbd_review_run_id ON public.cbbd_review_captures USING btree (cbbd_review_run_id);


--
-- Name: index_cbbd_review_comparisons_on_cbbd_review_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_review_comparisons_on_cbbd_review_run_id ON public.cbbd_review_comparisons USING btree (cbbd_review_run_id);


--
-- Name: index_cbbd_review_comparisons_on_identity_mapping_decision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_review_comparisons_on_identity_mapping_decision_id ON public.cbbd_review_comparisons USING btree (identity_mapping_decision_id);


--
-- Name: index_cbbd_review_runs_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_review_runs_on_season_id ON public.cbbd_review_runs USING btree (season_id);


--
-- Name: index_cbbd_sync_runs_on_future_acquisition_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_sync_runs_on_future_acquisition_id ON public.cbbd_sync_runs USING btree (future_acquisition_id);


--
-- Name: index_cbbd_sync_runs_on_past_acquisition_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_sync_runs_on_past_acquisition_id ON public.cbbd_sync_runs USING btree (past_acquisition_id);


--
-- Name: index_cbbd_sync_runs_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_sync_runs_on_ratings_config_version_id ON public.cbbd_sync_runs USING btree (ratings_config_version_id);


--
-- Name: index_cbbd_sync_runs_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_cbbd_sync_runs_on_season_id ON public.cbbd_sync_runs USING btree (season_id);


--
-- Name: index_cbbd_sync_runs_on_season_id_and_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_cbbd_sync_runs_on_season_id_and_bucket ON public.cbbd_sync_runs USING btree (season_id, bucket);


--
-- Name: index_coaching_changes_on_effective_year_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coaching_changes_on_effective_year_and_status ON public.coaching_changes USING btree (effective_year, status);


--
-- Name: index_coaching_changes_on_previous_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coaching_changes_on_previous_team_id ON public.coaching_changes USING btree (previous_team_id);


--
-- Name: index_coaching_changes_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_coaching_changes_on_team_id ON public.coaching_changes USING btree (team_id);


--
-- Name: index_coaching_reviews_on_year; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_coaching_reviews_on_year ON public.coaching_reviews USING btree (year);


--
-- Name: index_conference_external_identities_on_conference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conference_external_identities_on_conference_id ON public.conference_external_identities USING btree (conference_id);


--
-- Name: index_conferences_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conferences_on_name ON public.conferences USING btree (name);


--
-- Name: index_conferences_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_conferences_on_slug ON public.conferences USING btree (slug);


--
-- Name: index_departure_acquisitions_on_departure_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_acquisitions_on_departure_batch_id ON public.departure_acquisitions USING btree (departure_batch_id);


--
-- Name: index_departure_acquisitions_on_predecessor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_acquisitions_on_predecessor_id ON public.departure_acquisitions USING btree (predecessor_id);


--
-- Name: index_departure_approvals_on_departure_validation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_departure_approvals_on_departure_validation_id ON public.departure_approvals USING btree (departure_validation_id);


--
-- Name: index_departure_approvals_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_approvals_on_user_id ON public.departure_approvals USING btree (user_id);


--
-- Name: index_departure_batches_on_predecessor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_batches_on_predecessor_id ON public.departure_batches USING btree (predecessor_id);


--
-- Name: index_departure_batches_on_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_batches_on_revision_id ON public.departure_batches USING btree (revision_id);


--
-- Name: index_departure_batches_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_batches_on_season_id ON public.departure_batches USING btree (season_id);


--
-- Name: index_departure_dataset_normalizations_on_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_departure_dataset_normalizations_on_identity ON public.departure_dataset_normalizations USING btree (identity);


--
-- Name: index_departure_proposals_on_departure_validation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_proposals_on_departure_validation_id ON public.departure_proposals USING btree (departure_validation_id);


--
-- Name: index_departure_proposals_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_proposals_on_team_id ON public.departure_proposals USING btree (team_id);


--
-- Name: index_departure_source_captures_on_sha256; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_departure_source_captures_on_sha256 ON public.departure_source_captures USING btree (sha256);


--
-- Name: index_departure_source_normalizations_on_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_departure_source_normalizations_on_identity ON public.departure_source_normalizations USING btree (identity);


--
-- Name: index_departure_validations_on_departure_acquisition_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_validations_on_departure_acquisition_id ON public.departure_validations USING btree (departure_acquisition_id);


--
-- Name: index_departure_validations_on_departure_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_validations_on_departure_batch_id ON public.departure_validations USING btree (departure_batch_id);


--
-- Name: index_departure_validations_on_offseason_input_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_departure_validations_on_offseason_input_revision_id ON public.departure_validations USING btree (offseason_input_revision_id);


--
-- Name: index_game_external_identities_on_active_provider_game; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_external_identities_on_active_provider_game ON public.game_external_identities USING btree (provider, game_id) WHERE (superseded_at IS NULL);


--
-- Name: index_game_external_identities_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_external_identities_on_game_id ON public.game_external_identities USING btree (game_id);


--
-- Name: index_game_external_identities_on_provider_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_external_identities_on_provider_and_external_id ON public.game_external_identities USING btree (provider, external_id);


--
-- Name: index_game_observations_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_observations_on_game_id ON public.game_observations USING btree (game_id);


--
-- Name: index_game_observations_on_game_id_and_accepted_and_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_observations_on_game_id_and_accepted_and_id ON public.game_observations USING btree (game_id, accepted, id);


--
-- Name: index_game_observations_on_provider_and_external_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_observations_on_provider_and_external_game_id ON public.game_observations USING btree (provider, external_game_id);


--
-- Name: index_game_observations_on_scoring_review_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_observations_on_scoring_review_id ON public.game_observations USING btree (scoring_review_id);


--
-- Name: index_game_odds_on_game_id_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_odds_on_game_id_unique ON public.game_odds USING btree (game_id);


--
-- Name: index_game_scoring_reviews_on_reviewed_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_scoring_reviews_on_reviewed_by_id ON public.game_scoring_reviews USING btree (reviewed_by_id);


--
-- Name: index_game_scoring_reviews_on_schedule_refresh_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_scoring_reviews_on_schedule_refresh_run_id ON public.game_scoring_reviews USING btree (schedule_refresh_run_id);


--
-- Name: index_game_scoring_reviews_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_scoring_reviews_on_season_id ON public.game_scoring_reviews USING btree (season_id);


--
-- Name: index_game_scoring_reviews_on_source_fingerprint; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_scoring_reviews_on_source_fingerprint ON public.game_scoring_reviews USING btree (source_fingerprint);


--
-- Name: index_game_scoring_reviews_on_source_observation_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_scoring_reviews_on_source_observation_id ON public.game_scoring_reviews USING btree (source_observation_id);


--
-- Name: index_game_sync_dates_on_provider_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_game_sync_dates_on_provider_scope ON public.game_sync_dates USING btree (season_id, schedule_date, provider, contract_version, semantic_profile, adapter_revision);


--
-- Name: index_game_sync_dates_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_game_sync_dates_on_season_id ON public.game_sync_dates USING btree (season_id);


--
-- Name: index_games_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_season_id ON public.games USING btree (season_id);


--
-- Name: index_games_on_teams_and_start_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_teams_and_start_time ON public.games USING btree (home_team_name, away_team_name, start_time);


--
-- Name: index_games_on_url; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_url ON public.games USING btree (url);


--
-- Name: index_games_on_venue_confidence; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_venue_confidence ON public.games USING btree (venue_confidence);


--
-- Name: index_games_on_venue_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_games_on_venue_type ON public.games USING btree (venue_type);


--
-- Name: index_good_job_executions_on_active_job_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_job_executions_on_active_job_id_and_created_at ON public.good_job_executions USING btree (active_job_id, created_at);


--
-- Name: index_good_job_executions_on_process_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_job_executions_on_process_id_and_created_at ON public.good_job_executions USING btree (process_id, created_at);


--
-- Name: index_good_job_jobs_for_candidate_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_job_jobs_for_candidate_lookup ON public.good_jobs USING btree (priority, created_at) WHERE (finished_at IS NULL);


--
-- Name: index_good_job_settings_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_good_job_settings_on_key ON public.good_job_settings USING btree (key);


--
-- Name: index_good_jobs_jobs_on_finished_at_only; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_jobs_on_finished_at_only ON public.good_jobs USING btree (finished_at) WHERE (finished_at IS NOT NULL);


--
-- Name: index_good_jobs_jobs_on_priority_created_at_when_unfinished; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_jobs_on_priority_created_at_when_unfinished ON public.good_jobs USING btree (priority DESC NULLS LAST, created_at) WHERE (finished_at IS NULL);


--
-- Name: index_good_jobs_on_active_job_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_active_job_id_and_created_at ON public.good_jobs USING btree (active_job_id, created_at);


--
-- Name: index_good_jobs_on_batch_callback_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_batch_callback_id ON public.good_jobs USING btree (batch_callback_id) WHERE (batch_callback_id IS NOT NULL);


--
-- Name: index_good_jobs_on_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_batch_id ON public.good_jobs USING btree (batch_id) WHERE (batch_id IS NOT NULL);


--
-- Name: index_good_jobs_on_concurrency_key_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_concurrency_key_and_created_at ON public.good_jobs USING btree (concurrency_key, created_at);


--
-- Name: index_good_jobs_on_concurrency_key_when_unfinished; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_concurrency_key_when_unfinished ON public.good_jobs USING btree (concurrency_key) WHERE (finished_at IS NULL);


--
-- Name: index_good_jobs_on_cron_key_and_created_at_cond; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_cron_key_and_created_at_cond ON public.good_jobs USING btree (cron_key, created_at) WHERE (cron_key IS NOT NULL);


--
-- Name: index_good_jobs_on_cron_key_and_cron_at_cond; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_good_jobs_on_cron_key_and_cron_at_cond ON public.good_jobs USING btree (cron_key, cron_at) WHERE (cron_key IS NOT NULL);


--
-- Name: index_good_jobs_on_job_class; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_job_class ON public.good_jobs USING btree (job_class);


--
-- Name: index_good_jobs_on_labels; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_labels ON public.good_jobs USING gin (labels) WHERE (labels IS NOT NULL);


--
-- Name: index_good_jobs_on_locked_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_locked_by_id ON public.good_jobs USING btree (locked_by_id) WHERE (locked_by_id IS NOT NULL);


--
-- Name: index_good_jobs_on_priority_scheduled_at_unfinished_unlocked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_priority_scheduled_at_unfinished_unlocked ON public.good_jobs USING btree (priority, scheduled_at) WHERE ((finished_at IS NULL) AND (locked_by_id IS NULL));


--
-- Name: index_good_jobs_on_queue_name_and_scheduled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_queue_name_and_scheduled_at ON public.good_jobs USING btree (queue_name, scheduled_at) WHERE (finished_at IS NULL);


--
-- Name: index_good_jobs_on_scheduled_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_good_jobs_on_scheduled_at ON public.good_jobs USING btree (scheduled_at) WHERE (finished_at IS NULL);


--
-- Name: index_identity_mapping_decisions_on_request_digest; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_identity_mapping_decisions_on_request_digest ON public.identity_mapping_decisions USING btree (request_digest);


--
-- Name: index_offseason_input_revisions_on_predecessor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_offseason_input_revisions_on_predecessor_id ON public.offseason_input_revisions USING btree (predecessor_id);


--
-- Name: index_offseason_input_revisions_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_offseason_input_revisions_on_season_id ON public.offseason_input_revisions USING btree (season_id);


--
-- Name: index_offseason_readiness_reviews_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_offseason_readiness_reviews_on_ratings_config_version_id ON public.offseason_readiness_reviews USING btree (ratings_config_version_id);


--
-- Name: index_offseason_readiness_reviews_on_reviewer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_offseason_readiness_reviews_on_reviewer_id ON public.offseason_readiness_reviews USING btree (reviewer_id);


--
-- Name: index_offseason_readiness_reviews_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_offseason_readiness_reviews_on_season_id ON public.offseason_readiness_reviews USING btree (season_id);


--
-- Name: index_offseason_revisions_identity; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_offseason_revisions_identity ON public.offseason_input_revisions USING btree (season_id, kind, input_hash);


--
-- Name: index_offseason_revisions_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_offseason_revisions_version ON public.offseason_input_revisions USING btree (season_id, kind, version);


--
-- Name: index_one_accepted_observation_per_scoring_review; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_one_accepted_observation_per_scoring_review ON public.game_observations USING btree (scoring_review_id) WHERE (accepted = true);


--
-- Name: index_predictions_on_away_team_snapshot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_predictions_on_away_team_snapshot_id ON public.predictions USING btree (away_team_snapshot_id);


--
-- Name: index_predictions_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_predictions_on_game_id ON public.predictions USING btree (game_id);


--
-- Name: index_predictions_on_game_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_predictions_on_game_id_and_created_at ON public.predictions USING btree (game_id, created_at);


--
-- Name: index_predictions_on_home_team_snapshot_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_predictions_on_home_team_snapshot_id ON public.predictions USING btree (home_team_snapshot_id);


--
-- Name: index_predictions_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_predictions_on_ratings_config_version_id ON public.predictions USING btree (ratings_config_version_id);


--
-- Name: index_predictions_on_revision; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_predictions_on_revision ON public.predictions USING btree (game_id, ratings_config_version_id, revision_key);


--
-- Name: index_preseason_priors_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_preseason_priors_on_ratings_config_version_id ON public.preseason_priors USING btree (ratings_config_version_id);


--
-- Name: index_preseason_priors_on_team_season_and_config; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_preseason_priors_on_team_season_and_config ON public.preseason_priors USING btree (team_season_id, ratings_config_version_id);


--
-- Name: index_preseason_priors_on_team_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_preseason_priors_on_team_season_id ON public.preseason_priors USING btree (team_season_id);


--
-- Name: index_preseason_publications_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_preseason_publications_on_ratings_config_version_id ON public.preseason_publications USING btree (ratings_config_version_id);


--
-- Name: index_preseason_publications_on_reviewer_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_preseason_publications_on_reviewer_id ON public.preseason_publications USING btree (reviewer_id);


--
-- Name: index_preseason_publications_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_preseason_publications_on_season_id ON public.preseason_publications USING btree (season_id);


--
-- Name: index_ratings_config_versions_on_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ratings_config_versions_on_current ON public.ratings_config_versions USING btree (current) WHERE (current IS TRUE);


--
-- Name: index_ratings_config_versions_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ratings_config_versions_on_name ON public.ratings_config_versions USING btree (name);


--
-- Name: index_recruiting_batches_on_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recruiting_batches_on_revision_id ON public.recruiting_batches USING btree (revision_id);


--
-- Name: index_recruiting_batches_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recruiting_batches_on_season_id ON public.recruiting_batches USING btree (season_id);


--
-- Name: index_recruiting_entries_on_recruiting_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recruiting_entries_on_recruiting_batch_id ON public.recruiting_entries USING btree (recruiting_batch_id);


--
-- Name: index_recruiting_entries_on_recruiting_batch_id_and_row_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_recruiting_entries_on_recruiting_batch_id_and_row_number ON public.recruiting_entries USING btree (recruiting_batch_id, row_number);


--
-- Name: index_recruiting_entries_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recruiting_entries_on_team_id ON public.recruiting_entries USING btree (team_id);


--
-- Name: index_schedule_deferrals_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedule_deferrals_on_requested_by_id ON public.schedule_deferrals USING btree (requested_by_id);


--
-- Name: index_schedule_deferrals_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedule_deferrals_on_season_id ON public.schedule_deferrals USING btree (season_id);


--
-- Name: index_schedule_refresh_runs_on_requested_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedule_refresh_runs_on_requested_by_id ON public.schedule_refresh_runs USING btree (requested_by_id);


--
-- Name: index_schedule_refresh_runs_on_retry_of_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_schedule_refresh_runs_on_retry_of_id ON public.schedule_refresh_runs USING btree (retry_of_id);


--
-- Name: index_schedule_refresh_runs_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_schedule_refresh_runs_on_season_id ON public.schedule_refresh_runs USING btree (season_id);


--
-- Name: index_seasons_on_current; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seasons_on_current ON public.seasons USING btree (current) WHERE (current IS TRUE);


--
-- Name: index_seasons_on_preseason_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seasons_on_preseason_revision_id ON public.seasons USING btree (preseason_revision_id);


--
-- Name: index_seasons_on_selected_preseason_model_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_seasons_on_selected_preseason_model_id ON public.seasons USING btree (selected_preseason_model_id);


--
-- Name: index_seasons_on_year; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_seasons_on_year ON public.seasons USING btree (year);


--
-- Name: index_team_aliases_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_aliases_on_team_id ON public.team_aliases USING btree (team_id);


--
-- Name: index_team_aliases_on_value_and_source; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_aliases_on_value_and_source ON public.team_aliases USING btree (value, source);


--
-- Name: index_team_conferences_on_conference_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_conferences_on_conference_id ON public.team_conferences USING btree (conference_id);


--
-- Name: index_team_conferences_on_end_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_conferences_on_end_season_id ON public.team_conferences USING btree (end_season_id);


--
-- Name: index_team_conferences_on_start_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_conferences_on_start_season_id ON public.team_conferences USING btree (start_season_id);


--
-- Name: index_team_conferences_on_team_and_start_season; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_conferences_on_team_and_start_season ON public.team_conferences USING btree (team_id, start_season_id);


--
-- Name: index_team_conferences_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_conferences_on_team_id ON public.team_conferences USING btree (team_id);


--
-- Name: index_team_external_identities_on_provider_and_external_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_external_identities_on_provider_and_external_id ON public.team_external_identities USING btree (provider, external_id);


--
-- Name: index_team_external_identities_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_external_identities_on_team_id ON public.team_external_identities USING btree (team_id);


--
-- Name: index_team_games_on_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_games_on_game_id ON public.team_games USING btree (game_id);


--
-- Name: index_team_games_on_game_id_and_home; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_games_on_game_id_and_home ON public.team_games USING btree (game_id, home);


--
-- Name: index_team_games_on_opponent_team_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_games_on_opponent_team_season_id ON public.team_games USING btree (opponent_team_season_id);


--
-- Name: index_team_games_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_games_on_team_id ON public.team_games USING btree (team_id);


--
-- Name: index_team_games_on_team_id_and_game_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_games_on_team_id_and_game_id ON public.team_games USING btree (team_id, game_id);


--
-- Name: index_team_games_on_team_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_games_on_team_season_id ON public.team_games USING btree (team_season_id);


--
-- Name: index_team_offseason_profiles_on_departure_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_offseason_profiles_on_departure_revision_id ON public.team_offseason_profiles USING btree (departure_revision_id);


--
-- Name: index_team_offseason_profiles_on_recruiting_revision_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_offseason_profiles_on_recruiting_revision_id ON public.team_offseason_profiles USING btree (recruiting_revision_id);


--
-- Name: index_team_offseason_profiles_on_team_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_offseason_profiles_on_team_season_id ON public.team_offseason_profiles USING btree (team_season_id);


--
-- Name: index_team_rating_snapshots_on_rating_and_snapshot_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_rating_and_snapshot_date ON public.team_rating_snapshots USING btree (rating, snapshot_date);


--
-- Name: index_team_rating_snapshots_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_ratings_config_version_id ON public.team_rating_snapshots USING btree (ratings_config_version_id);


--
-- Name: index_team_rating_snapshots_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_season_id ON public.team_rating_snapshots USING btree (season_id);


--
-- Name: index_team_rating_snapshots_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_team_id ON public.team_rating_snapshots USING btree (team_id);


--
-- Name: index_team_rating_snapshots_on_team_season_config_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_team_season_config_date ON public.team_rating_snapshots USING btree (team_season_id, ratings_config_version_id, snapshot_date);


--
-- Name: index_team_rating_snapshots_on_team_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_rating_snapshots_on_team_season_id ON public.team_rating_snapshots USING btree (team_season_id);


--
-- Name: index_team_seasons_on_preseason_prior_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_seasons_on_preseason_prior_id ON public.team_seasons USING btree (preseason_prior_id);


--
-- Name: index_team_seasons_on_ratings_config_version_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_seasons_on_ratings_config_version_id ON public.team_seasons USING btree (ratings_config_version_id);


--
-- Name: index_team_seasons_on_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_seasons_on_season_id ON public.team_seasons USING btree (season_id);


--
-- Name: index_team_seasons_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_seasons_on_team_id ON public.team_seasons USING btree (team_id);


--
-- Name: index_team_seasons_on_team_id_and_season_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_seasons_on_team_id_and_season_id ON public.team_seasons USING btree (team_id, season_id);


--
-- Name: index_teams_on_school; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_school ON public.teams USING btree (school);


--
-- Name: index_teams_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_slug ON public.teams USING btree (slug);


--
-- Name: index_teams_on_the_odds_api_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_the_odds_api_team_id ON public.teams USING btree (the_odds_api_team_id);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_reset_password_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_reset_password_token ON public.users USING btree (reset_password_token);


--
-- Name: unique_coaching_discovery_school; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_coaching_discovery_school ON public.coaching_changes USING btree (effective_year, discovery_school) WHERE (discovery_school IS NOT NULL);


--
-- Name: unique_confirmed_coaching_destination; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX unique_confirmed_coaching_destination ON public.coaching_changes USING btree (team_id, effective_year) WHERE ((status)::text = 'confirmed'::text);


--
-- Name: departure_approvals departure_approval_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_approval_immutable BEFORE DELETE OR UPDATE ON public.departure_approvals FOR EACH ROW EXECUTE FUNCTION public.departure_certificate_immutable();


--
-- Name: departure_acquisitions departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.departure_acquisitions FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: departure_batches departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.departure_batches FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: departure_capture_observations departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER DELETE OR UPDATE ON public.departure_capture_observations FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: departure_source_captures departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER DELETE OR UPDATE ON public.departure_source_captures FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: offseason_input_revisions departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.offseason_input_revisions FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: seasons departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.seasons FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: team_aliases departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.team_aliases FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: team_external_identities departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.team_external_identities FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: team_offseason_profiles departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.team_offseason_profiles FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: team_seasons departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.team_seasons FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: teams departure_dependency_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_dependency_changed AFTER INSERT OR DELETE OR UPDATE ON public.teams FOR EACH STATEMENT EXECUTE FUNCTION public.departure_dependency_changed();


--
-- Name: departure_dataset_normalizations departure_normalization_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_normalization_changed AFTER DELETE OR UPDATE ON public.departure_dataset_normalizations FOR EACH ROW EXECUTE FUNCTION public.departure_normalization_changed();


--
-- Name: departure_source_normalizations departure_normalization_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_normalization_changed AFTER DELETE OR UPDATE ON public.departure_source_normalizations FOR EACH ROW EXECUTE FUNCTION public.departure_normalization_changed();


--
-- Name: departure_dataset_rows departure_normalized_row_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_normalized_row_changed AFTER INSERT OR DELETE OR UPDATE ON public.departure_dataset_rows FOR EACH ROW EXECUTE FUNCTION public.departure_normalized_row_changed();


--
-- Name: departure_normalized_rows departure_normalized_row_changed; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_normalized_row_changed AFTER INSERT OR DELETE OR UPDATE ON public.departure_normalized_rows FOR EACH ROW EXECUTE FUNCTION public.departure_normalized_row_changed();


--
-- Name: departure_proposals departure_proposal_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_proposal_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.departure_proposals FOR EACH ROW EXECUTE FUNCTION public.departure_proposal_immutable();


--
-- Name: departure_validations departure_validation_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_validation_immutable BEFORE DELETE OR UPDATE ON public.departure_validations FOR EACH ROW EXECUTE FUNCTION public.departure_validation_immutable();


--
-- Name: departure_dataset_rows departure_verified_rows_immutable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER departure_verified_rows_immutable BEFORE INSERT OR DELETE OR UPDATE ON public.departure_dataset_rows FOR EACH ROW EXECUTE FUNCTION public.departure_verified_rows_immutable();


--
-- Name: team_seasons fk_rails_004bfc5e7d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_seasons
    ADD CONSTRAINT fk_rails_004bfc5e7d FOREIGN KEY (preseason_prior_id) REFERENCES public.preseason_priors(id);


--
-- Name: cbbd_review_comparisons fk_rails_017bbf62d2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_comparisons
    ADD CONSTRAINT fk_rails_017bbf62d2 FOREIGN KEY (cbbd_review_run_id) REFERENCES public.cbbd_review_runs(id);


--
-- Name: schedule_deferrals fk_rails_07b3c71c0d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_deferrals
    ADD CONSTRAINT fk_rails_07b3c71c0d FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: predictions fk_rails_09703da98b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT fk_rails_09703da98b FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: departure_dataset_rows fk_rails_0b4513bfd4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_dataset_rows
    ADD CONSTRAINT fk_rails_0b4513bfd4 FOREIGN KEY (departure_dataset_normalization_id) REFERENCES public.departure_dataset_normalizations(id);


--
-- Name: bet_recommendations fk_rails_0c1e0ad007; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations
    ADD CONSTRAINT fk_rails_0c1e0ad007 FOREIGN KEY (game_odd_id) REFERENCES public.game_odds(id);


--
-- Name: offseason_readiness_reviews fk_rails_0d4f804c96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_readiness_reviews
    ADD CONSTRAINT fk_rails_0d4f804c96 FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: coaching_changes fk_rails_0f120455bf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes
    ADD CONSTRAINT fk_rails_0f120455bf FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: recruiting_entries fk_rails_1031c79c2f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_entries
    ADD CONSTRAINT fk_rails_1031c79c2f FOREIGN KEY (recruiting_batch_id) REFERENCES public.recruiting_batches(id);


--
-- Name: cbbd_review_captures fk_rails_1c4ef0d60d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_captures
    ADD CONSTRAINT fk_rails_1c4ef0d60d FOREIGN KEY (cbbd_review_run_id) REFERENCES public.cbbd_review_runs(id);


--
-- Name: bet_recommendations fk_rails_1f224fffef; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations
    ADD CONSTRAINT fk_rails_1f224fffef FOREIGN KEY (prediction_id) REFERENCES public.predictions(id);


--
-- Name: cbbd_review_runs fk_rails_21f2377298; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_runs
    ADD CONSTRAINT fk_rails_21f2377298 FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: departure_approvals fk_rails_24f0d98485; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_approvals
    ADD CONSTRAINT fk_rails_24f0d98485 FOREIGN KEY (departure_validation_id) REFERENCES public.departure_validations(id);


--
-- Name: departure_approvals fk_rails_2c027b8f38; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_approvals
    ADD CONSTRAINT fk_rails_2c027b8f38 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: team_offseason_profiles fk_rails_2d38756d3b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_offseason_profiles
    ADD CONSTRAINT fk_rails_2d38756d3b FOREIGN KEY (recruiting_revision_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: departure_normalized_rows fk_rails_31af1d63f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_normalized_rows
    ADD CONSTRAINT fk_rails_31af1d63f7 FOREIGN KEY (departure_source_normalization_id) REFERENCES public.departure_source_normalizations(id);


--
-- Name: team_rating_snapshots fk_rails_327135e71f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots
    ADD CONSTRAINT fk_rails_327135e71f FOREIGN KEY (team_season_id) REFERENCES public.team_seasons(id);


--
-- Name: schedule_deferrals fk_rails_328cc2619e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_deferrals
    ADD CONSTRAINT fk_rails_328cc2619e FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: team_conferences fk_rails_33ca56b37b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences
    ADD CONSTRAINT fk_rails_33ca56b37b FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: recruiting_batches fk_rails_3c9dcffe9d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_batches
    ADD CONSTRAINT fk_rails_3c9dcffe9d FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: departure_acquisitions fk_rails_40ac26d1f3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_acquisitions
    ADD CONSTRAINT fk_rails_40ac26d1f3 FOREIGN KEY (predecessor_id) REFERENCES public.departure_acquisitions(id);


--
-- Name: departure_capture_observations fk_rails_4982deb02e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_capture_observations
    ADD CONSTRAINT fk_rails_4982deb02e FOREIGN KEY (departure_acquisition_id) REFERENCES public.departure_acquisitions(id);


--
-- Name: departure_capture_observations fk_rails_4e8d80dc96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_capture_observations
    ADD CONSTRAINT fk_rails_4e8d80dc96 FOREIGN KEY (departure_source_capture_id) REFERENCES public.departure_source_captures(id);


--
-- Name: seasons fk_rails_50e528fe96; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons
    ADD CONSTRAINT fk_rails_50e528fe96 FOREIGN KEY (preseason_revision_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: departure_acquisitions fk_rails_556deb360f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_acquisitions
    ADD CONSTRAINT fk_rails_556deb360f FOREIGN KEY (departure_batch_id) REFERENCES public.departure_batches(id);


--
-- Name: schedule_refresh_runs fk_rails_6565e24e28; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_refresh_runs
    ADD CONSTRAINT fk_rails_6565e24e28 FOREIGN KEY (requested_by_id) REFERENCES public.users(id);


--
-- Name: preseason_publications fk_rails_669141b242; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_publications
    ADD CONSTRAINT fk_rails_669141b242 FOREIGN KEY (reviewer_id) REFERENCES public.users(id);


--
-- Name: game_odds fk_rails_676b7769b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_odds
    ADD CONSTRAINT fk_rails_676b7769b8 FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: coaching_changes fk_rails_68326708be; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes
    ADD CONSTRAINT fk_rails_68326708be FOREIGN KEY (discovery_previous_team_id) REFERENCES public.teams(id);


--
-- Name: cbbd_sync_runs fk_rails_69eb1a88ea; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs
    ADD CONSTRAINT fk_rails_69eb1a88ea FOREIGN KEY (future_acquisition_id) REFERENCES public.cbbd_review_runs(id);


--
-- Name: bet_recommendations fk_rails_71c12acb10; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations
    ADD CONSTRAINT fk_rails_71c12acb10 FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: departure_proposals fk_rails_727884dc6d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_proposals
    ADD CONSTRAINT fk_rails_727884dc6d FOREIGN KEY (departure_validation_id) REFERENCES public.departure_validations(id);


--
-- Name: cbbd_sync_runs fk_rails_72f2b28e7b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs
    ADD CONSTRAINT fk_rails_72f2b28e7b FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: team_games fk_rails_737ab3f93a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_games
    ADD CONSTRAINT fk_rails_737ab3f93a FOREIGN KEY (opponent_team_season_id) REFERENCES public.team_seasons(id);


--
-- Name: departure_validations fk_rails_747bfeea14; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations
    ADD CONSTRAINT fk_rails_747bfeea14 FOREIGN KEY (offseason_input_revision_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: offseason_readiness_reviews fk_rails_75188d4f7d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_readiness_reviews
    ADD CONSTRAINT fk_rails_75188d4f7d FOREIGN KEY (reviewer_id) REFERENCES public.users(id);


--
-- Name: departure_source_normalizations fk_rails_7804c2d46c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_source_normalizations
    ADD CONSTRAINT fk_rails_7804c2d46c FOREIGN KEY (departure_source_capture_id) REFERENCES public.departure_source_captures(id);


--
-- Name: preseason_priors fk_rails_78b4792cd7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_priors
    ADD CONSTRAINT fk_rails_78b4792cd7 FOREIGN KEY (team_season_id) REFERENCES public.team_seasons(id);


--
-- Name: preseason_publications fk_rails_7a6d8a345e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_publications
    ADD CONSTRAINT fk_rails_7a6d8a345e FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: departure_validations fk_rails_7c3051f051; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations
    ADD CONSTRAINT fk_rails_7c3051f051 FOREIGN KEY (departure_dataset_normalization_id) REFERENCES public.departure_dataset_normalizations(id);


--
-- Name: game_sync_dates fk_rails_7d4def7b77; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_sync_dates
    ADD CONSTRAINT fk_rails_7d4def7b77 FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: predictions fk_rails_7e4ce1cbb7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT fk_rails_7e4ce1cbb7 FOREIGN KEY (away_team_snapshot_id) REFERENCES public.team_rating_snapshots(id);


--
-- Name: coaching_changes fk_rails_84d19cf8cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes
    ADD CONSTRAINT fk_rails_84d19cf8cd FOREIGN KEY (discovery_team_id) REFERENCES public.teams(id);


--
-- Name: bookmaker_odds fk_rails_8d5c63c372; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookmaker_odds
    ADD CONSTRAINT fk_rails_8d5c63c372 FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: preseason_publications fk_rails_8f78a7645a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_publications
    ADD CONSTRAINT fk_rails_8f78a7645a FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: team_external_identities fk_rails_94b206471e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_external_identities
    ADD CONSTRAINT fk_rails_94b206471e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: cbbd_review_runs fk_rails_9545386de3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_runs
    ADD CONSTRAINT fk_rails_9545386de3 FOREIGN KEY (active_comparison_id) REFERENCES public.cbbd_review_comparisons(id);


--
-- Name: recruiting_batches fk_rails_95882b86a2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_batches
    ADD CONSTRAINT fk_rails_95882b86a2 FOREIGN KEY (revision_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: team_aliases fk_rails_972cca2ae9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_aliases
    ADD CONSTRAINT fk_rails_972cca2ae9 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: recruiting_entries fk_rails_975855ee27; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recruiting_entries
    ADD CONSTRAINT fk_rails_975855ee27 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: game_external_identities fk_rails_9a77c631d9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_external_identities
    ADD CONSTRAINT fk_rails_9a77c631d9 FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: team_seasons fk_rails_9aa25d1777; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_seasons
    ADD CONSTRAINT fk_rails_9aa25d1777 FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: schedule_refresh_runs fk_rails_9ab8472d9a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_refresh_runs
    ADD CONSTRAINT fk_rails_9ab8472d9a FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: departure_batches fk_rails_9c7977dd3e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_batches
    ADD CONSTRAINT fk_rails_9c7977dd3e FOREIGN KEY (revision_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: team_conferences fk_rails_9c86903891; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences
    ADD CONSTRAINT fk_rails_9c86903891 FOREIGN KEY (end_season_id) REFERENCES public.seasons(id);


--
-- Name: game_observations fk_rails_9dcb1e33bb; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_observations
    ADD CONSTRAINT fk_rails_9dcb1e33bb FOREIGN KEY (scoring_review_id) REFERENCES public.game_scoring_reviews(id);


--
-- Name: team_rating_snapshots fk_rails_a1a3f2acd5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots
    ADD CONSTRAINT fk_rails_a1a3f2acd5 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: seasons fk_rails_a6d6d2ce27; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.seasons
    ADD CONSTRAINT fk_rails_a6d6d2ce27 FOREIGN KEY (selected_preseason_model_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: team_rating_snapshots fk_rails_a87cf21b03; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots
    ADD CONSTRAINT fk_rails_a87cf21b03 FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: departure_batches fk_rails_a9f3c5a008; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_batches
    ADD CONSTRAINT fk_rails_a9f3c5a008 FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: team_conferences fk_rails_aac49aa0da; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences
    ADD CONSTRAINT fk_rails_aac49aa0da FOREIGN KEY (conference_id) REFERENCES public.conferences(id);


--
-- Name: game_scoring_reviews fk_rails_adf90ccebf; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews
    ADD CONSTRAINT fk_rails_adf90ccebf FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: game_observations fk_rails_b3a12242ae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_observations
    ADD CONSTRAINT fk_rails_b3a12242ae FOREIGN KEY (game_id) REFERENCES public.games(id);


--
-- Name: offseason_readiness_reviews fk_rails_b3b5b547a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_readiness_reviews
    ADD CONSTRAINT fk_rails_b3b5b547a1 FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: team_rating_snapshots fk_rails_b466a2b4ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_rating_snapshots
    ADD CONSTRAINT fk_rails_b466a2b4ac FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: cbbd_review_comparisons fk_rails_b62d204664; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_review_comparisons
    ADD CONSTRAINT fk_rails_b62d204664 FOREIGN KEY (identity_mapping_decision_id) REFERENCES public.identity_mapping_decisions(id);


--
-- Name: cbbd_sync_runs fk_rails_bd65aa212d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs
    ADD CONSTRAINT fk_rails_bd65aa212d FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: cbbd_sync_runs fk_rails_bff17760ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cbbd_sync_runs
    ADD CONSTRAINT fk_rails_bff17760ac FOREIGN KEY (past_acquisition_id) REFERENCES public.cbbd_review_runs(id);


--
-- Name: team_conferences fk_rails_cb9e0e1eb2; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_conferences
    ADD CONSTRAINT fk_rails_cb9e0e1eb2 FOREIGN KEY (start_season_id) REFERENCES public.seasons(id);


--
-- Name: departure_proposals fk_rails_cc559f6fc9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_proposals
    ADD CONSTRAINT fk_rails_cc559f6fc9 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: game_scoring_reviews fk_rails_cd59fb06f3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews
    ADD CONSTRAINT fk_rails_cd59fb06f3 FOREIGN KEY (source_observation_id) REFERENCES public.game_observations(id);


--
-- Name: game_scoring_reviews fk_rails_d63d3ca8ff; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews
    ADD CONSTRAINT fk_rails_d63d3ca8ff FOREIGN KEY (schedule_refresh_run_id) REFERENCES public.schedule_refresh_runs(id);


--
-- Name: team_offseason_profiles fk_rails_e1f279c52a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_offseason_profiles
    ADD CONSTRAINT fk_rails_e1f279c52a FOREIGN KEY (departure_revision_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: departure_batches fk_rails_e2a8e0d0d6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_batches
    ADD CONSTRAINT fk_rails_e2a8e0d0d6 FOREIGN KEY (predecessor_id) REFERENCES public.departure_batches(id);


--
-- Name: game_scoring_reviews fk_rails_e2db0064c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.game_scoring_reviews
    ADD CONSTRAINT fk_rails_e2db0064c4 FOREIGN KEY (reviewed_by_id) REFERENCES public.users(id);


--
-- Name: schedule_refresh_runs fk_rails_e33e9012a0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_refresh_runs
    ADD CONSTRAINT fk_rails_e33e9012a0 FOREIGN KEY (retry_of_id) REFERENCES public.schedule_refresh_runs(id);


--
-- Name: offseason_input_revisions fk_rails_e37a454e5e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_input_revisions
    ADD CONSTRAINT fk_rails_e37a454e5e FOREIGN KEY (predecessor_id) REFERENCES public.offseason_input_revisions(id);


--
-- Name: offseason_input_revisions fk_rails_e950657113; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.offseason_input_revisions
    ADD CONSTRAINT fk_rails_e950657113 FOREIGN KEY (season_id) REFERENCES public.seasons(id);


--
-- Name: preseason_priors fk_rails_f06d755ca4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.preseason_priors
    ADD CONSTRAINT fk_rails_f06d755ca4 FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- Name: conference_external_identities fk_rails_f0ef183268; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.conference_external_identities
    ADD CONSTRAINT fk_rails_f0ef183268 FOREIGN KEY (conference_id) REFERENCES public.conferences(id);


--
-- Name: departure_validations fk_rails_f365606ede; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations
    ADD CONSTRAINT fk_rails_f365606ede FOREIGN KEY (departure_acquisition_id) REFERENCES public.departure_acquisitions(id);


--
-- Name: predictions fk_rails_f49bc6617f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.predictions
    ADD CONSTRAINT fk_rails_f49bc6617f FOREIGN KEY (home_team_snapshot_id) REFERENCES public.team_rating_snapshots(id);


--
-- Name: coaching_changes fk_rails_f8cd5b9491; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.coaching_changes
    ADD CONSTRAINT fk_rails_f8cd5b9491 FOREIGN KEY (previous_team_id) REFERENCES public.teams(id);


--
-- Name: departure_validations fk_rails_f95408e883; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.departure_validations
    ADD CONSTRAINT fk_rails_f95408e883 FOREIGN KEY (departure_batch_id) REFERENCES public.departure_batches(id);


--
-- Name: bet_recommendations fk_rails_fd2cde6a85; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bet_recommendations
    ADD CONSTRAINT fk_rails_fd2cde6a85 FOREIGN KEY (ratings_config_version_id) REFERENCES public.ratings_config_versions(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20261026020000'),
('20261026010000'),
('20261025040000'),
('20261024020000'),
('20261024010000'),
('20261022040000'),
('20261022030000'),
('20261022020000'),
('20261022010000'),
('20261021200000'),
('20261021150000'),
('20261021140000'),
('20261021130000'),
('20261021120000'),
('20261021010000'),
('20261021001000'),
('20261020000000'),
('20261017220000'),
('20261017010000'),
('20261017000000'),
('20261016230000'),
('20261016010000'),
('20261016000000'),
('20261014000000'),
('20261010163200'),
('20261010163100'),
('20261010163000'),
('20261010060000'),
('20261010050000'),
('20261010040000'),
('20261010030000'),
('20261010020000'),
('20261010010000'),
('20261009020000'),
('20261008180000'),
('20260622000100'),
('20260525193000'),
('20260525173000'),
('20260517000100'),
('20260513000100'),
('20260301052600'),
('20260301052500'),
('20260301052400'),
('20260228230105'),
('20260228230104'),
('20260228230103'),
('20260228230102'),
('20260228230101'),
('20250930015506'),
('20250901143700'),
('20250901143000'),
('20250713142057'),
('20250628192143'),
('20250628192136'),
('20250628192122'),
('20250628192117'),
('20250628184923'),
('20250608042707'),
('20250608041321'),
('20250607034959'),
('20250607031511'),
('20250607030159'),
('20250605134826'),
('20250519011042'),
('20250519010429'),
('20250518190953'),
('20250518182324'),
('20250518181718'),
('20250518022216'),
('20250518003428'),
('20250518003153'),
('20250514035512'),
('20250514032922'),
('20250513034726'),
('20250508234304'),
('20250504201525'),
('20250504200823'),
('20250504200421'),
('20250503030859'),
('20250428124337'),
('20250427132635'),
('20250426151303'),
('20250426150609'),
('20250423023631'),
('20250422123458'),
('20250419163447'),
('20250419021936'),
('20240209151600'),
('20240209025506'),
('20240202152208'),
('20240202031542'),
('20240202031237'),
('20240202020844'),
('20240201214527'),
('20240201212702'),
('20240201170226'),
('20240131142443'),
('20240130002010'),
('20240128185109'),
('20240127204108'),
('20240126193159'),
('20240126192726'),
('20240126191632'),
('20240126191627'),
('20240126191120'),
('20240126183618');

