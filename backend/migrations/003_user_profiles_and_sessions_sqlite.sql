-- Migration 003: User Profiles and Session Context (SQLite)
-- Purpose: Store user preferences and search session context for enhanced tool search
-- Date: November 3, 2025

-- Enable foreign keys in SQLite
PRAGMA foreign_keys = ON;

-- User Profiles Table
CREATE TABLE IF NOT EXISTS user_profiles (
    user_id TEXT PRIMARY KEY,
    email TEXT UNIQUE NOT NULL,

    -- Research Preferences
    research_domain TEXT,  -- proteomics, genomics, transcriptomics, metabolomics
    expertise_level TEXT,  -- beginner, intermediate, expert
    default_data_type TEXT,  -- DIA-LCMS, DDA-LCMS, RNA-seq, WGS, etc.
    organism TEXT,  -- human, mouse, yeast, etc.

    -- Data Requirements (for enhanced search)
    typical_num_samples INTEGER,
    typical_num_replicates INTEGER,

    -- Additional Preferences (JSON for flexibility)
    preferences TEXT DEFAULT '{}',

    -- Metadata
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    last_login TEXT
);

-- Index for fast email lookup
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON user_profiles(email);

-- Index for research domain filtering
CREATE INDEX IF NOT EXISTS idx_user_profiles_domain ON user_profiles(research_domain);

-- Search Sessions Table
CREATE TABLE IF NOT EXISTS search_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,

    -- Session Context (auto-populated from user profile, can be overridden)
    context TEXT NOT NULL DEFAULT '{}',

    -- Session Metadata
    created_at TEXT DEFAULT (datetime('now')),
    last_active TEXT DEFAULT (datetime('now')),
    expires_at TEXT,
    is_active INTEGER DEFAULT 1,

    FOREIGN KEY (user_id) REFERENCES user_profiles(user_id) ON DELETE CASCADE
);

-- Index for fast user lookup
CREATE INDEX IF NOT EXISTS idx_search_sessions_user ON search_sessions(user_id);

-- Index for active sessions
CREATE INDEX IF NOT EXISTS idx_search_sessions_active ON search_sessions(is_active, last_active);

-- Search Feedback Table
CREATE TABLE IF NOT EXISTS search_feedback (
    feedback_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT,
    user_id TEXT,

    -- Search Query Info
    query TEXT NOT NULL,
    search_context TEXT,  -- Context used for this search (JSON)

    -- Tool Selection
    tool_id TEXT,  -- Which tool was selected
    tool_rank INTEGER,  -- Position in search results (1 = top result)
    scientific_score REAL,  -- Scientific relevance score
    combined_score REAL,  -- Final combined score

    -- User Feedback
    was_selected INTEGER DEFAULT 0,  -- Did user select this tool? (0=no, 1=yes)
    was_helpful INTEGER,  -- Explicit feedback (NULL=no feedback, 0=not helpful, 1=helpful)
    feedback_comment TEXT,

    -- Relevance Explanation
    relevance_explanation TEXT,  -- Why tool was recommended
    had_nfcore_badge INTEGER DEFAULT 0,  -- Did tool have nf-core validation? (0=no, 1=yes)

    -- Metadata
    created_at TEXT DEFAULT (datetime('now')),

    FOREIGN KEY (session_id) REFERENCES search_sessions(session_id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES user_profiles(user_id) ON DELETE CASCADE
);

-- Indexes for analysis
CREATE INDEX IF NOT EXISTS idx_search_feedback_session ON search_feedback(session_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_user ON search_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_tool ON search_feedback(tool_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_helpful ON search_feedback(was_helpful);

-- Trigger to auto-update updated_at on user_profiles
CREATE TRIGGER IF NOT EXISTS update_user_profiles_updated_at
AFTER UPDATE ON user_profiles
FOR EACH ROW
BEGIN
    UPDATE user_profiles SET updated_at = datetime('now') WHERE user_id = NEW.user_id;
END;

-- Trigger to auto-update last_active on search_sessions
CREATE TRIGGER IF NOT EXISTS update_search_sessions_last_active
AFTER UPDATE ON search_sessions
FOR EACH ROW
BEGIN
    UPDATE search_sessions SET last_active = datetime('now') WHERE session_id = NEW.session_id;
END;

-- Sample data for testing
INSERT OR IGNORE INTO user_profiles (user_id, email, research_domain, expertise_level, default_data_type, organism, typical_num_samples, typical_num_replicates)
VALUES
    ('user-001', 'test@example.com', 'proteomics', 'intermediate', 'DIA-LCMS', 'human', 6, 3),
    ('user-002', 'genomics@example.com', 'genomics', 'expert', 'WGS', 'mouse', 12, 4),
    ('user-003', 'beginner@example.com', 'proteomics', 'beginner', 'DDA-LCMS', 'yeast', 3, 2);

-- Create initial session for test user
INSERT OR IGNORE INTO search_sessions (session_id, user_id, context, expires_at)
VALUES (
    'session-test-001',
    'user-001',
    '{"research_domain": "proteomics", "expertise_level": "intermediate", "data_type": "DIA-LCMS", "num_samples": 6, "num_replicates": 3, "organism": "human"}',
    datetime('now', '+7 days')
);

-- Record migration
INSERT OR IGNORE INTO schema_migrations (migration_name, applied_at, status)
VALUES ('003_user_profiles_and_sessions', datetime('now'), 'applied');
