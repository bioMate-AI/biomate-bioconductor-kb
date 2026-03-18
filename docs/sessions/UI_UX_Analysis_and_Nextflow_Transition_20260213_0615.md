# UI/UX Analysis and Nextflow-First Transition Plan
**Date:** February 13, 2026
**Author:** BioMate AI Assistant

## 1. Executive Summary

Following a comprehensive End-to-End (E2E) test and detailed code review of the frontend-backend interaction, we have identified that while the system is technically capable of running Nextflow, the **User Experience (UX) is currently fragmented**. The distinction between "Galaxy Workflows" and "Nextflow Pipelines" is exposed to the user, creating unnecessary cognitive load.

**Strategic Shift:** Per the latest directive, we will move to a **"Nextflow-Only" / "Hidden Engine" model**. The user will simply interact with "Workflows," and the system will default to Nextflow execution without exposing the underlying Galaxy orchestration details (`.ga` files).

---

## 2. E2E Test & UI Audit Findings

### 2.1. Automated API Test Results
We performed an automated validation (`verify_nextflow_api.ts`) against the running backend (`localhost:8081`).

*   **System Health:** ✅ **PASSED**. Both Frontend (port 5000) and Backend (port 8081) are healthy and communicating.
*   **Intent Routing:** ❌ **UNSTABLE**.
    *   **Issue:** Natural language requests like *"Generate RNA-seq analysis"* were frequently misclassified as `tool_search` (returning a list of tools) or `general_question` (asking for clarification) instead of triggering the Workflow Generator.
    *   **Cause:** The `EnhancedIntentClassifier` is too conservative (requires >95% confidence). It often defaults to fallback behaviors rather than committing to generation.
    *   **Impact:** Users have to "fight" the chatbot to get a workflow generated.

### 2.2. UI/UX Interaction Analysis
*   **Visual Fragmentation:** The UI currently has two distinct modes:
    1.  **Standard Artifact:** Used for Galaxy workflows (linear step list).
    2.  **Nextflow Viewer:** Used for Nextflow (Phase-based, grouped steps).
    *   *Critique:* This exposes implementation details. The "Phase-based" view is superior for scientific users and should be the standard.
*   **Terminology:** The interface references "Galaxy," "Tool IDs," and ".ga files."
    *   *Critique:* Irrelevant to a user focused on Nextflow. These should be internal implementation details only.
*   **Progress Tracking:**
    *   **Strength:** The granular status tracking (pending → running → completed) works well.
    *   **Strength:** The "AutoFix" integration (appearing contextually on failure) is excellent.

---

## 3. The "Nextflow-First" Transition Plan

**Objective:** Unify the experience. To the user, BioMate is a Nextflow execution platform. The "Galaxy" engine is merely the invisible driver.

### 3.1. Backend Changes (Prioritize Nextflow)
We must force the AI to assume Nextflow generation is the goal.

1.  **Default to Nextflow Engine:**
    *   In `ai_assistant.py`, change the default `execution_engine` from `'galaxy'` to `'nextflow'`.
    *   Update `UnifiedWorkflowGenerator` to skip the "Galaxy .ga generation" fallback path unless explicitly requested for debugging.
    
2.  **Aggressive Intent Routing:**
    *   Tune `EnhancedIntentClassifier` to map keywords like "analyze", "pipeline", "workflow", "process" directly to `workflow_generation`.
    *   Lower the confidence threshold for generating a Nextflow draft (it's better to show a draft than ask generic questions).

3.  **Silence "Galaxy" Metadata:**
    *   Ensure API responses (`/api/chat`) do not return metadata fields containing "galaxy_id" or "ga_file" in the user-facing `message` or `suggestions`.

### 3.2. Frontend Changes (Unified UI)

1.  **Single Workflow View (The "Phase" View):**
    *   Deprecate the old linear step list (`WorkflowArtifact`).
    *   Use the **Phase-Card** component (currently `NextflowWorkflowViewer`) for **ALL** workflows.
    *   If a workflow is simple (linear), it simply renders as a single "Execution Phase."

2.  **Terminology Cleanup:**
    *   Rename "Nextflow Pipeline" → **"Analysis Workflow"**.
    *   Rename "Tool ID" → **"Component"**.
    *   Remove any UI badges or text saying "Galaxy Engine" or ".ga".

3.  **Simplified Chat Interaction:**
    *   **Before:** User asks -> AI asks "Do you want Galaxy or Nextflow?" -> User selects.
    *   **After:** User asks -> AI says "Generating Analysis Workflow..." -> Displays Nextflow Phase View immediately.

---

## 4. Implementation Checklist

### Phase 1: Backend Routing Fix (Immediate)
- [ ] Modify `ai_assistant.py` to set `execution_engine='nextflow'` as hard default.
- [ ] Update `NextflowWorkflowGenerator` to be the primary generation path.
- [ ] bypass `EnhancedIntentClassifier` strictness for domain-specific queries (e.g., if query contains "fastq" or "rna-seq", force workflow generation).

### Phase 2: UI Unification
- [ ] Refactor `ChatInterface.tsx` to always render `NextflowWorkflowViewer` for workflow artifacts.
- [ ] Update `NextflowWorkflowViewer` to handle simple linear workflows (wrapping them in a default phase) so it can display anything.
- [ ] Audit `chat-message.tsx` to remove "Galaxy" strings from output text.

### Phase 3: Verification
- [ ] Re-run `verify_nextflow_api.ts`.
    *   *Success Criteria:* "Generate RNA-seq" returns a `workflow_type: 'nextflow'` JSON immediately, without follow-up questions.

---

**Next Steps for Team:**
Please review this plan. Upon approval, I will begin with **Phase 1 (Backend Routing Fix)** to solve the test failure observed today.
