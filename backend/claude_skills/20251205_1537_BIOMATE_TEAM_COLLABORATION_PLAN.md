# BioMate Team Collaboration UI Plan

**Date**: 2025-12-05 15:37
**Goal**: Extend BioMate project functionality with Galaxy-powered team collaboration

---

## Current State Analysis

### BioMate Project System (Existing)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CURRENT BIOMATE PROJECTS                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ✅ IMPLEMENTED                          ❌ NOT IMPLEMENTED                 │
│  ─────────────────                       ──────────────────                 │
│  • Project CRUD                          • Backend API                      │
│  • Name, description, category           • Database persistence             │
│  • Project instructions/context          • Multi-user sharing               │
│  • Status (active/archived/completed)    • Team collaboration               │
│  • Progress tracking (0-100%)            • Access control/permissions       │
│  • Chat sessions per project             • File upload/download             │
│  • Document attachments                  • Real-time collaboration          │
│  • Tags and search                       • Audit logging                    │
│  • Last activity tracking                • Project templates                │
│                                                                             │
│  Storage: localStorage (client-side)     Needed: PostgreSQL + Galaxy        │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Galaxy Collaboration Features (Available to Leverage)

| Galaxy API | Purpose | BioMate Integration |
|------------|---------|---------------------|
| **Histories** | Analysis workspaces | Map to project runs |
| **Workflows** | Reusable pipelines | Shared team workflows |
| **Groups** | User collections | Team membership |
| **Sharing** | Access control | Project permissions |
| **Libraries** | Shared data | Team data repository |

---

## Proposed Architecture

### Three-Layer Integration

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              BIOMATE UI LAYER                               │
│                         (React + TypeScript)                                │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  Projects   │  │    Teams    │  │  Workflows  │  │    Data     │        │
│  │    Page     │  │    Page     │  │    Page     │  │   Library   │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │               │
│         └────────────────┴────────────────┴────────────────┘               │
│                                   │                                        │
├───────────────────────────────────┼────────────────────────────────────────┤
│                              BIOMATE API                                   │
│                         (Express + PostgreSQL)                             │
├───────────────────────────────────┼────────────────────────────────────────┤
│                                   │                                        │
│   ┌───────────────────────────────┴───────────────────────────────┐       │
│   │                      BioMate Backend                           │       │
│   │                                                                │       │
│   │  • Project Management (extended from current)                  │       │
│   │  • Team/Member Management                                      │       │
│   │  • Permission System                                           │       │
│   │  • Activity Logging                                            │       │
│   │  • Notifications                                               │       │
│   └───────────────────────────────┬───────────────────────────────┘       │
│                                   │                                        │
├───────────────────────────────────┼────────────────────────────────────────┤
│                           GALAXY API LAYER                                 │
│                         (BioBlend / REST API)                             │
├───────────────────────────────────┼────────────────────────────────────────┤
│                                   │                                        │
│   ┌───────────────────────────────┴───────────────────────────────┐       │
│   │                      Galaxy Server                             │       │
│   │                                                                │       │
│   │  • Histories (analysis runs)                                   │       │
│   │  • Workflows (pipelines)                                       │       │
│   │  • Groups (team mapping)                                       │       │
│   │  • Libraries (shared data)                                     │       │
│   │  • Job Queue (execution)                                       │       │
│   └────────────────────────────────────────────────────────────────┘       │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Database Schema Extension

### New Tables for Collaboration

```sql
-- Teams table
CREATE TABLE teams (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    owner_id UUID NOT NULL REFERENCES users(id),
    galaxy_group_id VARCHAR(255),  -- Link to Galaxy group
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Team members with roles
CREATE TABLE team_members (
    team_id UUID REFERENCES teams(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) NOT NULL DEFAULT 'member',  -- 'owner', 'admin', 'member', 'viewer'
    joined_at TIMESTAMP DEFAULT NOW(),
    PRIMARY KEY (team_id, user_id)
);

-- Extended projects table
CREATE TABLE projects (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    instructions TEXT,
    status VARCHAR(50) DEFAULT 'active',
    category VARCHAR(100),
    progress INTEGER DEFAULT 0,

    -- Ownership
    owner_id UUID NOT NULL REFERENCES users(id),
    team_id UUID REFERENCES teams(id),  -- NULL = personal project

    -- Galaxy integration
    galaxy_history_id VARCHAR(255),     -- Primary Galaxy history
    galaxy_workflow_ids TEXT[],         -- Associated workflows

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_activity TIMESTAMP DEFAULT NOW()
);

-- Project sharing (beyond team)
CREATE TABLE project_shares (
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    permission VARCHAR(50) NOT NULL DEFAULT 'view',  -- 'view', 'edit', 'admin'
    shared_at TIMESTAMP DEFAULT NOW(),
    shared_by UUID REFERENCES users(id),
    PRIMARY KEY (project_id, user_id)
);

-- Project activity log
CREATE TABLE project_activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id),
    action VARCHAR(100) NOT NULL,  -- 'created', 'updated', 'ran_workflow', 'added_file', etc.
    details JSONB,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Project files (linked to Galaxy datasets)
CREATE TABLE project_files (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID REFERENCES projects(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    type VARCHAR(50),
    size BIGINT,
    galaxy_dataset_id VARCHAR(255),  -- Link to Galaxy dataset
    galaxy_history_id VARCHAR(255),
    uploaded_by UUID REFERENCES users(id),
    uploaded_at TIMESTAMP DEFAULT NOW(),
    description TEXT
);

-- Notifications
CREATE TABLE notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(100) NOT NULL,  -- 'project_shared', 'workflow_completed', 'mention', etc.
    title VARCHAR(255),
    message TEXT,
    data JSONB,
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);
```

