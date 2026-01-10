# BioMate Frontend & Integration Plan: Citations, Progressive Tuning & Test Harness UI

**Date**: 2025-12-19 15:15
**Status**: Approved for implementation

## Executive Summary

This plan details frontend modifications, API enhancements, and comprehensive testing to support three new backend features:
1. **Citation & Best Practices UI** - Display citations, copy methods sections, export BibTeX
2. **Progressive Tuning UI** - Pilot run configuration, progress monitoring, full run estimation
3. **Benchmark Comparison UI** - View tool comparisons, export reports

**Backend Status**: Already implemented in:
- `/lib/galaxy/ai/tool_knowledge_provider.py` - Citations & best practices
- `/lib/galaxy/ai/methods_generator.py` - Publication-ready methods text
- `/lib/galaxy/ai/progressive_tuning.py` - Pilot runs & parameter optimization
- `/lib/galaxy/ai/test_harness/` - Benchmark framework

---

## Part 1: API Response Enhancement

### 1.1 Current API Response (`/api/ai_assistant/generate_workflow`)

```json
{
  "success": true,
  "workflow_ga": {...},
  "source": "template_reuse|template_adapted|from_scratch",
  "confidence": 0.85,
  "message": "..."
}
```

### 1.2 Enhanced API Response

**File to modify**: `/home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`

```python
class WorkflowGenerationResponse(BaseModel):
    # Existing fields
    success: bool
    workflow_ga: Dict[str, Any]
    source: str
    confidence: float
    message: str

    # NEW: Citation fields
    citations: List[CitationData] = []
    methods_section: Optional[MethodsSectionData] = None

    # NEW: Progressive tuning fields
    pilot_run_suggested: bool = False
    tuning_config: Optional[TuningConfigData] = None
    parameter_recommendations: Dict[str, ParameterRecommendation] = {}

class CitationData(BaseModel):
    tool_id: str
    tool_name: str
    doi: Optional[str]
    pmid: Optional[str]
    title: str
    authors: List[str]
    year: Optional[int]
    formatted_apa: str
    formatted_short: str
    formatted_bibtex: str

class MethodsSectionData(BaseModel):
    text: str
    style: str  # 'apa', 'short', 'numbered'
    tools_cited: List[str]
    tools_missing_citations: List[str]
```

### 1.3 New API Endpoints

Add to `/home/yzhang/biomate/backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/ai_assistant/pilot/start` | POST | Start pilot run |
| `/api/ai_assistant/pilot/{pilot_id}/status` | GET | Get pilot status |
| `/api/ai_assistant/pilot/{pilot_id}/estimate` | GET | Get full run estimate |
| `/api/ai_assistant/citations/export` | POST | Export citations as BibTeX |
| `/api/ai_assistant/benchmarks/{scenario}` | GET | Get benchmark results |

---

## Part 2: Frontend Components

### 2.1 New Components to Create

#### A. Citation Panel (`citation-panel.tsx`)
**Path**: `/home/yzhang/biomate/frontend/client/src/components/citation-panel.tsx`

```
┌─────────────────────────────────────────────────────────────┐
│ 📚 Citations (5/6 tools)                            [Copy] ▼│
├─────────────────────────────────────────────────────────────┤
│ ▼ STAR Aligner                                              │
│   Dobin et al., 2013. STAR: ultrafast universal RNA-seq...  │
│   DOI: 10.1093/bioinformatics/bts635  PMID: 23104886       │
│   [Copy APA] [Copy BibTeX]                                  │
├─────────────────────────────────────────────────────────────┤
│ ▼ DESeq2                                                    │
│   Love et al., 2014. Moderated estimation of fold change... │
│   ...                                                        │
├─────────────────────────────────────────────────────────────┤
│ Methods Section                                    [Copy] ▼ │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ Quality assessment was performed using FastQC (Andrews, │ │
│ │ 2010). Reads were aligned using STAR (Dobin et al.,     │ │
│ │ 2013) with default parameters...                        │ │
│ └─────────────────────────────────────────────────────────┘ │
│ [Export All as BibTeX]                                      │
└─────────────────────────────────────────────────────────────┘
```

