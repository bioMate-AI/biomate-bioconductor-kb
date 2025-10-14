# Comprehensive User State Analysis for BioMate

**Date:** 2025-10-14
**Branch:** frontend_stronger
**Purpose:** Complete inventory of user information that needs to be persisted

---

## Executive Summary

After analyzing the BioMate frontend architecture, I've identified **15 categories** of user state information that need to be persisted across sessions. The application uses a sophisticated state management system with Pinia stores and extensive local storage usage.

---

## Current State Management Architecture

### Frontend State Management
- **Framework:** Pinia (Vue 3 state management)
- **Local Storage Pattern:** Per-user localStorage using hashed user IDs
- **Composable:** `useUserLocalStorage(key, initialValue)` - automatically scopes to current user
- **Total Stores:** 70+ Pinia stores managing different aspects

### Backend State Management
- **Database:** SQLite (galaxy_ai_tools.db) + PostgreSQL (galaxy_user tables)
- **Existing User Tables:** `galaxy_user`, user preferences stored as JSON
- **Session Management:** Currently basic, needs enhancement

---

## Categories of User Information to Persist

### 1. **User Profile & Authentication**

**Current Location:** `userStore.ts`, backend `galaxy_user` table

**Data to Persist:**
- User ID, email, username
- Email verification status
- Registration timestamp
- Last login timestamp
- Profile picture/avatar
- Bio/description
- Account settings

**Database Schema (Existing + Additions):**
```sql
-- galaxy_user table (existing, add columns)
ALTER TABLE galaxy_user ADD COLUMN email_verified INTEGER DEFAULT 0;
ALTER TABLE galaxy_user ADD COLUMN last_login_at TIMESTAMP;
ALTER TABLE galaxy_user ADD COLUMN profile_picture_url TEXT;
ALTER TABLE galaxy_user ADD COLUMN bio TEXT;
```

**Frontend State:**
```typescript
currentUser: {
  id: string,
  email: string,
  username: string,
  isAnonymous: boolean,
  isAdmin: boolean,
  emailVerified: boolean,
  lastLogin: Date,
  profilePicture: string,
  bio: string
}
```

---

### 2. **User Preferences & Theme**

**Current Location:** `userStore.ts`, stored in `currentPreferences`

**Data to Persist:**
- Theme selection (dark/light)
- Language preference
- Timezone
- Date format
- Notification preferences
- Auto-save interval
- Display density (compact/comfortable)

**Database Schema:**
```sql
-- galaxy_user table (preferences column already exists as JSON)
-- Expand JSON structure:
{
  "theme": "dark",
  "language": "en",
  "timezone": "America/New_York",
  "dateFormat": "MM/DD/YYYY",
  "notifications": {
    "email": true,
    "browser": true,
    "workflow_completion": true,
    "tool_updates": false
  },
  "autoSaveInterval": 5000,
  "displayDensity": "comfortable"
}
```

**Frontend State (currently tracked):**
```typescript
currentPreferences: {
  theme: string,
  favorites: { tools: string[] },
  // Add more preferences
}
```

---

### 3. **Favorite Tools**

**Current Location:** `userStore.ts`, `addFavoriteTool()`, `removeFavoriteTool()`

**Data to Persist:**
- Tool IDs marked as favorites
- Order of favorites
- Last used timestamp for each favorite
- Custom notes/tags for favorites

**Database Schema:**
```sql
CREATE TABLE user_tool_favorites (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    display_order INTEGER DEFAULT 0,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    notes TEXT,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, tool_id)
);

CREATE INDEX idx_favorites_user ON user_tool_favorites(user_id);
CREATE INDEX idx_favorites_order ON user_tool_favorites(user_id, display_order);
```

**Frontend State (currently tracked):**
```typescript
currentFavorites: {
  tools: string[]  // List of tool IDs
}
```

---

### 4. **Tool Usage History & Recommendations**

**Current Location:** `toolStore.ts`, `userTagsStore.ts`

**Data to Persist:**
- Recently used tools (last 50)
- Tool usage frequency
- Tool usage context (which workflows/datasets)
- Tool search history
- Custom tool tags

