-- Migration 0012: Long-Term Memory (LTM) Schema
--
-- Creates the tables declared in frontend/shared/ltm-schema.ts. These tables
-- back BioMate's MemoryService (frontend/server/memory-repository.ts) — projects,
-- sessions, conversation messages, learned preferences, corrections, project
-- knowledge, workflows, episodes, procedures, conversation state facts, and
-- pending pipeline tasks.
--
-- The 2026-06-11 audit found `relation "projects" does not exist` on dev,
-- confirming the entire LTM backend was silently no-op'ing because no SQL
-- migration ever created these tables. This migration is fully idempotent
-- (CREATE TABLE IF NOT EXISTS / CREATE INDEX IF NOT EXISTS) and safe to re-run.

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================================
-- Table 1: ltm_users
-- ============================================================================
CREATE TABLE IF NOT EXISTS ltm_users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL UNIQUE,
  name text,
  expertise_level varchar(20) DEFAULT 'intermediate',
  research_domain varchar(100),
  affiliation text,
  preferred_communication_style varchar(20) DEFAULT 'balanced',
  workflow_generation_mode varchar(20) DEFAULT 'auto-accept',
  total_workflows integer DEFAULT 0,
  successful_workflows integer DEFAULT 0,
  created_at timestamp DEFAULT now(),
  last_active timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ltm_users_email_idx ON ltm_users (email);
CREATE INDEX IF NOT EXISTS ltm_users_last_active_idx ON ltm_users (last_active);

-- ============================================================================
-- Table 2: projects
-- ============================================================================
CREATE TABLE IF NOT EXISTS projects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES ltm_users(id) ON DELETE CASCADE,
  name varchar(255) NOT NULL,
  description text,
  research_goal text,
  instructions text,
  primary_domain varchar(100),
  organisms text[],
  tissue_types text[],
  conditions text[],
  data_modalities text[],
  status varchar(20) DEFAULT 'active',
  progress integer DEFAULT 0,
  storage_path text,
  category varchar(100),
  tags text[] DEFAULT '{}',
  created_at timestamp DEFAULT now(),
  updated_at timestamp DEFAULT now(),
  archived_at timestamp
);
CREATE INDEX IF NOT EXISTS projects_user_id_idx ON projects (user_id);
CREATE INDEX IF NOT EXISTS projects_status_idx ON projects (status);
CREATE INDEX IF NOT EXISTS projects_domain_idx ON projects (primary_domain);

-- ============================================================================
-- Table 3: sessions
-- ============================================================================
CREATE TABLE IF NOT EXISTS sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES ltm_users(id) ON DELETE CASCADE,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  title text,
  started_at timestamp DEFAULT now(),
  ended_at timestamp,
  duration_seconds integer,
  summary text,
  key_decisions jsonb,
  tools_discussed text[],
  workflows_created integer DEFAULT 0,
  workflows_executed integer DEFAULT 0,
  transcript_path text,
  message_count integer DEFAULT 0,
  total_tokens integer DEFAULT 0,
  conversation_state jsonb
);
CREATE INDEX IF NOT EXISTS sessions_user_id_idx ON sessions (user_id);
CREATE INDEX IF NOT EXISTS sessions_project_id_idx ON sessions (project_id);
CREATE INDEX IF NOT EXISTS sessions_started_at_idx ON sessions (started_at);

-- ============================================================================
-- Table 4: conversation_messages
-- ============================================================================
CREATE TABLE IF NOT EXISTS conversation_messages (
  id serial PRIMARY KEY,
  session_id uuid REFERENCES sessions(id) ON DELETE CASCADE,
  role varchar(20) NOT NULL,
  content text NOT NULL,
  tools_used jsonb,
  context_snapshot jsonb,
  token_count integer,
  created_at timestamp DEFAULT now(),
  thinking_content text,
  thinking_level varchar(20)
);
CREATE INDEX IF NOT EXISTS messages_session_id_idx ON conversation_messages (session_id);
CREATE INDEX IF NOT EXISTS messages_created_at_idx ON conversation_messages (created_at);

