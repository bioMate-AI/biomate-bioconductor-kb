# BioMate LLM Parameter Generation + E2E Testing Implementation Plan

**Created**: 2025-10-14
**Status**: IN PROGRESS
**Estimated Completion**: 2025-11-04 (3 weeks)

---

## 📅 Timeline Overview

| Phase | Duration | Dates | Status |
|-------|----------|-------|--------|
| Phase 1: Backend LLM Parameter Generation | 3 days | Oct 14-16 | 🟡 IN PROGRESS |
| Phase 2: Frontend Parameter Preview | 2 days | Oct 17-18 | ⚪ PENDING |
| Phase 3: E2E Test Framework Setup | 3 days | Oct 19-21 | ⚪ PENDING |
| Phase 4: Test Cases Implementation | 7 days | Oct 22-28 | ⚪ PENDING |
| Phase 5: Test Execution & Reporting | 5 days | Oct 29-Nov 4 | ⚪ PENDING |

---

## Phase 1: Backend LLM Parameter Generation (Oct 14-16)

### Objectives
- Add LLM-based parameter inference for dataset query tools
- Return parameters with confidence scores and reasoning
- Integrate into unified workflow generation pipeline

### Tasks

#### Day 1 (Oct 14) - Core Implementation
- [x] Create implementation plan document
- [ ] Create `llm_parameter_generator.py` module
- [ ] Implement `_format_parameter_schema()` helper
- [ ] Implement `_llm_generate_parameters()` method
- [ ] Implement `_validate_generated_parameters()` method
- [ ] Write unit tests for parameter generation

#### Day 2 (Oct 15) - Integration
- [ ] Modify `galaxy_workflow_generator.py` to use LLM parameter generation
- [ ] Update `_build_tool_state()` to call parameter generator for data source tools
- [ ] Update `_build_galaxy_workflow_json()` to track generated parameters
- [ ] Modify `ai_assistant.py` response format to include parameter metadata
- [ ] Update API endpoint to return `generated_parameters` field

#### Day 3 (Oct 16) - Testing & Validation
- [ ] Write integration tests for workflow generation with parameters
- [ ] Test with sample queries (e.g., "Get mouse genes from Ensembl")
- [ ] Validate parameter confidence scores
- [ ] Test fallback to defaults on LLM failure
- [ ] Document API changes

### Deliverables
1. `backend/lib/galaxy/ai/llm_parameter_generator.py` (NEW)
2. Updated `backend/lib/galaxy/ai/galaxy_workflow_generator.py`
3. Updated `backend/lib/galaxy/ai/ai_assistant.py`
4. Updated `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`
5. Unit and integration tests
6. API documentation

---

## Phase 2: Frontend Parameter Preview (Oct 17-18)

### Objectives
- Create visual parameter preview dialog
- Allow user to review and edit LLM-generated parameters
- Integrate into chat workflow

### Tasks

#### Day 4 (Oct 17) - Component Development
- [ ] Create `ParameterPreviewDialog` component
- [ ] Implement parameter display with confidence badges
- [ ] Add inline editing for each parameter
- [ ] Implement confidence-based highlighting (<0.7 = yellow/red)
- [ ] Add confirm/cancel actions
- [ ] Write component tests

#### Day 5 (Oct 18) - Integration
- [ ] Integrate dialog into `chat-interface.tsx`
- [ ] Update `useWorkflowSync` hook to handle parameter state
- [ ] Add state management for pending workflows
- [ ] Test full flow: chat → parameters → workflow view
- [ ] UI/UX testing and refinement

### Deliverables
1. `frontend/client/src/components/parameter-preview-dialog.tsx` (NEW)
2. Updated `frontend/client/src/components/chat-interface.tsx`
3. Updated `frontend/client/src/hooks/useWorkflowSync.ts`
4. Component tests
5. UI/UX documentation

---

## Phase 3: E2E Test Framework Setup (Oct 19-21)

### Objectives
- Set up Playwright for browser automation
- Create page objects for UI testing
- Build test infrastructure with screenshots and video recording

### Tasks

#### Day 6 (Oct 19) - Playwright Setup
- [ ] Install Playwright and dependencies
- [ ] Create `backend/tests/e2e_ui/` directory structure
- [ ] Write `conftest.py` with fixtures (browser, page, screenshots)
- [ ] Configure video recording
- [ ] Test basic navigation and screenshot capture