**Database Schema:**
```sql
CREATE TABLE user_tool_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    usage_count INTEGER DEFAULT 1,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    context_workflow_id TEXT,  -- Which workflow was tool used in
    context_dataset_id TEXT,   -- Which dataset was used
    execution_time_avg REAL,   -- Average execution time
    success_rate REAL DEFAULT 1.0,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_tool_usage_user ON user_tool_usage(user_id);
CREATE INDEX idx_tool_usage_frequency ON user_tool_usage(user_id, usage_count DESC);
CREATE INDEX idx_tool_usage_recent ON user_tool_usage(user_id, last_used_at DESC);
```

**Frontend State:**
```typescript
// toolStore already uses useUserLocalStorage for:
currentPanelView: string  // e.g., "default", "ontology:edam_topics"
```

---

### 5. **History State**

**Current Location:** `historyStore.ts` - Very comprehensive!

**Data to Persist:**
- All histories (stored, pinned, archived)
- Current history selection
- History filter text (per history)
- Pinned histories
- History metadata (name, tags, annotations)
- History sharing settings

**Database Schema:**
```sql
-- Histories are already in Galaxy's history table
-- Add user-specific metadata:

CREATE TABLE user_history_metadata (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    history_id TEXT NOT NULL,
    pinned INTEGER DEFAULT 0,
    custom_color TEXT,
    custom_icon TEXT,
    notes TEXT,
    last_accessed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, history_id)
);

CREATE INDEX idx_history_meta_user ON user_history_metadata(user_id);
CREATE INDEX idx_history_pinned ON user_history_metadata(user_id, pinned);
```

**Frontend State (currently tracked in historyStore):**
```typescript
storedCurrentHistoryId: string | null
storedFilterTexts: { [historyId: string]: string }
storedHistories: { [historyId: string]: AnyHistory }
pinnedHistories: { id: string }[]  // Already uses useUserLocalStorage!
```

---

### 6. **Workflow State**

**Current Location:** `workflowStore.ts`, `workflowEditorStateStore.ts`, `workflowStepStore.ts`

**Data to Persist:**
- Created workflows (stored/published)
- Workflow drafts (in-progress, unsaved)
- Workflow execution history
- Workflow favorites
- Recently opened workflows
- Workflow editor state (zoom, position)
- Current workflow being edited
- Unsaved changes indicator

**Database Schema:**
```sql
CREATE TABLE user_workflow_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    workflow_id TEXT,  -- NULL for unsaved drafts
    workflow_name TEXT,
    workflow_data TEXT,  -- JSON workflow definition
    status TEXT DEFAULT 'draft',  -- 'draft', 'saved', 'published'
    editor_state TEXT,  -- JSON: zoom, position, active nodes
    is_favorite INTEGER DEFAULT 0,
    last_opened_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_saved_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_workflow_state_user ON user_workflow_state(user_id);
CREATE INDEX idx_workflow_recent ON user_workflow_state(user_id, last_opened_at DESC);

CREATE TABLE user_workflow_executions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    workflow_id TEXT NOT NULL,
    invocation_id TEXT,
    status TEXT,  -- 'running', 'completed', 'failed', 'cancelled'
    inputs TEXT,  -- JSON
    outputs TEXT,  -- JSON
    execution_time_seconds REAL,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP,
    error_message TEXT,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_workflow_exec_user ON user_workflow_executions(user_id);
CREATE INDEX idx_workflow_exec_status ON user_workflow_executions(status);
```

**Frontend State (currently tracked):**
```typescript
// workflowStore.ts
workflowsByInstanceId: { [workflowId: string]: StoredWorkflowDetailed }
fullWorkflowsByIdAndVersion: Map<string, any>

// workflowEditorStateStore.ts
scale: number  // Zoom level
position: [number, number]  // Canvas position
activeNodeId: number | null
hasChanges: boolean  // Unsaved changes!
report: { markdown: string }
multiSelectedSteps: { [stepId: number]: boolean }
```

---

### 7. **AI Assistant State**

**Current Location:** `AIAssistantPanel.vue`, likely needs backend persistence

**Data to Persist:**
- Chat conversation history (per user)
- AI-generated workflows
- AI suggestions accepted/rejected
- Quick action usage
- AI assistant preferences
- Message read/unread status