**Props**:
```typescript
interface CitationPanelProps {
  citations: Citation[];
  methodsSection?: MethodsSection;
  isCollapsed?: boolean;
  onCopy: (text: string, format: 'apa' | 'bibtex') => void;
  onExportBibTeX: () => void;
}
```

#### B. Pilot Run Panel (`pilot-run-panel.tsx`)
**Path**: `/home/yzhang/biomate/frontend/client/src/components/pilot-run-panel.tsx`

```
┌─────────────────────────────────────────────────────────────┐
│ 🧪 Pilot Run Configuration                                  │
├─────────────────────────────────────────────────────────────┤
│ Your dataset has 100 samples. Running a pilot on a subset  │
│ helps optimize parameters before full analysis.             │
│                                                             │
│ Pilot Size:  [====○=========] 10%  (10 samples)            │
│                                                             │
│ Sampling Strategy:  [Stratified ▼]                         │
│                     ○ Random                                │
│                     ● Stratified (preserves group balance) │
│                     ○ First N samples                       │
│                                                             │
│ Estimated pilot time: ~5 minutes                           │
│                                                             │
│         [Cancel]  [Start Pilot Run]                        │
└─────────────────────────────────────────────────────────────┘
```

After pilot completes:
```
┌─────────────────────────────────────────────────────────────┐
│ ✓ Pilot Run Complete                                        │
├─────────────────────────────────────────────────────────────┤
│ Pilot Metrics:                                              │
│   Runtime: 4m 32s    Memory: 8.2 GB    Quality: 94%        │
│                                                             │
│ Full Run Estimate (100 samples):                           │
│   ⏱ ~45 minutes    💾 ~12 GB RAM    💰 ~$0.85             │
│   Confidence: 80%                                          │
│                                                             │
│ Parameter Recommendations:                                  │
│   threads: 8 → 16 (2x faster)                  [Apply]     │
│   outSAMtype: Unsorted → Sorted (recommended) [Apply]      │
│                                                             │
│   [Re-run Pilot]  [Apply All & Run Full Analysis]          │
└─────────────────────────────────────────────────────────────┘
```

**Props**:
```typescript
interface PilotRunPanelProps {
  workflowId: string;
  totalSamples: number;
  onStartPilot: (config: TuningConfig) => Promise<void>;
  onComplete: (result: PilotResult, estimate: FullRunEstimate) => void;
  onProceedToFull: (params: Record<string, any>) => void;
}
```

#### C. Parameter Recommendations Badge (`parameter-recommendation-badge.tsx`)
**Path**: `/home/yzhang/biomate/frontend/client/src/components/parameter-recommendation-badge.tsx`

Small badge shown next to parameters with recommendations:
```
threads: 8  [💡 16 recommended]
```

### 2.2 Existing Components to Modify

#### A. `workflow-artifact.tsx`
**Path**: `/home/yzhang/biomate/frontend/client/src/components/workflow-artifact.tsx`

**Changes**:
1. Add citation badge: `📚 5 citations` next to confidence badge
2. Add "View Citations" button
3. Add "Pilot Run" button (when dataset > 20 samples)
4. Show parameter recommendation indicators on steps

```typescript
// Add to props
interface WorkflowArtifactProps {
  // ...existing
  citations?: Citation[];
  methodsSection?: MethodsSection;
  parameterRecommendations?: Record<string, ParameterRecommendation>;
  pilotRunSuggested?: boolean;
  onViewCitations?: () => void;
  onStartPilotRun?: () => void;
}
```

#### B. `parameter-dialog.tsx`
**Path**: `/home/yzhang/biomate/frontend/client/src/components/parameter-dialog.tsx`

**Changes**:
1. Show recommendation badge next to parameters
2. Add "Use Recommended" button per parameter
3. Add "Apply All Recommendations" button at bottom

#### C. `chat-message.tsx`
**Path**: `/home/yzhang/biomate/frontend/client/src/components/chat-message.tsx`

**Changes**:
1. Render CitationPanel when `message.metadata.citations` exists
2. Show pilot run suggestion banner when appropriate

