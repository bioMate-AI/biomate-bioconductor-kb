# Comprehensive E2E Tests - Natural User Conversations

**Created**: 2026-02-09
**Purpose**: Test BioMate with realistic, natural user-agent conversations across all scientific domains

---

## Test Suites Overview

### 1. `comprehensive-workflow-tests.spec.ts`
**12 test cases** covering general workflows and user interactions:

| Test # | Domain | Scenario | Key Features |
|--------|--------|----------|--------------|
| 1 | Genomics | RNA-seq differential expression | Multi-step conversation, parameter discussion |
| 2 | Proteomics | LC-MS protein identification | Context provision, database selection |
| 3 | Molecular Biology | Primer design for PCR | Specific requirements, parameter specification |
| 4 | Quality Control | FASTQ quality analysis | Simple workflow, immediate execution |
| 5 | Sequence Analysis | Read alignment to reference | Output format discussion |
| 6 | Microbiology | Bacterial growth modeling | Data format specification |
| 7 | Error Handling | Unclear request handling | AI clarification flow |
| 8 | Multi-step | Incremental workflow building | Context retention across messages |
| 9 | Modification | Iterative workflow refinement | Tool substitution |
| 10 | History | Previous workflow access | History panel interaction |
| 11 | Complex | Multi-omics integration | Complex cross-domain workflow |
| 12 | Recommendation | Tool suggestion and selection | AI tool recommendations |

---

### 2. `domain-specific-workflows.spec.ts`
**20+ test cases** covering specialized scientific domains:

#### Structural Biology (3 tests)
- **Cryo-EM**: Single particle analysis with CryoSPARC
- **X-ray Crystallography**: Structure determination from diffraction data
- **NMR**: Protein structure from NMR data

#### Systems Biology (2 tests)
- **Network Analysis**: Protein-protein interaction networks
- **Pathway Enrichment**: GO and KEGG pathway analysis

#### Synthetic Biology (2 tests)
- **Circuit Design**: Genetic toggle switch optimization
- **Metabolic Engineering**: Pathway design with FBA

#### Biochemistry (3 tests)
- **Enzyme Kinetics**: Michaelis-Menten parameter fitting
- **Protein Stability**: Circular dichroism analysis
- **Binding Assay**: ITC thermodynamic analysis

#### Pharmacology (3 tests)
- **Drug Screening**: High-throughput compound analysis
- **ADME Prediction**: Pharmacokinetic property prediction
- **Molecular Docking**: Protein-ligand binding prediction

#### Edge Cases (3 tests)
- **Ambiguous Requests**: AI clarification behavior
- **Unsupported Analysis**: Limitation explanation
- **Correction Flow**: User correction handling

---

## Natural Conversation Patterns Tested

### 1. **Progressive Detail Addition**
```typescript
User: "I want to analyze protein-protein interactions"
AI: [Asks for details]
User: "The data is from a yeast two-hybrid screen"
AI: [Asks for analysis type]
User: "I need to filter for high-confidence interactions"
AI: [Generates workflow]
```

### 2. **Clarification Flow**
```typescript
User: "Analyze some data"
AI: "What type of data do you have?"
User: "It's RNA sequencing data from a time series"
AI: [Generates appropriate workflow]
```

### 3. **Correction Handling**
```typescript
User: "Align protein sequences"
AI: [Starts protein alignment workflow]
User: "Sorry, I meant DNA sequences, not proteins"
AI: [Adjusts to DNA alignment]
```

### 4. **Parameter Discussion**
```typescript
User: "Design primers for PCR"
AI: [Generates primer design workflow]
User: "I need primers with Tm around 60°C"
AI: [Updates parameters]
User: "What other parameters can I configure?"
AI: [Lists available parameters]
```

### 5. **Context Retention**
Tests verify AI remembers earlier conversation context when generating workflows.

---

## Running the Tests

### Prerequisites

**1. Services Running**:
```bash
# Terminal 1: Backend
cd /home/yzhang/biomate/backend
source .venv/bin/activate
python scripts/galaxy-main.py serve --host=0.0.0.0 --port=8081

# Terminal 2: Frontend
cd /home/yzhang/biomate/frontend
export GALAXY_API_KEY=7341822cd19cddaa49139f6cccae8c76
export GALAXY_URL=http://localhost:8081
npm run dev
```

**2. Environment Variables**:
```bash
export BIOMATE_URL="http://localhost:5000"
export GALAXY_URL="http://localhost:8081"
export GALAXY_API_KEY="<your-key>"
```

---

