-- Migration 003: User Profiles and Session Context
-- Purpose: Store user preferences and search session context for enhanced tool search
-- Date: November 3, 2025

-- User Profiles Table
-- Stores persistent user preferences for research domain, expertise level, etc.
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

    -- Additional Preferences (JSONB for flexibility)
    preferences JSONB DEFAULT '{}',

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP
);

-- Index for fast email lookup
CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON user_profiles(email);

-- Index for research domain filtering
CREATE INDEX IF NOT EXISTS idx_user_profiles_domain ON user_profiles(research_domain);

-- Search Sessions Table
-- Tracks active search sessions for context persistence across queries
CREATE TABLE IF NOT EXISTS search_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT REFERENCES user_profiles(user_id) ON DELETE CASCADE,

    -- Session Context (auto-populated from user profile, can be overridden)
    context JSONB NOT NULL DEFAULT '{}',
    -- Example context:
    -- {
    --   "research_domain": "proteomics",
    --   "expertise_level": "intermediate",
    --   "data_type": "DIA-LCMS",
    --   "num_samples": 6,
    --   "num_replicates": 3,
    --   "organism": "human"
    -- }

    -- Session Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_active TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);

-- Index for fast user lookup
CREATE INDEX IF NOT EXISTS idx_search_sessions_user ON search_sessions(user_id);

-- Index for active sessions
CREATE INDEX IF NOT EXISTS idx_search_sessions_active ON search_sessions(is_active, last_active);

-- Search Feedback Table
-- Tracks which tools users select and find helpful for ACE learning
CREATE TABLE IF NOT EXISTS search_feedback (
    feedback_id SERIAL PRIMARY KEY,
    session_id TEXT REFERENCES search_sessions(session_id) ON DELETE CASCADE,
    user_id TEXT REFERENCES user_profiles(user_id) ON DELETE CASCADE,

    -- Search Query Info
    query TEXT NOT NULL,
    search_context JSONB,  -- Context used for this search

    -- Tool Selection
    tool_id TEXT,  -- Which tool was selected
    tool_rank INTEGER,  -- Position in search results (1 = top result)
    scientific_score REAL,  -- Scientific relevance score
    combined_score REAL,  -- Final combined score

    -- User Feedback
    was_selected BOOLEAN DEFAULT FALSE,  -- Did user select this tool?
    was_helpful BOOLEAN,  -- Explicit feedback (nullable - null means no feedback yet)
    feedback_comment TEXT,

    -- Relevance Explanation
    relevance_explanation TEXT,  -- Why tool was recommended
    had_nfcore_badge BOOLEAN DEFAULT FALSE,  -- Did tool have nf-core validation?

    -- Metadata
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for analysis
CREATE INDEX IF NOT EXISTS idx_search_feedback_session ON search_feedback(session_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_user ON search_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_tool ON search_feedback(tool_id);
CREATE INDEX IF NOT EXISTS idx_search_feedback_helpful ON search_feedback(was_helpful);

-- Function to auto-update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for user_profiles
CREATE TRIGGER update_user_profiles_updated_at
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to auto-update last_active on search_sessions
CREATE OR REPLACE FUNCTION update_session_last_active()
RETURNS TRIGGER AS $$
BEGIN
    NEW.last_active = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for search_sessions
CREATE TRIGGER update_search_sessions_last_active
    BEFORE UPDATE ON search_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_session_last_active();

-- Sample data for testing
INSERT INTO user_profiles (user_id, email, research_domain, expertise_level, default_data_type, organism, typical_num_samples, typical_num_replicates)
VALUES
    ('user-001', 'test@example.com', 'proteomics', 'intermediate', 'DIA-LCMS', 'human', 6, 3),
    ('user-002', 'genomics@example.com', 'genomics', 'expert', 'WGS', 'mouse', 12, 4),
    ('user-003', 'beginner@example.com', 'proteomics', 'beginner', 'DDA-LCMS', 'yeast', 3, 2)
ON CONFLICT (user_id) DO NOTHING;

-- Create initial session for test user
INSERT INTO search_sessions (session_id, user_id, context, expires_at)
VALUES (
    'session-test-001',
    'user-001',
    '{"research_domain": "proteomics", "expertise_level": "intermediate", "data_type": "DIA-LCMS", "num_samples": 6, "num_replicates": 3, "organism": "human"}',
    CURRENT_TIMESTAMP + INTERVAL '7 days'
)
ON CONFLICT (session_id) DO NOTHING;

-- Comments for documentation
COMMENT ON TABLE user_profiles IS 'Stores persistent user preferences for research domain, expertise level, and typical data characteristics';
COMMENT ON TABLE search_sessions IS 'Tracks active search sessions with context that persists across multiple queries';
COMMENT ON TABLE search_feedback IS 'Collects user feedback on tool recommendations for ACE learning system';

COMMENT ON COLUMN user_profiles.research_domain IS 'Primary research domain: proteomics, genomics, transcriptomics, metabolomics';
COMMENT ON COLUMN user_profiles.expertise_level IS 'User expertise level: beginner, intermediate, expert';
COMMENT ON COLUMN user_profiles.preferences IS 'Additional flexible preferences stored as JSON';

COMMENT ON COLUMN search_sessions.context IS 'Search context JSON auto-populated from user profile, can be overridden per session';
COMMENT ON COLUMN search_sessions.expires_at IS 'Session expiration timestamp, defaults to 7 days from creation';

COMMENT ON COLUMN search_feedback.was_selected IS 'TRUE if user selected this tool from search results';
COMMENT ON COLUMN search_feedback.was_helpful IS 'User explicit feedback: TRUE=helpful, FALSE=not helpful, NULL=no feedback yet';
COMMENT ON COLUMN search_feedback.had_nfcore_badge IS 'TRUE if tool had nf-core validation badge in explanation';