#### D. `chat-interface.tsx`
**Path**: `/home/yzhang/biomate/frontend/client/src/components/chat-interface.tsx`

**Changes**:
1. Add pilot run state management
2. Add citation export handlers
3. Update workflow generation response handling

---

## Part 3: TypeScript Types

### Add to `/home/yzhang/biomate/frontend/shared/schema.ts`

```typescript
// Citation types
export const citationSchema = z.object({
  tool_id: z.string(),
  tool_name: z.string(),
  doi: z.string().optional(),
  pmid: z.string().optional(),
  title: z.string(),
  authors: z.array(z.string()),
  year: z.number().optional(),
  formatted_apa: z.string(),
  formatted_short: z.string(),
  formatted_bibtex: z.string(),
});

export const methodsSectionSchema = z.object({
  text: z.string(),
  style: z.enum(['apa', 'short', 'numbered']),
  tools_cited: z.array(z.string()),
  tools_missing_citations: z.array(z.string()),
});

// Progressive tuning types
export const tuningConfigSchema = z.object({
  pilot_fraction: z.number().min(0.05).max(0.3),
  sampling_strategy: z.enum(['random', 'stratified', 'first_n']),
  strata_column: z.string().optional(),
});

export const pilotResultSchema = z.object({
  pilot_id: z.string(),
  status: z.enum(['running', 'complete', 'failed']),
  progress: z.number(),
  runtime_seconds: z.number().optional(),
  peak_memory_gb: z.number().optional(),
  quality_metrics: z.record(z.number()).optional(),
});

export const fullRunEstimateSchema = z.object({
  estimated_runtime_seconds: z.number(),
  estimated_runtime_display: z.string(),
  estimated_memory_gb: z.number(),
  estimated_cost_usd: z.number().optional(),
  confidence: z.number(),
});

export const parameterRecommendationSchema = z.object({
  name: z.string(),
  recommended_value: z.any(),
  current_value: z.any().optional(),
  confidence: z.number(),
  source: z.enum(['benchmark', 'protocol', 'best_practice']),
  reason: z.string().optional(),
});
```

---

## Part 4: User Experience Flows

### 4.1 Citation Flow

```
User generates workflow
         │
         ▼
┌─────────────────────────┐
│ WorkflowArtifact shows  │
│ "📚 5 citations" badge  │
└───────────┬─────────────┘
            │ click
            ▼
┌─────────────────────────┐
│ CitationPanel opens     │
│ - List all tool cites   │
│ - Methods section       │
│ - Copy/Export buttons   │
└─────────────────────────┘
```

### 4.2 Pilot Run Flow

```
User clicks "Run" on large dataset
         │
         ▼
┌─────────────────────────┐
│ System suggests pilot:  │
│ "Run pilot first?"      │
│ [Yes] [No, run full]    │
└───────────┬─────────────┘
            │ Yes
            ▼
┌─────────────────────────┐
│ PilotRunPanel opens     │
│ - Configure sampling    │
│ - Set pilot fraction    │
│ - Start pilot           │
└───────────┬─────────────┘
            │
            ▼
┌─────────────────────────┐
│ Pilot executes          │
│ - Progress bar          │
│ - Real-time metrics     │
└───────────┬─────────────┘
            │ complete
            ▼
┌─────────────────────────┐
│ Show results:           │
│ - Pilot metrics         │
│ - Full run estimate     │
│ - Parameter suggestions │
│ [Re-run] [Proceed Full] │
└─────────────────────────┘
```

---

## Part 5: Comprehensive Test Plan

### 5.1 Frontend Unit Tests (Jest/Vitest)

**Location**: `/home/yzhang/biomate/frontend/client/src/components/__tests__/`

| Test File | Test Cases |
|-----------|------------|
| `citation-panel.test.tsx` | Renders citations, formats APA/BibTeX, copies to clipboard, exports file |
| `pilot-run-panel.test.tsx` | Renders config, validates inputs, shows progress, displays results |
| `parameter-recommendation-badge.test.tsx` | Shows badge, applies recommendation |
| `workflow-artifact.test.tsx` | Shows citation badge, pilot button, integrates new features |