### Run All Tests

```bash
cd /home/yzhang/biomate/frontend

# Run all comprehensive tests
npm run e2e -- comprehensive-workflow-tests.spec.ts

# Run domain-specific tests
npm run e2e -- domain-specific-workflows.spec.ts

# Run both suites
npm run e2e -- comprehensive-workflow-tests.spec.ts domain-specific-workflows.spec.ts

# Run with UI (see browser)
npm run e2e -- --headed

# Run specific test
npm run e2e -- comprehensive-workflow-tests.spec.ts -g "RNA-seq"
```

### Run UX Feedback Regression Matrix

```bash
cd /home/yzhang/biomate/frontend

# Run both feedback suites with CI-style summary output
BIOMATE_URL=http://localhost:5000 npm run e2e:feedback:matrix

# Run release-gate mode (critical suites only, no SKIP allowed in critical logs)
FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5000 npm run e2e:feedback:matrix
```

Includes:
- `feedback-regression.e2e.ts` (core feedback flow)
- `feedback-branches-deterministic.e2e.ts` (deterministic confusion/download branches)
- `feedback-real-ui-strict.e2e.ts` (strict real-UI-only feedback gate; no direct fallback POST)
- `real-user-visual-evaluation.e2e.ts` (real UI-based visual evaluation with screenshots/report)
- `pm-user-stories-comprehensive.e2e.ts` (PM user stories and acceptance criteria validation)

Release mode includes only:
- `feedback-real-ui-strict.e2e.ts`
- `pm-user-stories-comprehensive.e2e.ts`

### Evidence-First Artifact Package (Detailed Logs + Data)

Each matrix run now writes a stable artifact package under:

- `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>.txt` (run metadata)
- `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>/matrix-console.log` (full execution log)
- `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>/<suite>.console.log` (suite logs)
- `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>/<suite>.results.json` (Playwright JSON report)
- `frontend/e2e/matrix-runs/feedback-matrix-run-<timestamp>/<suite>.artifacts/attachments-manifest.json` (copied evidence index)
- copied attachments per suite (`trace.zip`, `video.webm`, `test-finished-1.png`, custom evidence JSON)

Key-point checks now explicitly covered and inspectable:
- **Chats**: prompt and chat-step logs in console + visual report JSON.
- **Workflow**: workflow card/title and state (`RUNNING/COMPLETED/...`) in visual report.
- **Execution process**: ordered timeline + per-suite durations in metadata and logs.
- **Parameters**: parameter panel visibility evidence in visual report.
- **Output/result surfaces**: output section/action visibility in visual report and PM suite.
- **Reports**: per-suite Playwright JSON reports and trace/video artifacts.

CI workflow:
- GitHub Actions workflow: `UX Feedback Regression CI`
- File: `.github/workflows/feedback-e2e-matrix.yml`
- Trigger: path-filtered `pull_request` and `push` (main/master), plus `workflow_dispatch`

---

### Generate HTML Report

```bash
# Run tests with reporter
npm run e2e -- --reporter=html

# View report
open playwright-report/index.html
```

---

## Test Features

### Realistic User Simulation

**Natural Typing**:
- Variable typing speed (30-70ms per character)
- Simulates human typing patterns
- Pauses between messages

**Human-Like Interactions**:
- Incremental detail provision
- Follow-up questions
- Corrections and clarifications
- Context-dependent queries

### Comprehensive Coverage

**Workflow Types**:
- Simple (FastQC)
- Complex (Multi-omics integration)
- Domain-specific (Cryo-EM, ITC, Docking)
- Cross-domain (Systems biology)

**User Behaviors**:
- Clear requests
- Vague requests → clarification
- Progressive refinement
- Tool selection
- Parameter configuration
- Error correction

**AI Behaviors Tested**:
- Workflow generation
- Clarification requests
- Tool recommendations
- Parameter suggestions
- Limitation explanations
- Context retention

---

## Expected Outcomes

### Success Criteria

**Workflow Generation**:
- ✅ Workflow card appears within 60s
- ✅ Workflow contains relevant tools
- ✅ Step count matches complexity

**AI Interaction**:
- ✅ AI asks clarifying questions for vague requests
- ✅ AI retains context across messages
- ✅ AI provides tool recommendations
- ✅ AI explains limitations gracefully

**Execution**:
- ✅ Run button appears when prerequisites met
- ✅ Status updates visible
- ✅ Results accessible after completion

### Common Patterns