**Database Schema:**
```sql
CREATE TABLE user_ai_conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    session_id TEXT NOT NULL,  -- UUID for conversation session
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_message_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE TABLE user_ai_messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL,
    message_type TEXT NOT NULL,  -- 'user', 'assistant', 'system'
    message_text TEXT NOT NULL,
    message_data TEXT,  -- JSON: workflows, tool recommendations, etc.
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_status INTEGER DEFAULT 0,
    FOREIGN KEY (conversation_id) REFERENCES user_ai_conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_ai_messages_conversation ON user_ai_messages(conversation_id);

CREATE TABLE user_ai_interactions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    interaction_type TEXT,  -- 'workflow_generated', 'tool_recommended', 'quick_action'
    interaction_data TEXT,  -- JSON
    accepted INTEGER DEFAULT 0,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_ai_interactions_user ON user_ai_interactions(user_id);
```

**Frontend State:**
```typescript
aiAssistant: {
  isOpen: boolean,
  messages: Array<{
    id: string,
    type: 'user' | 'assistant' | 'system',
    text: string,
    timestamp: Date,
    actions?: Array<{id: string, label: string}>,
    read: boolean
  }>,
  currentSession: string,
  unreadCount: number
}
```

---

### 8. **Dataset Usage History**

**Current Location:** Enhanced tool index (already has `dataset_tool_mapping`)

**Data to Persist:**
- Recently accessed datasets
- Dataset favorites
- Dataset usage count
- Dataset + tool combinations used
- Custom dataset tags/annotations

**Database Schema:**
```sql
CREATE TABLE user_dataset_usage (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    dataset_id TEXT NOT NULL,  -- e.g., 'biomate_dataset_bindingdb'
    usage_count INTEGER DEFAULT 1,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usage_context TEXT,  -- JSON: which tools/workflows used with
    is_favorite INTEGER DEFAULT 0,
    custom_tags TEXT,  -- JSON array
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, dataset_id)
);

CREATE INDEX idx_dataset_usage_user ON user_dataset_usage(user_id);
CREATE INDEX idx_dataset_favorites ON user_dataset_usage(user_id, is_favorite);
```

**Frontend State:**
```typescript
datasetUsage: {
  recent: string[],  // Dataset IDs
  favorites: string[],
  usageStats: {
    [datasetId: string]: {
      count: number,
      lastUsed: Date,
      usedWith: { tools: string[], workflows: string[] }
    }
  }
}
```

---

### 9. **Activity Bar & Panel Layout**

**Current Location:** `activityStore.ts` - Uses localStorage extensively!

**Data to Persist:**
- Activity bar configuration
- Custom activity items
- Visibility of activities
- Side panel open/closed state
- Active side panel
- Panel widths
- Panel positions

**Database Schema:**
```sql
CREATE TABLE user_layout_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    scope TEXT DEFAULT 'default',  -- 'workflow-editor', 'history-view', etc.
    layout_data TEXT,  -- JSON
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, scope)
);

CREATE INDEX idx_layout_user ON user_layout_preferences(user_id);
```

**Frontend State (currently tracked in activityStore):**
```typescript
// ALL of these use useUserLocalStorage already!
activities: Array<Activity>  // Stored per-user per-scope
toggledSideBar: string  // 'tools', 'history', 'closed', etc.
sidePanelWidth: number  // Width in pixels
```

---

### 10. **UI Component States**

**Current Location:** Various stores using `useUserLocalStorage`

**Data to Persist:**
- List view mode (grid vs list) - `userStore.ts`
- History panel width - `userStore.ts`
- "Has seen upload help" flag - `userStore.ts`
- Tool panel view selection - `toolStore.ts`
- Sort preferences
- Filter settings
- Column visibility (for tables)
- Collapsed/expanded sections

**Database Schema:**
```sql
CREATE TABLE user_ui_state (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    state_key TEXT NOT NULL,  -- e.g., 'workflow_editor', 'tool_panel', 'history_panel'
    state_data TEXT NOT NULL,  -- JSON blob
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, state_key)
);

CREATE INDEX idx_ui_state_user ON user_ui_state(user_id);
```

