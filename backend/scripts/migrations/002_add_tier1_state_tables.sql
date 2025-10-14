-- Migration: Add Tier 1 Critical State Tables
-- Date: 2025-10-14
-- Purpose: Add tables for critical user state that must be synced immediately
--          (Workflow drafts, AI conversations, Favorites, Tool/Dataset usage)

-- ============================================================================
-- WORKFLOW STATE TABLES
-- ============================================================================

-- Table: user_workflow_state - Workflow drafts and saved workflows
CREATE TABLE IF NOT EXISTS user_workflow_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    workflow_id TEXT, -- NULL for unsaved drafts, populated when saved
    workflow_uuid TEXT UNIQUE NOT NULL, -- Always unique even for drafts
    workflow_name TEXT,
    workflow_data TEXT NOT NULL, -- JSON workflow definition
    status TEXT DEFAULT 'draft', -- 'draft', 'saved', 'published'
    editor_state TEXT, -- JSON: zoom, position, active nodes, etc.
    is_favorite INTEGER DEFAULT 0,
    last_opened_at TEXT DEFAULT (datetime('now')),
    last_saved_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workflow_state_user ON user_workflow_state(user_id);
CREATE INDEX IF NOT EXISTS idx_workflow_state_recent ON user_workflow_state(user_id, last_opened_at DESC);
CREATE INDEX IF NOT EXISTS idx_workflow_state_status ON user_workflow_state(user_id, status);
CREATE INDEX IF NOT EXISTS idx_workflow_state_favorite ON user_workflow_state(user_id, is_favorite);
CREATE INDEX IF NOT EXISTS idx_workflow_state_uuid ON user_workflow_state(workflow_uuid);

-- Table: user_workflow_executions - Workflow invocation history
CREATE TABLE IF NOT EXISTS user_workflow_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    workflow_id TEXT NOT NULL,
    invocation_id TEXT UNIQUE,
    status TEXT NOT NULL, -- 'running', 'completed', 'failed', 'cancelled'
    inputs TEXT, -- JSON
    outputs TEXT, -- JSON
    parameters TEXT, -- JSON
    execution_time_seconds REAL,
    started_at TEXT DEFAULT (datetime('now')),
    completed_at TEXT,
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_workflow_exec_user ON user_workflow_executions(user_id);
CREATE INDEX IF NOT EXISTS idx_workflow_exec_workflow ON user_workflow_executions(workflow_id);
CREATE INDEX IF NOT EXISTS idx_workflow_exec_status ON user_workflow_executions(user_id, status);
CREATE INDEX IF NOT EXISTS idx_workflow_exec_recent ON user_workflow_executions(user_id, started_at DESC);

-- ============================================================================
-- AI ASSISTANT TABLES
-- ============================================================================