#### Day 7 (Oct 20) - Page Objects
- [ ] Create `ChatPage` page object (message sending, response checking)
- [ ] Create `WorkflowPage` page object (workflow validation, execution)
- [ ] Create `ExecutionPage` page object (progress monitoring, output validation)
- [ ] Write helper methods for common actions

#### Day 8 (Oct 21) - Test Utilities
- [ ] Create `ScreenshotManager` (organize screenshots by test case)
- [ ] Create `WorkflowValidator` (validate workflow structure)
- [ ] Create `ReportGenerator` (HTML report with embedded screenshots)
- [ ] Write sample test to validate framework

### Deliverables
1. Complete test framework directory structure
2. `conftest.py` with Playwright configuration
3. Page objects (ChatPage, WorkflowPage, ExecutionPage)
4. Test utilities (screenshot manager, validator, report generator)
5. Framework documentation

---

## Phase 4: Test Cases Implementation (Oct 22-28)

### Objectives
- Implement 10 comprehensive test cases
- Each test includes full workflow execution validation
- Capture visual evidence at every step

### Test Cases

#### Day 9 (Oct 22) - Proteomics Tests
- [ ] Test Case 1: DIA LC-MS Proteomics
  - User query, workflow generation, parameter preview, execution, output validation
- [ ] Test Case 2: Peptide Drug QC
  - Quality control workflow with purity calculations

#### Day 10 (Oct 23) - Genomics Tests
- [ ] Test Case 3: Single Cell RNA-Seq
  - scRNA-seq analysis with permutation testing
- [ ] Test Case 4: CRISPR Screen
  - Gene essentiality analysis with MAGeCK

#### Day 11 (Oct 24) - Structural Biology & Genomics
- [ ] Test Case 5: Cryo-EM Structure
  - 3D reconstruction workflow
- [ ] Test Case 6: Whole Genome Sequencing
  - Variant calling with GATK best practices

#### Day 12 (Oct 25) - Imaging & Multi-Omics
- [ ] Test Case 7: Digital Pathology
  - TIL quantification and survival analysis
- [ ] Test Case 8: Multi-Omics Integration
  - Complex multi-branch workflow

#### Day 13 (Oct 26) - Microbiome & Spatial
- [ ] Test Case 9: Metagenomics
  - Taxonomic and functional profiling
- [ ] Test Case 10: Spatial Transcriptomics
  - Spatial domain identification

#### Days 14-15 (Oct 27-28) - Refinement
- [ ] Review all test cases for completeness
- [ ] Add additional assertions and validations
- [ ] Optimize test execution time
- [ ] Create test data fixtures

### Deliverables
1. 10 complete test case files
2. `test_data/test_inputs.json` with test specifications
3. Mock data files (if needed)
4. Test documentation

---

## Phase 5: Test Execution & Reporting (Oct 29-Nov 4)

### Objectives
- Run all tests with visual browser automation
- Generate comprehensive test report
- Document findings and issues

### Tasks

#### Day 16 (Oct 29) - Initial Test Run
- [ ] Run all 10 tests in sequence
- [ ] Capture screenshots and videos
- [ ] Document any failures

#### Day 17 (Oct 30) - Bug Fixes Round 1
- [ ] Fix critical issues from test run
- [ ] Re-run failed tests
- [ ] Update test assertions if needed

#### Day 18 (Oct 31) - Full Test Suite Run
- [ ] Run complete test suite (all 10 tests)
- [ ] Collect all screenshots and videos
- [ ] Validate workflow execution results

#### Day 19 (Nov 1) - Report Generation
- [ ] Generate HTML test report with screenshots
- [ ] Create summary metrics (pass rate, parameter accuracy, execution times)
- [ ] Create video compilation of successful runs

#### Day 20 (Nov 2-4) - Documentation & Delivery
- [ ] Write final test report document
- [ ] Document any limitations or known issues
- [ ] Create user guide for running tests
- [ ] Archive test artifacts (screenshots, videos, logs)

### Deliverables
1. Complete test execution results
2. HTML test report with visual evidence
3. Test videos (10 full workflow executions)
4. Summary metrics and analysis
5. Final documentation

---

## 🎯 Success Criteria