**Frontend State (currently tracked):**
```typescript
// userStore.ts (using useUserLocalStorage)
currentListViewPreferences: { [listId: string]: 'grid' | 'list' }
hasSeenUploadHelp: boolean
historyPanelWidth: number

// toolStore.ts (using useUserLocalStorage)
currentPanelView: string
```

---

### 11. **Notifications**

**Current Location:** `notificationsStore.ts`

**Data to Persist:**
- Read/unread status
- Notification preferences
- Archived notifications
- Notification history (last 100)

**Database Schema:**
```sql
-- Notifications likely already exist in Galaxy backend
-- Add user-specific metadata:

CREATE TABLE user_notification_preferences (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    email_notifications INTEGER DEFAULT 1,
    browser_notifications INTEGER DEFAULT 1,
    workflow_completion INTEGER DEFAULT 1,
    tool_updates INTEGER DEFAULT 0,
    system_announcements INTEGER DEFAULT 1,
    digest_frequency TEXT DEFAULT 'immediate',  -- 'immediate', 'daily', 'weekly'
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);
```

**Frontend State (currently tracked):**
```typescript
notifications: UserNotification[]
totalUnreadCount: number
unreadNotifications: computed  // Derived from notifications
```

---

### 12. **Tags & Annotations**

**Current Location:** `userTagsStore.ts` - Uses Dexie (IndexedDB)!

**Data to Persist:**
- User-defined tags (per item type)
- Tag usage history
- Tag autocomplete suggestions
- Recent tags

**Database Schema:**
```sql
-- Currently stored in IndexedDB (userTagStoreDatabase)
-- Keep IndexedDB for client-side caching, sync to server:

CREATE TABLE user_tags (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tag TEXT NOT NULL,
    last_used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    usage_count INTEGER DEFAULT 1,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, tag)
);

CREATE INDEX idx_tags_user ON user_tags(user_id);
CREATE INDEX idx_tags_frequency ON user_tags(user_id, usage_count DESC);
```

**Frontend State (currently tracked):**
```typescript
// Stored in IndexedDB via Dexie
tags: StoredTag[] = [{
  id: number,
  tag: string,
  userHash: string,
  lastUsed: number
}]
```

---

### 13. **Search History & Filters**

**Data to Persist:**
- Tool search queries
- Workflow search queries
- Dataset search queries
- Filter presets (saved filter combinations)
- Search result preferences

**Database Schema:**
```sql
CREATE TABLE user_search_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    search_type TEXT NOT NULL,  -- 'tool', 'workflow', 'dataset', 'history'
    search_query TEXT NOT NULL,
    search_filters TEXT,  -- JSON
    result_count INTEGER,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_search_history_user ON user_search_history(user_id);
CREATE INDEX idx_search_recent ON user_search_history(user_id, timestamp DESC);

CREATE TABLE user_filter_presets (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    preset_name TEXT NOT NULL,
    filter_type TEXT NOT NULL,  -- 'tool', 'history', 'workflow'
    filter_data TEXT,  -- JSON
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, preset_name, filter_type)
);

CREATE INDEX idx_presets_user ON user_filter_presets(user_id);
```

---

### 14. **Interactive Tool Sessions**

**Current Location:** `interactiveToolsStore.ts`, `jobStore.ts`

**Data to Persist:**
- Active interactive tool sessions
- Saved interactive tool states
- Interactive tool preferences
- Recently used interactive tools

**Database Schema:**
```sql
CREATE TABLE user_interactive_sessions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    tool_id TEXT NOT NULL,
    session_id TEXT UNIQUE NOT NULL,
    session_data TEXT,  -- JSON: saved state
    status TEXT DEFAULT 'active',  -- 'active', 'paused', 'terminated'
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_accessed_at TIMESTAMP,
    expires_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE INDEX idx_interactive_user ON user_interactive_sessions(user_id);
CREATE INDEX idx_interactive_status ON user_interactive_sessions(status);
```

---

### 15. **User Quotas & Usage Stats**

**Data to Persist:**
- Storage usage
- Compute quota usage
- API rate limits
- Usage analytics (for admin/insights)