---

## UI Components Plan

### 1. Enhanced Project Page

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  🔬 Projects                                              [+ New Project]   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                         │
│  │ My Projects │  │Team Projects│  │Shared w/ Me │                         │
│  └─────────────┘  └─────────────┘  └─────────────┘                         │
│                                                                             │
│  Search: [________________________]  Sort: [Recent ▼]  Filter: [All ▼]     │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  🧬 RNA-Seq Analysis Pipeline                              [Active]  │  │
│  │  ─────────────────────────────────────────────────────────────────── │  │
│  │  Differential expression analysis for patient samples                │  │
│  │                                                                      │  │
│  │  Team: Genomics Lab  │  👥 5 members  │  📁 12 files  │  💬 8 chats  │  │
│  │  Progress: [████████████████░░░░] 80%                                │  │
│  │                                                                      │  │
│  │  Last activity: 2 hours ago by @jane                                 │  │
│  │  Tags: [RNA-seq] [DESeq2] [Cancer]                                   │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  🔬 Proteomics DIA-NN                                    [Active]    │  │
│  │  ─────────────────────────────────────────────────────────────────── │  │
│  │  Mass spec data analysis with DIA-NN                                 │  │
│  │                                                                      │  │
│  │  Team: Proteomics Core  │  👥 3 members  │  📁 45 files  │  💬 3 chats│  │
│  │  Progress: [████████░░░░░░░░░░░░] 40%                                │  │
│  │                                                                      │  │
│  │  ⏳ Running: DIA-NN quantification (ETA: 2h 15m)                     │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2. Project Detail Page (Enhanced)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  ← Back to Projects    RNA-Seq Analysis Pipeline              [⚙️] [Share] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐         │
│  │  Chat  │ │  Files │ │Workflows│ │  Runs  │ │  Team  │ │Activity│         │
│  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘         │
│                                                                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  [Chat Tab - Current Implementation]                                        │
│  ───────────────────────────────────                                        │
│  • Multiple chat sessions                                                   │
│  • Project context in sidebar                                               │
│                                                                             │
│  [Files Tab - NEW]                                                          │
│  ─────────────────                                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  📁 Input Data                                                       │  │
│  │    ├── 📄 samples.csv (2.1 KB) - @john, 2 days ago                   │  │
│  │    ├── 📄 sample_R1.fastq.gz (4.2 GB) - @jane, 1 day ago             │  │
│  │    └── 📄 sample_R2.fastq.gz (4.1 GB) - @jane, 1 day ago             │  │
│  │                                                                      │  │
│  │  📁 Results                                                          │  │
│  │    ├── 📄 deseq2_results.csv (156 KB) - workflow, 3 hours ago        │  │
│  │    ├── 📊 volcano_plot.png (89 KB) - workflow, 3 hours ago           │  │
│  │    └── 📄 gene_counts.tsv (12.4 MB) - workflow, 3 hours ago          │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  [Workflows Tab - NEW]                                                      │
│  ─────────────────────                                                      │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Available Workflows                                   [+ Import]    │  │
│  │                                                                      │  │
│  │  🔄 RNA-seq Analysis (DESeq2)                          [Run ▶]       │  │
│  │     5 steps • Last run: 3 hours ago • Used 12 times                  │  │
│  │                                                                      │  │
│  │  🔄 FastQC Quality Control                             [Run ▶]       │  │
│  │     2 steps • Last run: 1 day ago • Used 45 times                    │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  [Runs Tab - NEW]                                                           │
│  ────────────────                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Workflow Runs                                                       │  │
│  │                                                                      │  │
│  │  ✅ RNA-seq Analysis       Completed    3 hours ago     @jane        │  │
│  │  ⏳ DIA-NN Quantification  Running      ETA: 2h 15m     @john        │  │
│  │  ❌ FastQC                 Failed       1 day ago       @jane        │  │
│  │  ✅ RNA-seq Analysis       Completed    2 days ago      @john        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  [Team Tab - NEW]                                                           │
│  ────────────────                                                           │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Team Members                                          [+ Invite]    │  │
│  │                                                                      │  │
│  │  👤 John Smith (you)       Owner        john@lab.edu                 │  │
│  │  👤 Jane Doe               Admin        jane@lab.edu                 │  │
│  │  👤 Bob Wilson             Member       bob@lab.edu                  │  │
│  │  👤 Alice Chen             Viewer       alice@lab.edu                │  │
│  │                                                                      │  │
│  │  Shared With (outside team):                                         │  │
│  │  👤 Dr. External           Viewer       external@other.edu           │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  [Activity Tab - NEW]                                                       │
│  ────────────────────                                                       │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  Recent Activity                                                     │  │
│  │                                                                      │  │
│  │  🔄 @jane ran "RNA-seq Analysis" workflow          3 hours ago       │  │
│  │  📁 @jane uploaded 3 files                         1 day ago         │  │
│  │  💬 @john commented in "Analysis Discussion"       1 day ago         │  │
│  │  ✏️ @jane updated project instructions             2 days ago        │  │
│  │  👤 @bob was added to the team                     3 days ago        │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 3. Teams Page (NEW)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  👥 Teams                                                   [+ Create Team] │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐                                          │
│  │  My Teams   │  │  All Teams  │                                          │
│  └─────────────┘  └─────────────┘                                          │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  🔬 Genomics Lab                                              Owner  │  │
│  │  ─────────────────────────────────────────────────────────────────── │  │
│  │  RNA-seq and variant analysis team                                   │  │
│  │                                                                      │  │
│  │  👥 8 members  │  📊 5 projects  │  🔄 12 workflows                  │  │
│  │                                                                      │  │
│  │  Members: @john, @jane, @bob, +5 more                                │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │  🧪 Proteomics Core                                          Member  │  │
│  │  ─────────────────────────────────────────────────────────────────── │  │
│  │  Mass spectrometry and protein analysis                              │  │
│  │                                                                      │  │
│  │  👥 4 members  │  📊 3 projects  │  🔄 6 workflows                   │  │
│  │                                                                      │  │
│  │  Members: @alice, @charlie, @you, +1 more                            │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 4. Share Dialog (NEW)

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  Share "RNA-Seq Analysis Pipeline"                                    [X]  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Add people or teams                                                        │
│  ┌──────────────────────────────────────────────────────┐  ┌──────────┐    │
│  │ Enter email or team name...                          │  │  Invite  │    │
│  └──────────────────────────────────────────────────────┘  └──────────┘    │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  People with access                                                         │
│                                                                             │
│  👤 John Smith (Owner)                                          Owner ▼    │
│  👤 Genomics Lab (Team)                                         Edit ▼     │
│  👤 jane@lab.edu                                                Edit ▼     │
│  👤 external@other.edu                                          View ▼     │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  Link sharing                                                               │
│                                                                             │
│  ○ Restricted - Only people with access can open                           │
│  ● Anyone with the link can view                                           │
│                                                                             │
│  🔗 https://biomate.app/project/abc123?token=xyz                           │
│                                                         [Copy Link]        │
│                                                                             │
│  ─────────────────────────────────────────────────────────────────────────  │
│                                                                             │
│  ☐ Sync with Galaxy group                                                   │
│    Automatically share Galaxy histories with team members                   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## API Endpoints Plan