**Example Tests**:
```typescript
// citation-panel.test.tsx
describe('CitationPanel', () => {
  it('renders citation list with correct count');
  it('formats citations in APA style correctly');
  it('formats citations in BibTeX style correctly');
  it('copies single citation to clipboard');
  it('copies methods section to clipboard');
  it('exports all citations as .bib file');
  it('shows missing citation warning for tools without citations');
  it('collapses/expands correctly');
});

// pilot-run-panel.test.tsx
describe('PilotRunPanel', () => {
  it('calculates pilot size from fraction');
  it('validates minimum sample count');
  it('shows sampling strategy options');
  it('starts pilot run on submit');
  it('displays progress during execution');
  it('shows metrics on completion');
  it('displays full run estimate');
  it('applies parameter recommendations');
});
```

### 5.2 Backend API Tests (pytest)

**Location**: `/home/yzhang/biomate/backend/tests/`

| Test File | Test Cases |
|-----------|------------|
| `test_ai_assistant_api.py` | generate_workflow returns citations, methods section |
| `test_pilot_run_api.py` | start, status, estimate endpoints |
| `test_citation_export_api.py` | BibTeX export |

**Example Tests**:
```python
# test_ai_assistant_api.py
class TestWorkflowGenerationWithCitations:
    def test_response_includes_citations(self):
        """Verify citations are included for tools with known citations."""

    def test_response_includes_methods_section(self):
        """Verify auto-generated methods section is included."""

    def test_parameter_recommendations_included(self):
        """Verify parameter recommendations for known tools."""

# test_pilot_run_api.py
class TestPilotRunEndpoints:
    def test_start_pilot_run(self):
        """Test starting a pilot run with valid config."""

    def test_get_pilot_status(self):
        """Test retrieving pilot run status."""

    def test_estimate_full_run(self):
        """Test full run estimation from pilot results."""
```

### 5.3 Integration Tests

**Location**: `/home/yzhang/biomate/frontend/server/__tests__/`

```typescript
// ai-assistant-integration.test.ts
describe('AI Assistant API Integration', () => {
  describe('Workflow Generation', () => {
    it('returns citations for workflow with known tools');
    it('returns empty citations for unknown tools');
    it('generates methods section with correct citations');
  });

  describe('Pilot Run', () => {
    it('starts pilot and returns pilot_id');
    it('reports progress via status endpoint');
    it('returns metrics on completion');
    it('estimates full run correctly');
  });
});
```

### 5.4 E2E Tests

**Location**: `/home/yzhang/biomate/backend/tests/e2e_frontend_features.py`

```python
class TestCitationE2E:
    def test_01_generate_workflow_shows_citations(self):
        """E2E: Generate workflow and verify citation badge appears."""

    def test_02_view_citations_panel(self):
        """E2E: Click citation badge and verify panel opens."""

    def test_03_copy_citation_to_clipboard(self):
        """E2E: Copy citation and verify clipboard content."""

    def test_04_copy_methods_section(self):
        """E2E: Copy methods section and verify format."""

    def test_05_export_bibtex_file(self):
        """E2E: Export citations and verify .bib file download."""

class TestPilotRunE2E:
    def test_01_pilot_suggestion_appears(self):
        """E2E: Large dataset triggers pilot suggestion."""

    def test_02_configure_pilot_run(self):
        """E2E: Configure sampling and start pilot."""

    def test_03_pilot_progress_updates(self):
        """E2E: Verify real-time progress during pilot."""

    def test_04_pilot_results_display(self):
        """E2E: Verify metrics and estimate shown after pilot."""

    def test_05_apply_recommendations(self):
        """E2E: Apply parameter recommendations."""

    def test_06_proceed_to_full_run(self):
        """E2E: Proceed to full run after pilot."""

class TestParameterRecommendationsE2E:
    def test_01_recommendation_badges_shown(self):
        """E2E: Parameter dialog shows recommendation badges."""

    def test_02_apply_single_recommendation(self):
        """E2E: Apply single parameter recommendation."""

    def test_03_apply_all_recommendations(self):
        """E2E: Apply all recommendations at once."""
```

### 5.5 Test Data Requirements