**Database Schema:**
```sql
CREATE TABLE user_quotas (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL UNIQUE,
    storage_quota_mb INTEGER DEFAULT 10000,  -- 10GB
    storage_used_mb REAL DEFAULT 0,
    compute_quota_hours INTEGER DEFAULT 100,
    compute_used_hours REAL DEFAULT 0,
    api_rate_limit INTEGER DEFAULT 1000,  -- requests per hour
    api_requests_today INTEGER DEFAULT 0,
    quota_reset_date DATE,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE
);

CREATE TABLE user_usage_stats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER NOT NULL,
    stat_date DATE NOT NULL,
    workflows_created INTEGER DEFAULT 0,
    workflows_executed INTEGER DEFAULT 0,
    tools_used INTEGER DEFAULT 0,
    datasets_accessed INTEGER DEFAULT 0,
    compute_hours REAL DEFAULT 0,
    storage_mb REAL DEFAULT 0,
    FOREIGN KEY (user_id) REFERENCES galaxy_user(id) ON DELETE CASCADE,
    UNIQUE(user_id, stat_date)
);

CREATE INDEX idx_usage_user ON user_usage_stats(user_id, stat_date DESC);
```

---

## Current State Persistence Patterns

### Frontend Local Storage Pattern

The application uses a sophisticated pattern:

```typescript
// Automatically scopes storage to current user via hashed user ID
const myData = useUserLocalStorage('my-key', defaultValue)

// Examples from existing code:
const activities = useUserLocalStorage(`activity-store-activities-${scope}`, [])
const pinnedHistories = useUserLocalStorage('history-store-pinned-histories', [])
const currentPanelView = useUserLocalStorage('tool-store-view', '')
```

**Storage Key Format:** `galaxy:{hashedUserId}:{key}`

This means each user's data is already isolated in localStorage!

### Backend Sync Requirements

**Problem:** Current localStorage is:
- ✅ Per-user isolated
- ❌ Not synced across devices
- ❌ Lost if browser data cleared
- ❌ Not backed up

**Solution:** Sync critical state to backend database tables.

---

## State Persistence Strategy

### Tier 1: Critical State (Must sync to backend immediately)
- User authentication & profile
- Subscription status
- Workflow drafts
- AI conversation history
- Favorite tools/datasets

### Tier 2: Important State (Sync periodically, debounced)
- UI layout preferences
- Tool/dataset usage history
- Search history
- Filter presets
- Tag usage

### Tier 3: Cache-Only State (Keep in localStorage, optional sync)
- Temporary UI state (panel widths, collapsed sections)
- Auto-complete caches
- Transient search results
- Temporary filter states

---

## Data Sync Architecture

### Frontend State Sync Service

```typescript
// New service: userStateSyncService.ts
export class UserStateSyncService {
  private syncQueue: Map<string, any> = new Map()
  private syncTimer: number | null = null

  // Debounced sync - accumulate changes and send in batches
  queueSync(stateKey: string, data: any, priority: 'immediate' | 'normal' | 'low') {
    this.syncQueue.set(stateKey, { data, priority })

    if (priority === 'immediate') {
      this.flushQueue()
    } else {
      this.scheduleSync()
    }
  }

  // Batch upload to backend
  async flushQueue() {
    const states = Array.from(this.syncQueue.entries())
    if (states.length === 0) return

    await axios.post('/api/users/state/batch', {
      states: states.map(([key, value]) => ({ key, ...value }))
    })

    this.syncQueue.clear()
  }

  // Download all state on login
  async loadAllState(userId: string) {
    const { data } = await axios.get(`/api/users/${userId}/state/all`)
    return data
  }

  // Merge localStorage with backend state (backend wins)
  mergeState(localState: any, backendState: any) {
    // Complex merge logic
    // Prefer backend state for critical data
    // Keep local state for cache-only data
  }
}
```

### Backend State Sync API