-- ============================================================================
-- Table 5: user_preferences
-- ============================================================================
CREATE TABLE IF NOT EXISTS user_preferences (
  id serial PRIMARY KEY,
  user_id uuid REFERENCES ltm_users(id) ON DELETE CASCADE,
  preference_type varchar(50) NOT NULL,
  context jsonb,
  preference_key varchar(255) NOT NULL,
  preference_value jsonb NOT NULL,
  learned_from varchar(50),
  confidence real DEFAULT 1.0,
  usage_count integer DEFAULT 1,
  created_at timestamp DEFAULT now(),
  last_used timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS preferences_user_id_idx ON user_preferences (user_id);
CREATE INDEX IF NOT EXISTS preferences_type_idx ON user_preferences (preference_type);

-- ============================================================================
-- Table 6: correction_log
-- ============================================================================
CREATE TABLE IF NOT EXISTS correction_log (
  id serial PRIMARY KEY,
  user_id uuid REFERENCES ltm_users(id) ON DELETE CASCADE,
  session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  suggested_approach jsonb NOT NULL,
  corrected_approach jsonb NOT NULL,
  workflow_context jsonb,
  user_explanation text,
  applied_to_future boolean DEFAULT false,
  created_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS corrections_user_id_idx ON correction_log (user_id);
CREATE INDEX IF NOT EXISTS corrections_created_at_idx ON correction_log (created_at);

-- ============================================================================
-- Table 7: project_knowledge
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_knowledge (
  id serial PRIMARY KEY,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  knowledge_type varchar(50) NOT NULL,
  title varchar(255),
  content text NOT NULL,
  related_workflows uuid[],
  related_sessions uuid[],
  source varchar(50),
  relevance_score real DEFAULT 1.0,
  created_at timestamp DEFAULT now(),
  updated_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS knowledge_project_id_idx ON project_knowledge (project_id);
CREATE INDEX IF NOT EXISTS knowledge_type_idx ON project_knowledge (knowledge_type);

-- ============================================================================
-- Table 8: workflows
-- ============================================================================
CREATE TABLE IF NOT EXISTS workflows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES ltm_users(id) ON DELETE CASCADE,
  project_id uuid REFERENCES projects(id) ON DELETE SET NULL,
  session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
  name varchar(255),
  description text,
  workflow_json jsonb NOT NULL,
  domain varchar(100),
  data_type varchar(100),
  analysis_goal text,
  status varchar(20) DEFAULT 'draft',
  galaxy_workflow_id varchar(255),
  execution_id varchar(255),
  execution_started_at timestamp,
  execution_completed_at timestamp,
  execution_duration_seconds integer,
  success boolean,
  error_message text,
  output_datasets uuid[],
  workflow_path text,
  created_at timestamp DEFAULT now(),
  updated_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS workflows_user_id_idx ON workflows (user_id);
CREATE INDEX IF NOT EXISTS workflows_project_id_idx ON workflows (project_id);
CREATE INDEX IF NOT EXISTS workflows_status_idx ON workflows (status);
CREATE INDEX IF NOT EXISTS workflows_created_at_idx ON workflows (created_at);

-- ============================================================================
-- Table 9: project_episodes
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_episodes (
  id serial PRIMARY KEY,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  session_id uuid REFERENCES sessions(id) ON DELETE SET NULL,
  user_query text NOT NULL,
  assistant_response text NOT NULL,
  user_intent text,
  tools_used jsonb,
  workflow_generated boolean DEFAULT false,
  workflow_id uuid REFERENCES workflows(id) ON DELETE SET NULL,
  parameters_set jsonb,
  outcome_success boolean,
  user_feedback integer,
  error_occurred boolean DEFAULT false,
  error_type varchar(100),
  error_message text,
  what_worked text[],
  what_failed text[],
  lessons_learned text[],
  alternative_approaches text[],
  importance_score real DEFAULT 0.5,
  access_count integer DEFAULT 0,
  last_accessed timestamp DEFAULT now(),
  created_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS episodes_project_id_idx ON project_episodes (project_id);
CREATE INDEX IF NOT EXISTS episodes_session_id_idx ON project_episodes (session_id);
CREATE INDEX IF NOT EXISTS episodes_outcome_idx ON project_episodes (outcome_success);
CREATE INDEX IF NOT EXISTS episodes_importance_idx ON project_episodes (importance_score);

-- ============================================================================
-- Table 10: project_procedures
-- ============================================================================
CREATE TABLE IF NOT EXISTS project_procedures (
  id serial PRIMARY KEY,
  project_id uuid REFERENCES projects(id) ON DELETE CASCADE,
  name varchar(255) NOT NULL,
  trigger_pattern text NOT NULL,
  description text,
  steps jsonb NOT NULL,
  preconditions text[],
  postconditions text[],
  success_rate real DEFAULT 0.5,
  times_used integer DEFAULT 0,
  last_used timestamp,
  learned_from integer[],
  applicable_domains text[],
  created_at timestamp DEFAULT now(),
  updated_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS procedures_project_id_idx ON project_procedures (project_id);
CREATE INDEX IF NOT EXISTS procedures_success_rate_idx ON project_procedures (success_rate);

-- ============================================================================
-- Table 11: conversation_state_facts
-- ============================================================================
CREATE TABLE IF NOT EXISTS conversation_state_facts (
  id serial PRIMARY KEY,
  session_id uuid REFERENCES sessions(id) ON DELETE CASCADE,
  category varchar(50) NOT NULL,
  value text NOT NULL,
  confidence real DEFAULT 0.5,
  turn_index integer NOT NULL,
  superseded_by integer,
  source_type varchar(50),
  created_at timestamp DEFAULT now()
);
CREATE INDEX IF NOT EXISTS state_facts_session_id_idx ON conversation_state_facts (session_id);
CREATE INDEX IF NOT EXISTS state_facts_category_idx ON conversation_state_facts (category);

-- ============================================================================
-- Table 12: pending_tasks
-- ============================================================================
CREATE TABLE IF NOT EXISTS pending_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  session_id text,
  parent_pipeline_id uuid,
  description text NOT NULL,
  task_type text,
  status text DEFAULT 'pending',
  depends_on uuid[] DEFAULT '{}',
  celery_task_id text,
  result_path text,
  error_message text,
  created_at timestamp DEFAULT now(),
  started_at timestamp,
  completed_at timestamp
);