### BioMate Backend API

```typescript
// Teams
POST   /api/teams                    // Create team
GET    /api/teams                    // List my teams
GET    /api/teams/:id                // Get team details
PUT    /api/teams/:id                // Update team
DELETE /api/teams/:id                // Delete team
POST   /api/teams/:id/members        // Add member
DELETE /api/teams/:id/members/:userId // Remove member
PUT    /api/teams/:id/members/:userId // Update member role

// Projects (extended)
POST   /api/projects                 // Create project
GET    /api/projects                 // List accessible projects
GET    /api/projects/:id             // Get project details
PUT    /api/projects/:id             // Update project
DELETE /api/projects/:id             // Delete project
POST   /api/projects/:id/share       // Share project
DELETE /api/projects/:id/share/:userId // Revoke share
GET    /api/projects/:id/activity    // Get activity log
POST   /api/projects/:id/files       // Upload file
GET    /api/projects/:id/files       // List files
DELETE /api/projects/:id/files/:fileId // Delete file

// Galaxy integration
POST   /api/projects/:id/galaxy/sync       // Sync with Galaxy
GET    /api/projects/:id/galaxy/histories  // Get Galaxy histories
POST   /api/projects/:id/galaxy/workflows  // Run Galaxy workflow
GET    /api/projects/:id/galaxy/jobs       // Get job status

// Notifications
GET    /api/notifications            // Get user notifications
PUT    /api/notifications/:id/read   // Mark as read
DELETE /api/notifications/:id        // Delete notification
```

