-- Migration 004: Behavioral User Profile (Replaces static assumptions)
-- Purpose: Track actual user behavior instead of self-reported preferences
-- Date: November 3, 2025

-- DROP old assumption-based tables
DROP TABLE IF EXISTS user_profiles;
DROP TABLE IF EXISTS search_sessions;
DROP TABLE IF EXISTS search_feedback;

-- User Account (minimal identity info only)
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,
    name TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    last_login TEXT
);

-- Interaction History (track everything user does)
CREATE TABLE IF NOT EXISTS user_interactions (
    interaction_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,

    -- What happened
    interaction_type TEXT NOT NULL,  -- 'search', 'tool_select', 'file_upload', 'workflow_run', 'parameter_edit'

    -- Context at time of interaction
    query TEXT,  -- Search query if applicable
    detected_context TEXT,  -- JSON: what we detected from data/query
    -- Example: {"data_type": "mzML", "inferred_method": "DIA", "confidence": 0.7}

    -- User's action
    selected_tool_id TEXT,  -- Tool they chose (if applicable)
    selected_rank INTEGER,  -- Was it 1st, 2nd, 3rd result?

    -- File information (if file upload)
    file_name TEXT,
    file_extension TEXT,
    file_metadata TEXT,  -- JSON: extracted metadata from file
    -- Example: {"cv_params": ["MS:1003114"], "scan_type": "DIA"}

    -- Workflow information
    workflow_id TEXT,
    workflow_success INTEGER,  -- 0=failed, 1=success, NULL=unknown

    -- User feedback
    user_clicked INTEGER DEFAULT 0,  -- Did they click this result?
    user_kept INTEGER,  -- Did they keep this choice? (0=removed, 1=kept, NULL=unknown)
    user_feedback_rating INTEGER,  -- Optional: 1-5 star rating
    user_feedback_comment TEXT,

    -- Timestamp
    timestamp TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Indexes for fast queries
CREATE INDEX IF NOT EXISTS idx_interactions_user ON user_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_interactions_type ON user_interactions(interaction_type);
CREATE INDEX IF NOT EXISTS idx_interactions_timestamp ON user_interactions(timestamp);
CREATE INDEX IF NOT EXISTS idx_interactions_tool ON user_interactions(selected_tool_id);

-- Inferred User Patterns (what we learn from behavior)
CREATE TABLE IF NOT EXISTS user_patterns (
    pattern_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,

    -- Pattern Type
    pattern_type TEXT NOT NULL,  -- 'domain_preference', 'tool_preference', 'complexity_level', 'data_type_pattern'

    -- Pattern Details (JSON)
    pattern_data TEXT NOT NULL,
    -- Examples:
    -- {"domain": "proteomics", "frequency": 0.85, "last_30_days": 17}
    -- {"prefers_tool": "MSstats", "over": "Limma", "when": "DIA data", "confidence": 0.92}
    -- {"complexity_preference": "simple", "evidence": "always_selects_top_result", "confidence": 0.65}
    -- {"data_type": "DIA", "detection_success_rate": 0.95, "total_files": 23}

    -- Confidence & Evidence
    confidence REAL NOT NULL,  -- 0.0 to 1.0
    evidence_count INTEGER NOT NULL,  -- How many interactions support this pattern

    -- Timestamps
    first_observed TEXT,
    last_observed TEXT,
    last_updated TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_patterns_user ON user_patterns(user_id);
CREATE INDEX IF NOT EXISTS idx_patterns_type ON user_patterns(pattern_type);
CREATE INDEX IF NOT EXISTS idx_patterns_confidence ON user_patterns(confidence);

-- Data Type Detection History (learn how to detect data types)
CREATE TABLE IF NOT EXISTS data_type_detections (
    detection_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,

    -- File Info
    file_name TEXT,
    file_extension TEXT,
    file_metadata TEXT,  -- JSON: extracted metadata

    -- Our Detection
    detected_type TEXT,  -- What we guessed
    detection_confidence REAL,  -- How confident we were
    detection_method TEXT,  -- How we detected: 'metadata', 'extension', 'content_scan', 'user_history'

    -- User Confirmation
    user_confirmed_type TEXT,  -- What user said it actually is
    was_correct INTEGER,  -- 0=wrong, 1=correct, NULL=user didn't confirm

    -- Learning
    timestamp TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_detections_user ON data_type_detections(user_id);
CREATE INDEX IF NOT EXISTS idx_detections_correct ON data_type_detections(was_correct);

-- Context Inference Log (how we inferred context for each search)
CREATE TABLE IF NOT EXISTS context_inferences (
    inference_id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    interaction_id INTEGER,  -- Links to user_interactions

    -- Input signals
    query_text TEXT,
    uploaded_file_info TEXT,  -- JSON
    user_history_summary TEXT,  -- JSON: summary of past behavior

    -- Inferred context
    inferred_domain TEXT,  -- proteomics, genomics, etc.
    inferred_data_type TEXT,  -- DIA, RNA-seq, etc.
    inferred_complexity_need TEXT,  -- simple, intermediate, advanced

    -- Confidence for each inference
    domain_confidence REAL,
    data_type_confidence REAL,
    complexity_confidence REAL,

    -- How we inferred
    inference_method TEXT,  -- 'query_keywords', 'file_metadata', 'user_history', 'combined'
    inference_details TEXT,  -- JSON: detailed reasoning

    -- Was it helpful?
    user_accepted INTEGER,  -- Did user work with our suggestions? (0=changed everything, 1=accepted)

    timestamp TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    FOREIGN KEY (interaction_id) REFERENCES user_interactions(interaction_id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_context_user ON context_inferences(user_id);
CREATE INDEX IF NOT EXISTS idx_context_accepted ON context_inferences(user_accepted);

-- Sample data for testing
INSERT OR IGNORE INTO users (user_id, email, name)
VALUES ('user-001', 'test@example.com', 'Test User');

-- Simulate some behavioral history
INSERT INTO user_interactions (user_id, interaction_type, query, selected_tool_id, selected_rank, user_clicked, user_kept, detected_context)
VALUES
    ('user-001', 'search', 'differential expression', 'MSstats', 1, 1, 1, '{"inferred_domain": "proteomics", "confidence": 0.8}'),
    ('user-001', 'search', 'protein quantification', 'MSstats', 1, 1, 1, '{"inferred_domain": "proteomics", "confidence": 0.9}'),
    ('user-001', 'file_upload', NULL, NULL, NULL, NULL, NULL, '{"file_type": "mzML", "detected_method": "DIA", "confidence": 0.75}'),
    ('user-001', 'search', 'differential expression', 'MSstats', 1, 1, 1, '{"inferred_domain": "proteomics", "confidence": 0.95}');

-- Infer a pattern from this behavior
INSERT INTO user_patterns (user_id, pattern_type, pattern_data, confidence, evidence_count, first_observed, last_observed)
VALUES (
    'user-001',
    'domain_preference',
    '{"domain": "proteomics", "frequency": 1.0, "total_interactions": 4, "recent_trend": "consistent"}',
    0.95,
    4,
    datetime('now', '-7 days'),
    datetime('now')
);

INSERT INTO user_patterns (user_id, pattern_type, pattern_data, confidence, evidence_count, first_observed, last_observed)
VALUES (
    'user-001',
    'tool_preference',
    '{"prefers_tool": "MSstats", "for_task": "differential expression", "selection_rate": 1.0}',
    0.90,
    3,
    datetime('now', '-7 days'),
    datetime('now')
);

-- Record migration
INSERT OR IGNORE INTO schema_migrations (migration_name, applied_at, status)
VALUES ('004_behavioral_user_profile', datetime('now'), 'applied');
