CREATE TABLE IF NOT EXISTS ux_feedback (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id text,
  session_id text,
  feedback_type text NOT NULL,
  rating text NOT NULL,
  reason_tags text,
  comment text,
  run_id text,
  workflow_id text,
  message_id text,
  execution_status text,
  error_message text,
  ui_route text,
  status_clarity_score integer,
  output_usefulness_score integer,
  output_actionability_score integer,
  created_at timestamp DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS ux_feedback_created_at_idx ON ux_feedback(created_at);
CREATE INDEX IF NOT EXISTS ux_feedback_run_id_idx ON ux_feedback(run_id);
CREATE INDEX IF NOT EXISTS ux_feedback_session_id_idx ON ux_feedback(session_id);
CREATE INDEX IF NOT EXISTS ux_feedback_feedback_type_idx ON ux_feedback(feedback_type);
CREATE INDEX IF NOT EXISTS ux_feedback_rating_idx ON ux_feedback(rating);