### Galaxy API Integration

```python
# Galaxy service wrapper
class GalaxyProjectService:
    def __init__(self, galaxy_url: str, api_key: str):
        self.gi = GalaxyInstance(galaxy_url, api_key)

    # History management
    def create_project_history(self, project_name: str) -> str:
        """Create Galaxy history for project"""
        return self.gi.histories.create_history(name=f"BioMate: {project_name}")

    def share_history_with_team(self, history_id: str, user_emails: List[str]):
        """Share history with team members"""
        for email in user_emails:
            self.gi.histories.update_history(history_id, share_with=[email])

    # Workflow execution
    def run_workflow(self, workflow_id: str, history_id: str, inputs: dict):
        """Run workflow in project history"""
        return self.gi.workflows.invoke_workflow(
            workflow_id,
            inputs=inputs,
            history_id=history_id
        )

    # Group management
    def create_team_group(self, team_name: str, user_ids: List[str]) -> str:
        """Create Galaxy group for team"""
        group = self.gi.groups.create_group(team_name, user_ids)
        return group['id']

    def sync_team_members(self, group_id: str, user_ids: List[str]):
        """Sync team members with Galaxy group"""
        current = self.gi.groups.get_group_users(group_id)
        # Add/remove members to match
```

---

## Implementation Phases

### Phase 1: Database & Backend (2-3 weeks)

1. Create database migration for new tables
2. Implement project API with sharing
3. Add team management API
4. Add activity logging
5. Basic notification system

### Phase 2: Galaxy Integration (2-3 weeks)

1. Galaxy service wrapper
2. History sync with projects
3. Workflow execution integration
4. File upload to Galaxy datasets
5. Job status polling

### Phase 3: UI Components (3-4 weeks)

1. Enhanced Projects page with tabs
2. Team management UI
3. Share dialog component
4. Activity feed component
5. Workflow runs view
6. File browser with Galaxy integration

### Phase 4: Real-time Features (2 weeks)

1. WebSocket for live updates
2. Job completion notifications
3. @mentions in chat
4. Presence indicators

---

## File Changes Summary

### New Files

```
frontend/
├── client/src/
│   ├── components/
│   │   ├── share-dialog.tsx           # NEW
│   │   ├── team-member-list.tsx       # NEW
│   │   ├── activity-feed.tsx          # NEW
│   │   ├── workflow-runner.tsx        # NEW
│   │   ├── file-browser.tsx           # NEW
│   │   └── notification-bell.tsx      # NEW
│   ├── pages/
│   │   └── teams.tsx                  # NEW
│   └── lib/
│       ├── teams.ts                   # NEW
│       └── galaxy.ts                  # NEW

backend/
├── lib/galaxy/
│   └── project_sync.py               # NEW
└── migrations/
    └── 0001_add_collaboration.sql    # NEW
```

### Modified Files

```
frontend/
├── client/src/
│   ├── pages/
│   │   ├── projects.tsx              # MODIFY: Add tabs
│   │   └── project-detail.tsx        # MODIFY: Add new tabs
│   ├── components/
│   │   └── create-project-dialog.tsx # MODIFY: Add team selection
│   └── lib/
│       └── projects.ts               # MODIFY: Add API calls
├── shared/
│   └── schema.ts                     # MODIFY: Add team schemas
└── server/
    └── routes.ts                     # MODIFY: Add new endpoints
```

---

## Summary

| Feature | Effort | Priority |
|---------|--------|----------|
| Database schema for teams | 1 week | High |
| Project sharing API | 1 week | High |
| Team management UI | 2 weeks | High |
| Galaxy history sync | 2 weeks | High |
| Share dialog | 1 week | High |
| Activity feed | 1 week | Medium |
| Workflow runner UI | 2 weeks | Medium |
| File browser | 2 weeks | Medium |
| Real-time updates | 2 weeks | Low |
| Notifications | 1 week | Low |

**Total Estimated Time**: 8-10 weeks for full implementation
