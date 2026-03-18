# BioMate Current Status & Next Steps
**Date**: November 3, 2025
**Context**: After completing nfcore_metadata integration

---

## ✅ What We Just Completed

### Enhanced Tool Search with Dual Metadata (Week 2-3 of Roadmap)

**Completed Work**:
1. ✅ **Enhanced tool metadata** - `scientific_context` + `nfcore_metadata` integration
2. ✅ **Dual-source scoring algorithm** - 7 weighted factors
3. ✅ **Workflow validation bonus** - +15% for nf-core tools
4. ✅ **Database verification** - 1,841 tools with nfcore, 9,210 with scientific_context
5. ✅ **API endpoints** - `/api/tool_search/enhanced` and `/api/tool_search/validate`
6. ✅ **Comprehensive documentation** - All implementation details documented

**Database Coverage**:
```
Total tools: 9,212
├─ scientific_context: 9,210 (99.9%) - Decision-making guidance
├─ nfcore_metadata: 1,841 (20.0%) - Workflow validation
└─ BOTH sources: 1,839 (19.9%) - Optimal coverage
```

**This Completes**: Phase 1, Week 3 from IFLOW_ACE_BIOMATE_INTEGRATION roadmap ✅

---

## 🎯 Where This Fits in the iFlow+ACE Architecture

From `IFLOW_ACE_BIOMATE_INTEGRATION_20251030.md`:

```
┌─────────────────────────────────────┐
│   User Interface Layer (iFlow)      │  ← Week 1 (PENDING)
│   /workflow, @files, $agents        │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│   Workflow Orchestration            │  ← Week 2 (PENDING)
│   Route to agents, manage context   │
└─────────────────────────────────────┘
              ↓
┌──────────────┬──────────────────────┐
│ iFlow Agents │  ACE Learning System │  ← Week 4-8 (PENDING)
│ (Domain)     │  (Intelligence)      │
├──────────────┼──────────────────────┤
│ Tool DB      │  Enhanced Search     │  ← Week 3 (✅ COMPLETE)
│ (Metadata)   │  (scientific+nfcore) │
└──────────────┴──────────────────────┘
```

**What We Have**: The **knowledge foundation** (enhanced search with dual metadata)
**What We Need**: The **interface layer** (iFlow commands) and **learning layer** (ACE agents)

---

## 🚀 Recommended Next Steps

### Option A: User Profile & Context Persistence (Week 3 from INTEGRATION_PLAN)

**Why**: Makes enhanced search immediately useful
**What**: Store user preferences to auto-apply context

**Tasks**:
1. Add PostgreSQL user profile schema
   ```sql
   CREATE TABLE user_profiles (
     user_id UUID PRIMARY KEY,
     research_domain VARCHAR(50),  -- proteomics, genomics, etc.
     expertise_level VARCHAR(20),   -- beginner, intermediate, expert
     default_data_type VARCHAR(50), -- DIA-LCMS, RNA-seq, etc.
     preferences JSONB
   );
   ```

2. Add session context tracking
   ```sql
   CREATE TABLE search_sessions (
     session_id UUID PRIMARY KEY,
     user_id UUID REFERENCES user_profiles(user_id),
     context JSONB,
     created_at TIMESTAMP,
     last_active TIMESTAMP
   );
   ```

3. Update frontend to:
   - Store user profile during onboarding
   - Auto-inject context into enhanced search
   - Track search sessions for ACE learning

**Outcome**: Enhanced search works automatically with user context

---

### Option B: iFlow-Style Interface (Week 1 from ACE Integration)

**Why**: Provides intuitive UX for proteomics workflows
**What**: Implement slash commands and file references

**Tasks**:
1. **Slash Command Parser**
   ```typescript
   /workflow dia-proteomics      // Generate DIA workflow
   /workflow rna-seq              // Generate RNA-seq workflow
   /init                          // Initialize from project context
   /playbook show tool-selection  // Show learned rules
   ```

2. **File Reference Syntax**
   ```typescript
   @data/experiment.raw           // Include file in context
   @folder/project/               // Include directory structure
   ```

3. **Agent Call Syntax**
   ```typescript
   $tool-selector What tools for DIA data?
   $parameter-expert Configure DIA-NN parameters
   ```

4. **UI Implementation**
   - Command autocomplete
   - File picker for @ references
   - Agent selector for $ calls

**Outcome**: User-friendly interface for workflow generation

---

### Option C: ACE Playbook Foundation (Week 2 from ACE Integration)

**Why**: Enables automated learning from search feedback
**What**: Create playbook data structure and seeding

**Tasks**:
1. **PostgreSQL Playbook Schema**
   ```sql
   CREATE TABLE playbook_bullets (
     bullet_id VARCHAR(50) PRIMARY KEY,
     section VARCHAR(100),  -- tool_selection_rules, parameter_guidelines
     content TEXT,
     helpful_count INT DEFAULT 0,
     harmful_count INT DEFAULT 0,
     source VARCHAR(20),    -- 'expert_seed' or 'learned'
     created_at TIMESTAMP,
     updated_at TIMESTAMP,
     metadata JSONB
   );
   ```