-- Table: user_ai_conversations - AI chat sessions
CREATE TABLE IF NOT EXISTS user_ai_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    session_id TEXT UNIQUE NOT NULL, -- UUID for conversation session
    title TEXT, -- Auto-generated or user-set title
    context_type TEXT, -- 'general', 'workflow', 'tool_selection', 'troubleshooting'
    context_id TEXT, -- Reference to workflow_id, tool_id, etc.
    created_at TEXT DEFAULT (datetime('now')),
    last_message_at TEXT DEFAULT (datetime('now')),
    is_archived INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ai_conversations_user ON user_ai_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_recent ON user_ai_conversations(user_id, last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_active ON user_ai_conversations(user_id, is_archived);

-- Table: user_ai_messages - Individual chat messages
CREATE TABLE IF NOT EXISTS user_ai_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL,
    message_type TEXT NOT NULL, -- 'user', 'assistant', 'system'
    message_text TEXT NOT NULL,
    message_data TEXT, -- JSON: workflows, tool recommendations, code snippets, etc.
    timestamp TEXT DEFAULT (datetime('now')),
    read_status INTEGER DEFAULT 0,
    FOREIGN KEY (conversation_id) REFERENCES user_ai_conversations(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_ai_messages_conversation ON user_ai_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_messages_timestamp ON user_ai_messages(conversation_id, timestamp);
CREATE INDEX IF NOT EXISTS idx_ai_messages_unread ON user_ai_messages(conversation_id, read_status);

-- Table: user_ai_interactions - Tracking AI suggestions and actions
CREATE TABLE IF NOT EXISTS user_ai_interactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    conversation_id INTEGER,
    interaction_type TEXT NOT NULL, -- 'workflow_generated', 'tool_recommended', 'quick_action', 'parameter_suggested'
    interaction_data TEXT NOT NULL, -- JSON
    accepted INTEGER DEFAULT 0, -- Did user accept the suggestion?
    feedback_rating INTEGER, -- 1-5 stars (optional)
    feedback_text TEXT,
    timestamp TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    FOREIGN KEY (conversation_id) REFERENCES user_ai_conversations(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_ai_interactions_user ON user_ai_interactions(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_interactions_type ON user_ai_interactions(interaction_type);
CREATE INDEX IF NOT EXISTS idx_ai_interactions_accepted ON user_ai_interactions(user_id, accepted);

-- ============================================================================
-- FAVORITES TABLES
-- ============================================================================

-- Table: user_tool_favorites - Favorite tools with ordering
CREATE TABLE IF NOT EXISTS user_tool_favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,
    last_used_at TEXT DEFAULT (datetime('now')),
    notes TEXT,
    tags TEXT, -- JSON array of custom tags
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_tool_favorites_user ON user_tool_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_tool_favorites_order ON user_tool_favorites(user_id, display_order);
CREATE INDEX IF NOT EXISTS idx_tool_favorites_recent ON user_tool_favorites(user_id, last_used_at DESC);

-- Table: user_dataset_favorites - Favorite datasets
CREATE TABLE IF NOT EXISTS user_dataset_favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    dataset_id TEXT NOT NULL, -- e.g., 'biomate_dataset_bindingdb'
    display_order INTEGER DEFAULT 0,
    last_used_at TEXT DEFAULT (datetime('now')),
    notes TEXT,
    tags TEXT, -- JSON array
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, dataset_id)
);

CREATE INDEX IF NOT EXISTS idx_dataset_favorites_user ON user_dataset_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_dataset_favorites_order ON user_dataset_favorites(user_id, display_order);

-- ============================================================================
-- USAGE TRACKING TABLES
-- ============================================================================

-- Table: user_tool_usage - Tool usage history and frequency
CREATE TABLE IF NOT EXISTS user_tool_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    usage_count INTEGER DEFAULT 1,
    last_used_at TEXT DEFAULT (datetime('now')),
    first_used_at TEXT DEFAULT (datetime('now')),
    context_workflow_id TEXT, -- Which workflow was tool used in (last use)
    context_dataset_id TEXT, -- Which dataset was used with tool (last use)
    execution_time_avg REAL, -- Average execution time in seconds
    success_rate REAL DEFAULT 1.0, -- Percentage of successful runs
    total_successes INTEGER DEFAULT 1,
    total_failures INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, tool_id)
);

CREATE INDEX IF NOT EXISTS idx_tool_usage_user ON user_tool_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_tool_usage_frequency ON user_tool_usage(user_id, usage_count DESC);
CREATE INDEX IF NOT EXISTS idx_tool_usage_recent ON user_tool_usage(user_id, last_used_at DESC);

-- Table: user_dataset_usage - Dataset usage history
CREATE TABLE IF NOT EXISTS user_dataset_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    dataset_id TEXT NOT NULL,
    usage_count INTEGER DEFAULT 1,
    last_used_at TEXT DEFAULT (datetime('now')),
    first_used_at TEXT DEFAULT (datetime('now')),
    usage_context TEXT, -- JSON: which tools/workflows used with
    total_workflows INTEGER DEFAULT 0,
    total_analyses INTEGER DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, dataset_id)
);

CREATE INDEX IF NOT EXISTS idx_dataset_usage_user ON user_dataset_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_dataset_usage_frequency ON user_dataset_usage(user_id, usage_count DESC);
CREATE INDEX IF NOT EXISTS idx_dataset_usage_recent ON user_dataset_usage(user_id, last_used_at DESC);

-- ============================================================================
-- TRIGGERS FOR AUTOMATIC TIMESTAMP UPDATES
-- ============================================================================

CREATE TRIGGER IF NOT EXISTS update_workflow_state_timestamp
AFTER UPDATE ON user_workflow_state
BEGIN
    UPDATE user_workflow_state SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_ai_conversation_last_message
AFTER INSERT ON user_ai_messages
BEGIN
    UPDATE user_ai_conversations
    SET last_message_at = datetime('now')
    WHERE id = NEW.conversation_id;
END;

-- ============================================================================
-- INITIAL DATA POPULATION (Optional - for testing)
-- ============================================================================

-- Example: Populate tool usage from existing galaxy_user preferences
-- This can be run separately after migration if needed
-- INSERT INTO user_tool_usage (user_id, tool_id, usage_count, last_used_at)
-- SELECT id, json_extract(preferences, '$.favorites.tools'), 1, datetime('now')
-- FROM galaxy_user
-- WHERE json_valid(preferences) AND json_extract(preferences, '$.favorites.tools') IS NOT NULL;
