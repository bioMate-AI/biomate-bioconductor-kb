CREATE TABLE IF NOT EXISTS telemetry_events (
  id varchar PRIMARY KEY DEFAULT gen_random_uuid(),
  event text NOT NULL,
  timestamp timestamp NOT NULL,
  payload text,
  created_at timestamp DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS telemetry_events_event_idx ON telemetry_events(event);
CREATE INDEX IF NOT EXISTS telemetry_events_created_at_idx ON telemetry_events(created_at);
CREATE INDEX IF NOT EXISTS telemetry_events_timestamp_idx ON telemetry_events(timestamp);