| Test Type | Data Needed |
|-----------|-------------|
| Citation tests | Mock workflow with tools: STAR, DESeq2, FastQC |
| Pilot run tests | Dataset with 100+ samples, stratification column |
| Recommendations | Tool with known best practices (STAR: threads) |

---

## Part 6: Implementation Phases

### Phase 1: Backend API Enhancement (COMPLETED 2025-12-19)
- [x] Modify `generate_workflow` response to include citations/methods
- [x] Add pilot run endpoints (`/api/ai_assistant/pilot/start`, `status`, `estimate`)
- [x] Add citation export endpoints (`/api/ai_assistant/citations/export`, `methods`)
- [x] Add benchmark endpoint (`/api/ai_assistant/benchmarks/{scenario}`)
- [x] Write backend API tests (22 tests passing)

### Phase 2: TypeScript Types (COMPLETED 2025-12-19)
- [x] Add citation types to `schema.ts` (citationSchema, methodsSectionSchema)
- [x] Add pilot run types to `schema.ts` (tuningConfigSchema, pilotResultSchema, fullRunEstimateSchema)
- [x] Add parameter recommendation types (parameterRecommendationSchema)
- [x] Add enhanced workflow response schema (workflowGenerationResponseSchema)

### Phase 3: New Components (COMPLETED 2025-12-19)
- [x] Create `citation-panel.tsx` - Collapsible panel with APA/BibTeX copy, export
- [x] Create `pilot-run-panel.tsx` - Config UI, progress display, estimates, recommendations
- [x] Create `parameter-recommendation-badge.tsx` - Inline badges with popover details
- [ ] Write component unit tests (TODO)

### Phase 4: Component Integration (COMPLETED 2025-12-19)
- [x] Modify `workflow-artifact.tsx` - Added citation badge, pilot run button, integrated panels
- [x] Modify `parameter-dialog.tsx` - Added recommendation support with "Apply All" button
- [ ] Modify `chat-message.tsx` (Optional - can be done later)
- [ ] Modify `chat-interface.tsx` (Optional - can be done later)

### Phase 5: Testing & Polish (IN PROGRESS)
- [x] Backend API tests - 22 tests passing in `test_ai_assistant_api_citations.py`
- [ ] Frontend component unit tests
- [ ] E2E tests
- [ ] UI polish and accessibility
- [ ] Documentation

---

## Implementation Status (Updated 2025-12-19)

### Completed:
1. **Backend API** - All new endpoints implemented and tested
2. **TypeScript Types** - All schemas added to `shared/schema.ts`
3. **New Components** - citation-panel, pilot-run-panel, parameter-recommendation-badge
4. **Component Integration** - workflow-artifact and parameter-dialog updated

### Remaining:
1. Frontend component unit tests
2. E2E tests
3. Optional: chat-message.tsx and chat-interface.tsx integration

---

## Critical Files Summary

### Backend Files to Modify
| File | Changes |
|------|---------|
| `/lib/galaxy/webapps/galaxy/api/ai_assistant.py` | Add citations to response, new endpoints |
| `/lib/galaxy/ai/galaxy_workflow_generator.py` | Return citations and methods section |

### Frontend Files to Create
| File | Purpose |
|------|---------|
| `components/citation-panel.tsx` | Display and export citations |
| `components/pilot-run-panel.tsx` | Pilot configuration and results |
| `components/parameter-recommendation-badge.tsx` | Recommendation indicators |

### Frontend Files to Modify
| File | Changes |
|------|---------|
| `shared/schema.ts` | Add new type definitions |
| `components/workflow-artifact.tsx` | Citation badge, pilot button |
| `components/parameter-dialog.tsx` | Recommendation badges |
| `components/chat-message.tsx` | Citation panel integration |
| `components/chat-interface.tsx` | State management for new features |

### Test Files to Create
| File | Purpose |
|------|---------|
| `components/__tests__/citation-panel.test.tsx` | Citation panel unit tests |
| `components/__tests__/pilot-run-panel.test.tsx` | Pilot panel unit tests |
| `tests/e2e_frontend_features.py` | E2E test suite for new features |
