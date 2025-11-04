-- Migration 005: Chat Session Persistence
-- Purpose: Store chat sessions in backend (not just localStorage)
-- Date: November 3, 2025

-- Chat Sessions (main conversation containers)
CREATE TABLE IF NOT EXISTS chat_sessions (
    session_id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,

    -- Session metadata
    title TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    last_activity TEXT DEFAULT (datetime('now')),
    status TEXT DEFAULT 'active', -- 'active', 'archived', 'deleted'

    -- Context tracking
    message_count INTEGER DEFAULT 0,
    token_count INTEGER DEFAULT 0,
    last_compressed_at TEXT,

    -- Session type
    session_type TEXT DEFAULT 'chat', -- 'chat', 'workflow', 'analysis'

    FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE
);

-- Chat Messages (individual messages in conversations)
CREATE TABLE IF NOT EXISTS chat_messages (
    message_id TEXT PRIMARY KEY,
    session_id TEXT NOT NULL,

    -- Message content
    role TEXT NOT NULL, -- 'user', 'assistant', 'system'
    content TEXT NOT NULL,

    -- Metadata
    timestamp TEXT DEFAULT (datetime('now')),
    token_count INTEGER DEFAULT 0,

    -- Optional fields
    suggestions TEXT, -- JSON array of suggested responses
    workflow_id TEXT, -- Link to workflow if message generated one
    thinking_content TEXT, -- Thinking process if thinking mode was used
    thinking_level TEXT, -- 'normal', 'hard', 'mega', 'ultra'

    -- Error handling
    error_code INTEGER,
    error_message TEXT,

    FOREIGN KEY (session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
);

-- Session Workflows (workflows attached to sessions)
CREATE TABLE IF NOT EXISTS session_workflows (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,
    workflow_id TEXT NOT NULL, -- Galaxy workflow ID

    -- Workflow metadata
    workflow_name TEXT,
    workflow_description TEXT,
    created_at TEXT DEFAULT (datetime('now')),

    -- Execution status
    invocation_id TEXT, -- Galaxy invocation ID
    status TEXT, -- 'pending', 'running', 'completed', 'failed', 'cancelled'
    started_at TEXT,
    completed_at TEXT,

    -- Results
    success INTEGER, -- 0=failed, 1=success, NULL=in progress
    error_message TEXT,

    FOREIGN KEY (session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
);

-- Session Datasets (datasets used in sessions)
CREATE TABLE IF NOT EXISTS session_datasets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,

    -- Dataset identification
    dataset_id TEXT, -- Galaxy dataset ID if uploaded
    dataset_name TEXT NOT NULL,
    dataset_type TEXT NOT NULL, -- 'input', 'output', 'intermediate'

    -- Storage info
    storage_type TEXT NOT NULL, -- 's3', 'local', 'replit_storage', 'galaxy'
    storage_path TEXT,

    -- File metadata
    format TEXT, -- 'FASTQ', 'BAM', 'VCF', etc.
    size_bytes INTEGER,
    description TEXT,

    -- Timestamps
    created_at TEXT DEFAULT (datetime('now')),
    uploaded_at TEXT,

    FOREIGN KEY (session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
);

-- Session Compression History (track when sessions were compressed)
CREATE TABLE IF NOT EXISTS session_compressions (
    compression_id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL,

    -- Compression details
    compressed_at TEXT DEFAULT (datetime('now')),
    messages_before INTEGER NOT NULL, -- Message count before compression
    messages_after INTEGER NOT NULL, -- Message count after (kept recent N)
    tokens_before INTEGER NOT NULL,
    tokens_after INTEGER NOT NULL,
    compression_ratio REAL, -- tokens_after / tokens_before

    -- Compressed content
    summary TEXT NOT NULL, -- AI-generated summary of old messages

    FOREIGN KEY (session_id) REFERENCES chat_sessions(session_id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_sessions_user ON chat_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON chat_sessions(status);
CREATE INDEX IF NOT EXISTS idx_sessions_last_activity ON chat_sessions(last_activity);

CREATE INDEX IF NOT EXISTS idx_messages_session ON chat_messages(session_id);
CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON chat_messages(timestamp);
CREATE INDEX IF NOT EXISTS idx_messages_role ON chat_messages(role);

CREATE INDEX IF NOT EXISTS idx_session_workflows_session ON session_workflows(session_id);
CREATE INDEX IF NOT EXISTS idx_session_workflows_status ON session_workflows(status);
CREATE INDEX IF NOT EXISTS idx_session_workflows_invocation ON session_workflows(invocation_id);

CREATE INDEX IF NOT EXISTS idx_session_datasets_session ON session_datasets(session_id);
CREATE INDEX IF NOT EXISTS idx_session_datasets_type ON session_datasets(dataset_type);

CREATE INDEX IF NOT EXISTS idx_compressions_session ON session_compressions(session_id);

-- Views for common queries

-- Recent active sessions
CREATE VIEW IF NOT EXISTS recent_sessions AS
SELECT
    s.session_id,
    s.user_id,
    s.title,
    s.created_at,
    s.last_activity,
    s.message_count,
    s.token_count,
    s.status,
    COUNT(DISTINCT sw.workflow_id) as workflow_count,
    COUNT(DISTINCT sd.id) as dataset_count
FROM chat_sessions s
LEFT JOIN session_workflows sw ON s.session_id = sw.session_id
LEFT JOIN session_datasets sd ON s.session_id = sd.session_id
WHERE s.status = 'active'
GROUP BY s.session_id
ORDER BY s.last_activity DESC
LIMIT 20;

-- Session summary with statistics
CREATE VIEW IF NOT EXISTS session_summary AS
SELECT
    s.session_id,
    s.user_id,
    s.title,
    s.created_at,
    s.last_activity,
    s.status,
    s.message_count,
    s.token_count,
    COUNT(DISTINCT m.message_id) as actual_message_count,
    COUNT(DISTINCT sw.workflow_id) as workflow_count,
    COUNT(DISTINCT sd.id) as dataset_count,
    SUM(CASE WHEN sw.success = 1 THEN 1 ELSE 0 END) as successful_workflows,
    SUM(CASE WHEN sw.success = 0 THEN 1 ELSE 0 END) as failed_workflows,
    MAX(sc.compressed_at) as last_compression
FROM chat_sessions s
LEFT JOIN chat_messages m ON s.session_id = m.session_id
LEFT JOIN session_workflows sw ON s.session_id = sw.session_id
LEFT JOIN session_datasets sd ON s.session_id = sd.session_id
LEFT JOIN session_compressions sc ON s.session_id = sc.session_id
GROUP BY s.session_id;

-- Record migration
INSERT OR IGNORE INTO schema_migrations (migration_name, applied_at, status)
VALUES ('005_chat_sessions', datetime('now'), 'applied');