### Backend Parameter Generation
- ✅ LLM generates parameters for all data source tools
- ✅ Confidence scores returned for each parameter
- ✅ Parameter validation against tool schema
- ✅ Graceful fallback to defaults on failure
- ✅ API returns `generated_parameters` in response

### Frontend Parameter Preview
- ✅ Dialog displays generated parameters
- ✅ Confidence badges visible (high/medium/low)
- ✅ User can edit parameters before confirmation
- ✅ Workflow syncs to workflow builder after confirmation
- ✅ Low-confidence parameters highlighted

### E2E Test Framework
- ✅ Playwright automation works reliably
- ✅ Page objects cover all UI interactions
- ✅ Screenshots captured at every key step
- ✅ Video recording of full test runs
- ✅ HTML report generation with visual evidence

### Test Execution
- ✅ All 10 test cases pass (or issues documented)
- ✅ Workflows execute successfully end-to-end
- ✅ Parameter inference accuracy >80% for critical parameters
- ✅ Workflow structure validated (correct tools, steps, connections)
- ✅ Output files validated (format, content)

### Overall Goals
- ✅ **Visual Observability**: Watch entire process unfold in browser
- ✅ **Full E2E Validation**: From user input to workflow execution outputs
- ✅ **Reproducibility**: Tests can be re-run at any time
- ✅ **Documentation**: Complete test report with evidence

---

## 📊 Key Metrics to Track

### Parameter Generation Metrics
- Parameter inference accuracy (expected vs actual)
- Average confidence scores per parameter type
- LLM failure rate and fallback usage
- Inference time per workflow

### Workflow Generation Metrics
- Workflow generation success rate
- Average number of steps per use case
- Tool selection accuracy
- Workflow generation time

### Test Execution Metrics
- Test pass rate (target: 90%+)
- Average workflow execution time
- Container installation success rate
- Output validation pass rate

### User Experience Metrics
- Time from query to workflow display
- Parameter preview interaction time
- Workflow modification rate (how often users edit)

---

## 🛠️ Technology Stack

### Backend
- Python 3.9+
- OpenAI GPT-4 (for parameter inference)
- Galaxy workflow engine
- pytest (testing)

### Frontend
- React + TypeScript
- Material-UI (parameter dialog)
- TanStack Query (API calls)

### Testing
- Playwright (browser automation)
- pytest-playwright (integration)
- pytest-html (reporting)

### Tools
- Git (version control)
- GitHub (issue tracking)
- VS Code (development)

---

## 📝 Risk Assessment

### High Risk
- **LLM Reliability**: Parameter inference may fail or produce incorrect values
  - *Mitigation*: Fallback to defaults, confidence thresholds, user review
- **Workflow Execution Time**: E2E tests may be slow (30+ minutes per test)
  - *Mitigation*: Run tests in parallel, use mock data for faster iterations

### Medium Risk
- **Browser Automation Stability**: Playwright tests may be flaky
  - *Mitigation*: Add explicit waits, retry failed tests, increase timeouts
- **Tool Availability**: Some tools may not be installed or working
  - *Mitigation*: On-demand installation, skip optional steps, document limitations

### Low Risk
- **Frontend Integration**: Parameter dialog may need UI/UX adjustments
  - *Mitigation*: Iterative design, user feedback, A/B testing

---

## 📚 Documentation Deliverables

1. **Implementation Guide**: How to implement LLM parameter generation
2. **API Documentation**: Updated API endpoints with parameter metadata
3. **Test Framework Guide**: How to write and run E2E tests
4. **Test Report**: Visual test report with screenshots and metrics
5. **User Guide**: How to use parameter preview feature
6. **Developer Guide**: Code structure and architecture decisions

---

## 🔄 Progress Tracking

**Last Updated**: 2025-10-14

**Current Status**: Phase 1 - Day 1 (Backend LLM Parameter Generation)

**Next Milestone**: Complete Phase 1 by Oct 16

---

## 📧 Contact & Support

**Project Lead**: Claude Code + User (Jingqi Wang)
**Repository**: /Users/jingqiwang/biomate
**Branch**: frontend_stronger
**Issue Tracking**: GitHub Issues (TBD)

---

**Document Version**: 1.0
**Created**: 2025-10-14
**Purpose**: Master plan for LLM parameter generation and comprehensive E2E testing implementation