**Successful Flow**:
```
1. User request → AI response (3-5s)
2. Workflow generation (5-30s depending on complexity)
3. Workflow card display
4. Parameter discussion (if needed)
5. Execution (if run)
6. Results access
```

**Clarification Flow**:
```
1. Vague request → AI asks for details
2. User provides details → AI generates workflow
```

**Error Handling**:
```
1. Unsupported request → AI explains alternatives
2. User accepts alternative → Workflow generated
```

---

## Debugging Failed Tests

### Quick Troubleshooting (Matrix)

Common failures and exact rerun/debug commands:

- **`Workflow card not visible` / generation timeout**
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/real-user-visual-evaluation.e2e.ts --project chromium --headed`
- **`post-run survey not visible`**
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-regression.e2e.ts --project chromium --headed`
- **`deterministic branch assertion failed`**
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/feedback-branches-deterministic.e2e.ts --project chromium --headed`
- **`PM user story acceptance check failed`**
  - `BIOMATE_URL=http://localhost:5310 npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts --project chromium --headed`
- **`Need trace for root cause`**
  - `npx playwright show-trace e2e/test-results/<failed-test-folder>/trace.zip`
- **`Rerun full matrix`**
  - `BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`

### Test Fails at Workflow Generation

**Check**:
1. AI response in console logs
2. Whether AI asked clarification (expected for vague requests)
3. Backend logs for workflow generation errors

**Common Causes**:
- Tool search didn't find relevant tools
- LLM couldn't parse user intent
- Template reuse confidence too low

### Test Fails at Execution

**Check**:
1. Prerequisites validation
2. Parameter configuration requirements
3. Input data availability

**Common Causes**:
- Missing input datasets
- Required parameters not configured
- Tool installation failures

### AI Doesn't Ask for Clarification

**This may be expected**:
- AI might generate a workflow based on assumptions
- Check if workflow matches intent
- Not all vague requests need clarification

---

## Test Maintenance

### Adding New Test Cases

**Template**:
```typescript
test('Domain: Specific workflow type', async ({ page }) => {
  const chatInput = page.locator('textarea, input[type="text"]').first();

  // Step 1: Natural user request
  console.log('User: [describe what user does]');
  await typeNaturally(chatInput, 'Natural language request');
  await chatInput.press('Enter');
  await waitForAIResponse(page);

  // Step 2: Verify workflow
  const workflowCard = page.locator('[class*="workflow"]').first();
  await expect(workflowCard).toBeVisible({ timeout: 15000 });
  console.log('✓ Workflow generated');

  // Step 3: Additional interactions (optional)
  // ...
});
```

### Updating for UI Changes

**If UI selectors change**:
1. Update locator patterns in test
2. Check `comprehensive-workflow-tests.spec.ts` helper functions
3. Update wait conditions if loading behavior changes

---

## Related Documentation

- **E2E Test Plan**: `/backend/E2E_TEST_PLAN_WITH_PARAMETER_VALIDATION_2025-10-14.md`
- **Previous Findings**: `/backend/20260203_UI_E2E_TEST_FINDINGS_FINAL.md`
- **Workflow Markers Test**: `workflow-markers-validation.spec.ts`
- **Original Integration**: `/codex_work/20260209_nextflow_integration_complete.md`

---

## Coverage Matrix

| Domain | Simple | Medium | Complex | Total |
|--------|--------|--------|---------|-------|
| Genomics | ✅ FastQC | ✅ RNA-seq | ✅ Multi-omics | 3 |
| Proteomics | - | ✅ LC-MS | - | 1 |
| Structural Biology | - | ✅ Cryo-EM | ✅ X-ray | 2 |
| Systems Biology | - | ✅ Network | ✅ Pathway | 2 |
| Synthetic Biology | - | ✅ Circuit | ✅ Metabolic | 2 |
| Biochemistry | ✅ Enzyme | ✅ CD | ✅ ITC | 3 |
| Pharmacology | ✅ Screening | ✅ Docking | ✅ ADME | 3 |
| Molecular Biology | ✅ Primer | ✅ Align | - | 2 |
| Microbiology | ✅ Growth | - | - | 1 |
| **Total Tests** | **7** | **13** | **12** | **32+** |

---

## Performance Expectations

| Test Type | Expected Duration |
|-----------|-------------------|
| Simple workflows | 10-20 seconds |
| Medium complexity | 30-60 seconds |
| Complex workflows | 60-120 seconds |
| Full suite (32 tests) | 30-45 minutes |

**Note**: Times include natural typing delays and AI response waits.

---

**Status**: ✅ Ready to Run
**Next**: Start services and execute test suites

