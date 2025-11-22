# V6 Mode Detection E2E Testing Implementation Plan

**Date:** 2025-11-07
**Status:** Approved, ready for implementation
**Location:** `/home/yzhang/biomate/backend/tests/e2e_ui/`

---

## Overview

Extend existing Playwright + pytest e2e infrastructure to test V6 hybrid mode detection with 30 real-world scenarios.

---

## Reusing Existing Infrastructure (90%)

### Already Available ✅

- ✅ **Playwright + pytest framework** - Complete test harness
- ✅ **ChatPage** - Send queries and receive responses
- ✅ **WorkflowPage** - Validate generated workflows
- ✅ **ExecutionPage** - Monitor workflow execution
- ✅ **ScreenshotManager** - Visual documentation
- ✅ **ParameterValidator** - Pattern for validation (will adapt)
- ✅ **Test data management** - Structure for expectations
- ✅ **HTML report generation** - Automated reporting

### New Components Needed (10%)

1. **ModeValidator utility** - Validate mode detection decisions
2. **Mode detection test expectations** - JSON file with 30 scenarios
3. **3 test case files** - Beginner, Intermediate, Expert tests
4. **conftest.py updates** - New fixtures and markers

---

## Implementation Steps

### Step 1: Create ModeValidator Utility

**File:** `/home/yzhang/biomate/backend/tests/e2e_ui/utilities/mode_validator.py`

**Purpose:** Validate that correct mode (iterative vs legacy) was selected for each query.

**Key Methods:**
```python
class ModeValidator:
    def __init__(self, page, expected_modes_path):
        """Initialize with Playwright page and expectations file"""

    def validate_mode_decision(self, scenario_id: str, expected_mode: str, expertise: str) -> bool:
        """
        Validate mode detection decision.

        Args:
            scenario_id: Test scenario identifier
            expected_mode: "iterative" or "legacy"
            expertise: "beginner", "intermediate", or "expert"

        Returns:
            bool: True if mode matches expectation
        """

    def extract_mode_from_response(self, response_text: str) -> str:
        """
        Parse AI response to determine which mode was selected.

        Looks for indicators like:
        - "Let me help clarify..." → iterative
        - "Here's a workflow..." → legacy
        - Presence of clarifying questions → iterative
        - Direct workflow generation → legacy
        """

    def get_mode_indicators(self) -> dict:
        """Return patterns that indicate each mode"""

    def generate_validation_report(self, results: list) -> dict:
        """
        Generate detailed validation report.

        Returns summary by expertise level, mode type, and failure patterns.
        """
```

**Implementation Notes:**
- Reuse pattern from existing `ParameterValidator` class
- Add heuristics to detect mode from response text
- Support confidence scoring similar to parameter validation
- Generate detailed failure analysis

---

### Step 2: Create Mode Detection Test Expectations

**File:** `/home/yzhang/biomate/backend/tests/e2e_ui/test_data/expected_modes.json`

**Structure:**
```json
{
  "beginner_scenarios": {
    "test_01_confused_workflow": {
      "query": "I have some samples and want to find differences",
      "expected_mode": "iterative",
      "expertise": "beginner",
      "reasoning": "Vague request with missing information requires clarification",
      "mode_indicators": [
        "What type of data",
        "What kind of analysis",
        "Let me help clarify"
      ]
    },
    "test_02_tool_uncertainty": {
      "query": "Which tool should I use for RNA sequencing?",
      "expected_mode": "iterative",
      "expertise": "beginner",
      "reasoning": "Explicit help request for tool selection",
      "mode_indicators": [
        "depends on",
        "different tools",
        "would you like"
      ]
    }
    // ... 8 more beginner scenarios
  },
  "intermediate_scenarios": {
    "test_11_standard_workflow": {
      "query": "Generate standard RNA-seq differential expression workflow",
      "expected_mode": "legacy",
      "expertise": "intermediate",
      "reasoning": "Clear request for standard workflow with specific domain",
      "mode_indicators": [
        "Here's a workflow",
        "workflow steps",
        "Click to generate"
      ]
    }
    // ... 9 more intermediate scenarios
  },
  "expert_scenarios": {
    "test_21_specific_parameters": {
      "query": "Run STAR with GRCh38, --twopassMode Basic, --quantMode GeneCounts",
      "expected_mode": "legacy",
      "expertise": "expert",
      "reasoning": "Very specific request with tool and all parameters",
      "mode_indicators": [
        "Here's a workflow",
        "STAR alignment",
        "parameters configured"
      ]
    },
    "test_22_exploration": {
      "query": "Design benchmarking workflow comparing 3 aligners",
      "expected_mode": "iterative",
      "expertise": "expert",
      "reasoning": "Exploration and comparison requires clarification",
      "mode_indicators": [
        "Which aligners",
        "What metrics",
        "design together"
      ]
    }
    // ... 8 more expert scenarios
  }
}
```