```python
# lib/galaxy/webapps/galaxy/api/user_state_sync.py
class UserStateSyncController(BaseGalaxyAPIController):

    @expose_api
    @require_login
    def get_all_state(self, trans, **kwargs):
        """GET /api/users/{user_id}/state/all

        Returns all persisted state for user on login
        """
        user_id = trans.user.id

        state = {
            'profile': self._get_user_profile(user_id),
            'preferences': self._get_user_preferences(user_id),
            'ui_state': self._get_ui_state(user_id),
            'favorites': self._get_favorites(user_id),
            'workflow_drafts': self._get_workflow_drafts(user_id),
            'ai_conversations': self._get_recent_ai_conversations(user_id),
            'layout': self._get_layout_preferences(user_id),
            # ... more state categories
        }

        return state

    @expose_api
    @require_login
    def batch_update_state(self, trans, payload, **kwargs):
        """POST /api/users/state/batch

        Batch update multiple state categories
        """
        user_id = trans.user.id
        states = payload.get('states', [])

        for state in states:
            state_key = state['key']
            state_data = state['data']
            priority = state.get('priority', 'normal')

            # Route to appropriate handler
            if state_key.startswith('workflow_'):
                self._update_workflow_state(user_id, state_key, state_data)
            elif state_key.startswith('ui_'):
                self._update_ui_state(user_id, state_key, state_data)
            elif state_key.startswith('ai_'):
                self._update_ai_state(user_id, state_key, state_data)
            # ... more handlers

        trans.sa_session.commit()
        return {"success": True, "updated": len(states)}
```

---

## Migration Path

### Phase 1: Backend Schema (Week 1)
1. Create all new database tables (15 categories)
2. Add migration scripts
3. Test schema with sample data

### Phase 2: Backend API (Week 1-2)
1. Implement state sync APIs
2. Batch update/retrieve endpoints
3. State merge logic
4. Add to existing Galaxy API routes

### Phase 3: Frontend Sync Service (Week 2)
1. Create `UserStateSyncService`
2. Integrate with existing stores
3. Add debounced sync logic
4. Handle offline scenarios

### Phase 4: Store Migration (Week 2-3)
1. Update each Pinia store to use sync service
2. Add `syncToBackend()` methods
3. Test data persistence
4. Handle merge conflicts

### Phase 5: Login/Logout Flow (Week 3)
1. On login: fetch all state from backend
2. Merge with localStorage
3. On logout: flush sync queue
4. Clear sensitive localStorage

### Phase 6: Testing & Rollout (Week 4)
1. Multi-device testing
2. Network failure handling
3. Data integrity verification
4. Performance optimization

---

## Key Implementation Notes

### 1. **Backward Compatibility**
- Keep existing localStorage patterns
- Gracefully handle users with no backend state
- Don't break existing workflows

### 2. **Performance**
- Use debounced sync (not on every keystroke)
- Batch API calls
- Lazy load non-critical state
- Cache frequently accessed state

### 3. **Privacy**
- Encrypt sensitive state data
- Allow users to clear history
- GDPR compliance (export/delete)

### 4. **Conflict Resolution**
- Backend state wins on login
- Use timestamps for merge conflicts
- Allow manual conflict resolution for critical data (workflows)

### 5. **Offline Support**
- Queue sync operations when offline
- Retry failed syncs
- Show sync status to user

---

## Data Volume Estimates

**Per User Storage Requirements:**
- Profile & Preferences: ~5 KB
- Favorite Tools: ~2 KB
- Tool Usage History: ~50 KB
- Workflow Drafts: ~100 KB (5 drafts × 20 KB each)
- Workflow Executions: ~200 KB (100 executions)
- AI Conversations: ~500 KB (assuming 1MB compressed)
- Dataset Usage: ~10 KB
- UI State: ~50 KB
- Search History: ~20 KB
- Tags: ~10 KB
- Layout Preferences: ~10 KB
- Notifications: ~20 KB
- Interactive Sessions: ~50 KB

**Total per user: ~1 MB**

**For 10,000 users: ~10 GB**

Very manageable!

---

## Next Steps

1. **Review this analysis** with team
2. **Prioritize state categories** (which are most critical?)
3. **Decide on sync strategy** (real-time vs periodic vs on-demand)
4. **Update implementation plan** based on priorities
5. **Begin Phase 1** (Backend schema creation)

---

**Generated:** 2025-10-14
**Author:** Claude Code Analysis