2. **Seed Expert Knowledge** (50-100 bullets)
   ```json
   {
     "tool_selection_rules": [
       {
         "id": "tool-dia-001",
         "content": "DIA data from Orbitrap → DIA-NN (fast) or Spectronaut (accurate). Never MaxQuant (DDA-only).",
         "helpful": 0,
         "harmful": 0,
         "source": "expert_seed"
       }
     ]
   }
   ```

3. **Playbook API**
   - GET /api/playbook/:section - Retrieve rules
   - POST /api/playbook/feedback - Track helpful/harmful
   - PUT /api/playbook/delta - Add learned rules

4. **TypeScript Interfaces**
   ```typescript
   interface Playbook {
     version: string;
     sections: Record<string, PlaybookSection>;
     lastUpdated: Date;
   }

   interface PlaybookBullet {
     id: string;
     content: string;
     helpful: number;
     harmful: number;
     source: 'expert_seed' | 'learned';
   }
   ```

**Outcome**: Foundation for ACE learning system

---

## 📊 Decision Matrix

| Option | Immediate User Value | Enables ACE Learning | Implementation Time | Dependencies |
|--------|---------------------|---------------------|-------------------|--------------|
| **A: User Profiles** | ⭐⭐⭐⭐⭐ High | ⭐⭐⭐ Medium | 1 week | Enhanced search (✅) |
| **B: iFlow Interface** | ⭐⭐⭐⭐ High | ⭐⭐ Low | 2 weeks | None |
| **C: ACE Playbook** | ⭐⭐ Low | ⭐⭐⭐⭐⭐ High | 2 weeks | User feedback loop |

---

## 💡 Recommended Path

### Phase A: Make Enhanced Search Useful NOW (1-2 weeks)

**Week 1: User Context Persistence**
1. Add user_profiles table
2. Add session tracking
3. Update frontend to auto-inject context
4. Test with real proteomics queries

**Week 2: Feedback Collection**
1. Add search_feedback table
2. Track which tools users select
3. Track which explanations are helpful
4. Log search patterns

**Outcome**: Enhanced search works automatically + data for ACE learning

### Phase B: Build iFlow Interface (2-3 weeks)

**Week 3-4: Command System**
1. Implement slash command parser
2. Create /workflow commands
3. Add file reference system
4. Build UI autocomplete

**Week 5: Agent System**
1. Create .iflow/agents/ structure
2. Implement $tool-selector agent
3. Implement $parameter-expert agent
4. Connect to enhanced search

**Outcome**: Intuitive proteomics workflow interface

### Phase C: Enable ACE Learning (3-4 weeks)

**Week 6-7: Playbook System**
1. Create playbook schema
2. Seed 50 expert rules
3. Build playbook API
4. Implement bullet tracking

**Week 8-9: ACE Agents**
1. Implement Generator (uses playbook)
2. Implement Reflector (analyzes failures)
3. Implement Curator (updates playbook)
4. Run offline training

**Outcome**: Self-improving workflow system

---

## 🎯 Immediate Next Action

Based on current completion of enhanced search with dual metadata:

**RECOMMENDED: Start with Option A (User Profiles)**

**Why**:
1. ✅ Shortest path to user value (1 week)
2. ✅ Makes enhanced search immediately useful
3. ✅ Provides data for ACE learning later
4. ✅ No complex UI work needed yet
5. ✅ Builds on what we just completed

**Tasks for Week 1**:
```
Day 1-2: Design & implement user_profiles table
Day 3: Add session context tracking
Day 4: Frontend integration (auto-inject context)
Day 5: Testing with real proteomics workflows
```

**Expected Result**:
```bash
# User logs in, sets profile once:
Profile: {
  research_domain: "proteomics",
  expertise_level: "intermediate",
  default_data_type: "DIA-LCMS"
}

# From then on, all searches auto-use this context:
Search: "differential expression"
→ Enhanced search auto-applies proteomics context
→ Returns DIA-specific tools
→ Filters out incompatible tools
```

---

## 📝 Summary

**What We Completed**: Enhanced search with scientific_context + nfcore_metadata ✅

**What's Next**: Three parallel paths available
- **A: User Profiles** (RECOMMENDED) - Immediate value, 1 week
- **B: iFlow Interface** - Better UX, 2 weeks
- **C: ACE Playbook** - Learning foundation, 2 weeks

**Long-term Vision**: All three combine into self-improving proteomics platform

**Awaiting Decision**: Which path to prioritize first?

---

## 🔗 References

- Enhanced Search Implementation: `ENHANCED_SEARCH_IMPLEMENTATION_20251031.md`
- nfcore Integration Summary: `NFCORE_INTEGRATION_SUMMARY.md`
- Integration Architecture: `IFLOW_ACE_BIOMATE_INTEGRATION_20251030.md`
- Detailed Roadmap: `INTEGRATION_PLAN_20251031.md`