---

### Step 3: Create 3 Test Case Files

#### File 1: Beginner Scenarios

**Path:** `/home/yzhang/biomate/backend/tests/e2e_ui/test_cases/test_v6_mode_beginner.py`

```python
"""
V6 Mode Detection E2E Tests - Beginner User Scenarios

Tests mode detection accuracy for beginner users who need guidance.
Expected: High iterative mode usage (80-90%)
"""

import pytest
from playwright.sync_api import Page, expect

@pytest.mark.mode_detection
@pytest.mark.beginner
class TestV6ModeDetectionBeginner:
    """Test V6 mode detection with beginner user scenarios"""

    def test_01_confused_about_workflow(
        self,
        context,
        chat_page,
        mode_validator,
        screenshots
    ):
        """
        Scenario: User doesn't know what kind of workflow they need
        Expected: Iterative mode (clarification required)
        """
        # Send vague query
        chat_page.send_message("I have some samples and want to find differences")

        # Wait for AI response
        chat_page.wait_for_workflow_generation(timeout=15000)

        # Capture screenshot
        screenshots.capture("beginner_01_confused_workflow")

        # Validate mode detection
        result = mode_validator.validate_mode_decision(
            scenario_id="test_01_confused_workflow",
            expected_mode="iterative",
            expertise="beginner"
        )

        assert result, "Should route to iterative mode for vague beginner query"

    def test_02_tool_uncertainty(self, context, chat_page, mode_validator, screenshots):
        """
        Scenario: User asks which tool to use
        Expected: Iterative mode (tool recommendation requires dialog)
        """
        chat_page.send_message("Which tool should I use for RNA sequencing?")
        chat_page.wait_for_workflow_generation(timeout=15000)
        screenshots.capture("beginner_02_tool_uncertainty")

        result = mode_validator.validate_mode_decision(
            scenario_id="test_02_tool_uncertainty",
            expected_mode="iterative",
            expertise="beginner"
        )

        assert result, "Should route to iterative mode for tool selection help"

    # ... 8 more beginner test methods
```

#### File 2: Intermediate Scenarios

**Path:** `/home/yzhang/biomate/backend/tests/e2e_ui/test_cases/test_v6_mode_intermediate.py`

```python
"""
V6 Mode Detection E2E Tests - Intermediate User Scenarios

Tests mode detection for intermediate users with mixed requirements.
Expected: Balanced mode usage (40-60% each)
"""

import pytest

@pytest.mark.mode_detection
@pytest.mark.intermediate
class TestV6ModeDetectionIntermediate:
    """Test V6 mode detection with intermediate user scenarios"""

    def test_11_standard_workflow(self, context, chat_page, mode_validator, screenshots):
        """
        Scenario: Request for standard workflow
        Expected: Legacy mode (clear, standard request)
        """
        chat_page.send_message("Generate standard RNA-seq differential expression workflow")
        chat_page.wait_for_workflow_generation(timeout=15000)
        screenshots.capture("intermediate_11_standard_workflow")

        result = mode_validator.validate_mode_decision(
            scenario_id="test_11_standard_workflow",
            expected_mode="legacy",
            expertise="intermediate"
        )

        assert result, "Should route to legacy mode for standard workflow request"

    # ... 9 more intermediate test methods
```

#### File 3: Expert Scenarios

**Path:** `/home/yzhang/biomate/backend/tests/e2e_ui/test_cases/test_v6_mode_expert.py`

```python
"""
V6 Mode Detection E2E Tests - Expert User Scenarios

Tests mode detection for expert users with specific requirements.
Expected: Mixed usage with plan-first for exploration (30/70 split)
"""

import pytest

@pytest.mark.mode_detection
@pytest.mark.expert
class TestV6ModeDetectionExpert:
    """Test V6 mode detection with expert user scenarios"""

    def test_21_specific_parameters(self, context, chat_page, mode_validator, screenshots):
        """
        Scenario: Very specific request with all parameters
        Expected: Legacy mode (expert knows exactly what they want)
        """
        query = "Run STAR with GRCh38, --twopassMode Basic, --quantMode GeneCounts"
        chat_page.send_message(query)
        chat_page.wait_for_workflow_generation(timeout=15000)
        screenshots.capture("expert_21_specific_parameters")

        result = mode_validator.validate_mode_decision(
            scenario_id="test_21_specific_parameters",
            expected_mode="legacy",
            expertise="expert"
        )

        assert result, "Should route to legacy mode for specific expert request"

    def test_22_exploration(self, context, chat_page, mode_validator, screenshots):
        """
        Scenario: Expert wants to explore/compare options
        Expected: Iterative mode (exploration requires dialog)
        """
        chat_page.send_message("Design benchmarking workflow comparing 3 aligners")
        chat_page.wait_for_workflow_generation(timeout=15000)
        screenshots.capture("expert_22_exploration")

        result = mode_validator.validate_mode_decision(
            scenario_id="test_22_exploration",
            expected_mode="iterative",
            expertise="expert"
        )

        assert result, "Should route to iterative mode for exploration query"

    # ... 8 more expert test methods
```

---

### Step 4: Extend conftest.py

**File:** `/home/yzhang/biomate/backend/tests/e2e_ui/conftest.py`

**Add to existing conftest.py:**

```python
import json
from pathlib import Path
from utilities.mode_validator import ModeValidator

# Load expected modes
@pytest.fixture(scope="session")
def expected_modes():
    """Load expected mode detection results from JSON"""
    expected_modes_path = Path(__file__).parent / "test_data" / "expected_modes.json"
    with open(expected_modes_path, 'r') as f:
        return json.load(f)

# Mode validator fixture
@pytest.fixture(scope="class")
def mode_validator(page, expected_modes):
    """Provide mode validator for mode detection tests"""
    return ModeValidator(page, expected_modes)

# Add pytest marker
def pytest_configure(config):
    config.addinivalue_line(
        "markers",
        "mode_detection: mark test as mode detection validation test"
    )
    config.addinivalue_line(
        "markers",
        "beginner: mark test as beginner user scenario"
    )
    config.addinivalue_line(
        "markers",
        "intermediate: mark test as intermediate user scenario"
    )
    config.addinivalue_line(
        "markers",
        "expert: mark test as expert user scenario"
    )
```

---

### Step 5: Test Execution

**Commands:**

```bash
# Navigate to backend directory
cd /home/yzhang/biomate/backend

# Run all V6 mode detection tests with HTML report
pytest tests/e2e_ui/test_cases/test_v6_mode_*.py -v \
  --html=tests/e2e_ui/reports/v6_mode_detection.html \
  --self-contained-html

# Run specific category
pytest tests/e2e_ui/test_cases/test_v6_mode_beginner.py -v

# Run with markers
pytest -m "mode_detection and beginner" -v

# Run with coverage
pytest tests/e2e_ui/test_cases/test_v6_mode_*.py -v \
  --cov=lib.galaxy.ai \
  --cov-report=html
```

---

## 30 Test Scenarios Breakdown

### Beginner Scenarios (10 tests)

| Test # | Scenario | Query | Expected Mode | Reasoning |
|--------|----------|-------|---------------|-----------|
| 01 | Confused about workflow | "I have some samples and want to find differences" | Iterative | Vague, needs clarification |
| 02 | Tool uncertainty | "Which tool should I use for RNA sequencing?" | Iterative | Explicit help request |
| 03 | Missing information | "Quick RNA-seq analysis" | Iterative | Incomplete, missing details |
| 04 | Incomplete request | "I need to analyze my data" | Iterative | No domain or data type |
| 05 | First-time user | "I'm new to Galaxy, how do I start with differential expression?" | Iterative | Help request, beginner |
| 06 | Vague goal | "Process my fastq files" | Iterative | Unclear analysis goal |
| 07 | Multiple options | "Should I use STAR or HISAT2?" | Iterative | Tool comparison |
| 08 | Unclear data type | "Analyze my sequencing data" | Iterative | Ambiguous data type |
| 09 | Domain confusion | "Run proteomics on RNA-seq data" | Iterative | Conceptual error |
| 10 | Help request | "Help me design a variant calling workflow" | Iterative | Explicit help |

### Intermediate Scenarios (10 tests)

| Test # | Scenario | Query | Expected Mode | Reasoning |
|--------|----------|-------|---------------|-----------|
| 11 | Standard workflow | "Generate standard RNA-seq differential expression workflow" | Legacy | Clear standard request |
| 12 | Tool-specific + params | "Run STAR with --outSAMtype BAM Unsorted" | Legacy | Specific tool and params |
| 13 | Modification | "Modify my existing workflow to add quality filtering" | Legacy | Clear modification request |
| 14 | Comparison | "Compare DESeq2 vs edgeR for time series data" | Iterative | Needs discussion |
| 15 | Optimization | "Optimize kallisto parameters for my dataset" | Iterative | Optimization exploration |
| 16 | Multi-step | "Run QC, alignment, and quantification for 12 samples" | Legacy | Clear multi-step pipeline |
| 17 | Parameter tuning | "Adjust HISAT2 splice site parameters" | Iterative | Tuning needs context |
| 18 | Tool recommendation | "Best tool for isoform-level quantification?" | Iterative | Recommendation needed |
| 19 | Batch processing | "Process multiple samples with same workflow" | Legacy | Clear batch request |
| 20 | Data integration | "Combine results from two RNA-seq experiments" | Iterative | Integration strategy |

### Expert Scenarios (10 tests)

| Test # | Scenario | Query | Expected Mode | Reasoning |
|--------|----------|-------|---------------|-----------|
| 21 | Specific + params | "Run STAR with GRCh38, --twopassMode Basic, --quantMode GeneCounts" | Legacy | Complete specification |
| 22 | Exploration | "Design benchmarking workflow comparing 3 aligners" | Iterative | Benchmarking exploration |
| 23 | Advanced optimization | "Optimize DESeq2 dispersion estimation for low-count genes" | Iterative | Advanced tuning |
| 24 | Complex pipeline | "Create integrated workflow: QC → trim → align → dedup → call variants → annotate" | Legacy | Clear complex pipeline |
| 25 | Custom parameters | "Generate workflow using Salmon with selective alignment and gcBias correction" | Legacy | Specific custom config |
| 26 | Method comparison | "Compare standard vs stranded library prep effects on quantification" | Iterative | Comparison analysis |
| 27 | Alternative approach | "Design alternative splicing analysis with rMATS vs leafcutter" | Iterative | Method exploration |
| 28 | Technical question | "Quick explanation of TPM vs FPKM normalization" | Legacy | Informational query |
| 29 | Batch optimization | "Optimize workflow for 500 samples with cost constraints" | Iterative | Optimization design |
| 30 | Novel application | "Adapt RNA-seq workflow for spatial transcriptomics data" | Iterative | Novel adaptation |

---

## Deliverables

1. ✅ **ModeValidator utility** (`utilities/mode_validator.py`)
2. ✅ **expected_modes.json** (30 test scenario expectations)
3. ✅ **test_v6_mode_beginner.py** (10 beginner tests)
4. ✅ **test_v6_mode_intermediate.py** (10 intermediate tests)
5. ✅ **test_v6_mode_expert.py** (10 expert tests)
6. ✅ **Updated conftest.py** (new fixtures and markers)
7. ✅ **HTML test report** (results with screenshots)
8. ✅ **Summary analysis** (pass/fail breakdown by category)

---

## Execution Timeline

**Total Effort:** 16-20 hours

| Step | Task | Estimated Time |
|------|------|----------------|
| 1 | Create ModeValidator utility | 3 hours |
| 2 | Create expected_modes.json | 2 hours |
| 3 | Write 3 test case files | 8 hours |
| 4 | Update conftest.py | 1 hour |
| 5 | Execute tests & debug | 4 hours |
| 6 | Analyze & report | 2 hours |

---

## Success Criteria

### Accuracy Targets

- **Overall:** ≥85% mode detection accuracy
- **Beginner:** ≥90% accuracy
- **Intermediate:** ≥85% accuracy
- **Expert:** ≥80% accuracy

### Execution Quality

- All 30 tests execute without errors
- Clear pass/fail indication for each scenario
- HTML report with screenshots for visual validation
- Detailed failure analysis for any misclassified scenarios

### User Experience Validation

- Verify responses are appropriate for expertise level
- Check clarity of iterative mode clarifying questions
- Validate workflow quality in legacy mode
- Ensure smooth user experience across all scenarios

---

## Next Steps

Once implementation begins:

1. **Create ModeValidator utility** - Core validation logic
2. **Create expected_modes.json** - All 30 scenarios with expectations
3. **Implement 3 test files** - Complete test implementations
4. **Update conftest.py** - Add fixtures and markers
5. **Run initial test suite** - Execute and capture baseline
6. **Debug failures** - Analyze and fix any issues
7. **Generate final report** - HTML report with analysis
8. **Create summary document** - Results and recommendations

---

**Document Status:** Ready for implementation
**Last Updated:** 2025-11-07
**Implementation Start:** Pending approval
