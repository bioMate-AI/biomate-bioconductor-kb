#!/usr/bin/env python3
"""
BioMate Comprehensive LLM Agent E2E Test Suite

Based on documented use cases from:
- WORKFLOW_SCENARIOS_20251030.md (Real-world lab scenarios)
- NON_CLINICAL_USE_CASES_PROPOSAL_20251030.md (Market priority use cases)
- Frontend Integration Plan (Citation, Pilot Run features)

Test Categories:
1. User Experience (UX) Tests - Natural interaction, response quality
2. Function Tests - Feature correctness, API responses
3. Efficiency Tests - Response times, performance metrics
"""

import os
import sys
import time
import json
import statistics
from datetime import datetime
from typing import Dict, Any, List, Optional, Tuple
from dataclasses import dataclass, field, asdict
from enum import Enum

import requests
from anthropic import Anthropic

BASE_URL = os.environ.get("BIOMATE_URL", "http://localhost:8081")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")

# Initialize Claude
anthropic = Anthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None


# =============================================================================
# Test Categories
# =============================================================================

class TestCategory(Enum):
    UX = "user_experience"
    FUNCTION = "function"
    EFFICIENCY = "efficiency"


class TestPriority(Enum):
    CRITICAL = 1
    HIGH = 2
    MEDIUM = 3
    LOW = 4


@dataclass
class TestResult:
    test_id: str
    name: str
    category: TestCategory
    priority: TestPriority
    passed: bool
    duration_ms: float
    details: str = ""
    error: str = ""
    metrics: Dict[str, Any] = field(default_factory=dict)


# =============================================================================
# Priority Test Scenarios (From Documentation)
# =============================================================================

PRIORITY_SCENARIOS = [
    # =========================================================================
    # TIER 1: Core Bioinformatics (From WORKFLOW_SCENARIOS)
    # =========================================================================
    {
        "id": "CORE-01",
        "name": "RNA-seq Differential Expression Analysis",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.CRITICAL,
        "persona": """You are Dr. Sarah Chen, a computational biologist at a cancer research center.
You have RNA-seq data from a breast cancer study comparing tumor vs normal tissue.
You need to find differentially expressed genes and pathway enrichment.""",
        "initial_query": """I have 6 RNA-seq samples from breast cancer patients - 3 tumor samples and 3 matched normal tissue samples.
Can you help me analyze differential gene expression and find enriched pathways?
I need publication-quality results with proper citations.""",
        "expected_tools": ["FastQC", "STAR", "DESeq2", "salmon"],
        "expected_features": ["workflow_generated", "citations_available"],
        "validation": {
            "workflow_has_qc_step": True,
            "workflow_has_alignment": True,
            "workflow_has_de_analysis": True,
        }
    },
    {
        "id": "CORE-02",
        "name": "Variant Calling Pipeline",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.CRITICAL,
        "persona": """You are Dr. James Liu, a clinical geneticist.
You have whole exome sequencing data from a family trio (proband + parents).
You need to identify potentially pathogenic variants.""",
        "initial_query": """I have WES data from a family trio - a child with a rare developmental disorder and both parents.
Can you create a variant calling pipeline to identify de novo and inherited pathogenic variants?
I need the variants annotated with clinical significance.""",
        "expected_tools": ["BWA", "GATK", "bcftools", "VEP"],
        "expected_features": ["workflow_generated"],
        "validation": {
            "workflow_has_alignment": True,
            "workflow_has_variant_calling": True,
        }
    },
    {
        "id": "CORE-03",
        "name": "Single-Cell RNA-seq Cell Type Annotation",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.CRITICAL,
        "persona": """You are Dr. Emily Watson, a single-cell genomics researcher.
You have 10X Genomics scRNA-seq data from human PBMC samples.
You want to identify and annotate immune cell populations.""",
        "initial_query": """I have 10X Genomics single-cell RNA-seq data from human PBMCs.
I need to cluster the cells and identify the immune cell types present.
Can you help with cell type annotation using marker genes and reference datasets?""",
        "expected_tools": ["STARsolo", "Scanpy", "CellTypist"],
        "expected_features": ["workflow_generated"],
        "validation": {
            "workflow_has_clustering": True,
        }
    },

    # =========================================================================
    # TIER 2: Drug Discovery (From NON_CLINICAL_USE_CASES)
    # =========================================================================
    {
        "id": "DRUG-01",
        "name": "Drug-Target Docking Analysis",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.HIGH,
        "persona": """You are Dr. Michael Torres, a medicinal chemist at a biotech startup.
You're working on developing inhibitors for a cancer target (EGFR).
You have 5 candidate compounds to evaluate.""",
        "initial_query": """I want to dock 5 small molecule compounds against the EGFR kinase domain (PDB: 1M17).
Here are the SMILES:
1. CC(=O)Nc1ccc(O)cc1 (Acetaminophen-like)
2. COc1ccc(C=O)cc1OC (Vanillin-like)
3. c1ccc2[nH]ccc2c1 (Indole)
4. CC(C)Cc1ccc(C(C)C(=O)O)cc1 (Ibuprofen-like)
5. c1ccc(Nc2ncccn2)cc1 (Pyrimidine scaffold)

Can you run molecular docking and predict binding affinities?""",
        "expected_tools": ["AutoDock Vina", "DiffDock"],
        "expected_features": ["workflow_generated"],
        "validation": {
            "workflow_has_docking": True,
        }
    },
    {
        "id": "DRUG-02",
        "name": "ADMET Property Prediction",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.HIGH,
        "persona": """You are Dr. Anna Schmidt, a pharmacologist evaluating drug candidates.
You need to predict ADMET properties for lead optimization.""",
        "initial_query": """I need to predict ADMET properties (absorption, distribution, metabolism, excretion, toxicity)
for this drug candidate: CC(C)Cc1ccc(C(C)C(=O)O)cc1

What are the predicted pharmacokinetic properties and any toxicity concerns?""",
        "expected_tools": ["ADMET prediction"],
        "expected_features": ["workflow_generated"],
        "validation": {}
    },

    # =========================================================================
    # TIER 3: Microbiology & Metagenomics
    # =========================================================================
    {
        "id": "MICRO-01",
        "name": "Bacterial Genome Assembly (Long-Read)",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.HIGH,
        "persona": """You are Dr. Robert Kim, a microbiologist studying antibiotic resistance.
You have ONT long-read sequencing data from a multi-drug resistant E. coli isolate.
You need a complete genome assembly and resistance gene annotation.""",
        "initial_query": """I have Oxford Nanopore long-read sequencing data from a clinical E. coli isolate
showing multi-drug resistance phenotype. Can you:
1. Assemble the genome using Flye
2. Polish the assembly
3. Annotate genes with Prokka
4. Identify antibiotic resistance genes

I need to find the plasmids carrying resistance genes.""",
        "expected_tools": ["Flye", "Medaka", "Prokka"],
        "expected_features": ["workflow_generated"],
        "validation": {
            "workflow_has_assembly": True,
            "workflow_has_annotation": True,
        }
    },
    {
        "id": "MICRO-02",
        "name": "Metagenomics Species Classification",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.MEDIUM,
        "persona": """You are Dr. Lisa Park, an environmental microbiologist.
You have shotgun metagenomics data from soil samples.
You want to identify the microbial community composition.""",
        "initial_query": """I have shotgun metagenomics sequencing from agricultural soil samples.
I need to:
1. Classify the species present using Kraken2
2. Generate abundance profiles with Bracken
3. Create a community composition visualization

What microbes are dominant in these samples?""",
        "expected_tools": ["Kraken2", "MetaPhlAn", "Bracken"],
        "expected_features": ["workflow_generated"],
        "validation": {}
    },

    # =========================================================================
    # TIER 4: Database & Quick Queries (UX Tests)
    # =========================================================================
    {
        "id": "UX-01",
        "name": "Quick Gene Information Lookup",
        "category": TestCategory.UX,
        "priority": TestPriority.HIGH,
        "persona": """You are a graduate student doing background research.
You need quick information about a gene.""",
        "initial_query": "What is the function of the TP53 gene and what diseases is it associated with?",
        "expected_tools": [],  # Should be quick lookup, not workflow
        "expected_features": ["quick_response"],
        "validation": {
            "response_contains_gene_function": True,
            "response_contains_disease_association": True,
            "no_workflow_generated": True,  # Simple query shouldn't need workflow
        },
        "max_response_time_ms": 5000
    },
    {
        "id": "UX-02",
        "name": "Protein Structure Query",
        "category": TestCategory.UX,
        "priority": TestPriority.MEDIUM,
        "persona": """You are a structural biologist looking for protein structure information.""",
        "initial_query": "Show me the AlphaFold predicted structure for human insulin receptor (INSR).",
        "expected_tools": [],
        "expected_features": ["quick_response"],
        "validation": {
            "response_contains_structure_info": True,
        },
        "max_response_time_ms": 5000
    },
    {
        "id": "UX-03",
        "name": "Error Handling - Invalid Input",
        "category": TestCategory.UX,
        "priority": TestPriority.HIGH,
        "persona": """You are a new user who made a mistake in the input.""",
        "initial_query": "Analyze this sequence: ATGCXYZABC123",
        "expected_tools": [],
        "expected_features": ["error_guidance"],
        "validation": {
            "provides_clear_error": True,
            "suggests_correction": True,
        }
    },

    # =========================================================================
    # TIER 5: Citation & Pilot Run Features
    # =========================================================================
    {
        "id": "CITE-01",
        "name": "Citation Export Workflow",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.HIGH,
        "persona": """You are Dr. Chen preparing a methods section for publication.""",
        "initial_query": """Create an RNA-seq analysis workflow and then export all the tool citations
as a BibTeX file for my paper. I also need a publication-ready methods section.""",
        "expected_tools": ["FastQC", "STAR", "DESeq2"],
        "expected_features": ["workflow_generated", "citations_available", "bibtex_export"],
        "validation": {
            "workflow_generated": True,
            "citations_returned": True,
        }
    },
    {
        "id": "PILOT-01",
        "name": "Large Dataset with Pilot Run",
        "category": TestCategory.FUNCTION,
        "priority": TestPriority.HIGH,
        "persona": """You are a core facility manager with a large dataset.""",
        "initial_query": """I have 200 RNA-seq samples to analyze. This is a large batch and I want to
optimize parameters before running the full dataset. Can you suggest running a pilot first?""",
        "expected_tools": [],
        "expected_features": ["pilot_run_suggested"],
        "validation": {
            "suggests_pilot_run": True,
        }
    },

    # =========================================================================
    # TIER 6: Efficiency Tests
    # =========================================================================
    {
        "id": "EFF-01",
        "name": "Response Latency - Simple Query",
        "category": TestCategory.EFFICIENCY,
        "priority": TestPriority.HIGH,
        "persona": "Quick query user",
        "initial_query": "What is BRCA1?",
        "expected_tools": [],
        "expected_features": [],
        "validation": {},
        "max_response_time_ms": 3000
    },
    {
        "id": "EFF-02",
        "name": "Response Latency - Workflow Generation",
        "category": TestCategory.EFFICIENCY,
        "priority": TestPriority.HIGH,
        "persona": "Researcher requesting workflow",
        "initial_query": "Create a ChIP-seq peak calling workflow for H3K27ac data.",
        "expected_tools": ["BWA", "MACS2"],
        "expected_features": ["workflow_generated"],
        "validation": {},
        "max_response_time_ms": 15000
    },
]


# =============================================================================
# AI Agent Functions
# =============================================================================

def ai_evaluate_response(
    query: str,
    response: Dict[str, Any],
    expected_features: List[str],
    validation: Dict[str, Any]
) -> Tuple[bool, str, Dict[str, Any]]:
    """Use Claude to evaluate if the response meets expectations."""

    if not anthropic:
        # Fallback to simple validation if no API key
        return simple_validate(response, expected_features, validation)

    prompt = f"""Evaluate this BioMate AI response for a bioinformatics query.

QUERY: {query}

RESPONSE: {json.dumps(response, indent=2)[:3000]}

EXPECTED FEATURES: {expected_features}
VALIDATION CRITERIA: {json.dumps(validation)}

Evaluate:
1. Does the response address the query appropriately?
2. Are the expected features present (workflow_generated, citations_available, etc.)?
3. Is the response quality acceptable for a research platform?

Respond in JSON:
{{"passed": true/false, "reason": "brief explanation", "feature_scores": {{"feature": true/false}}}}
"""

    try:
        result = anthropic.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=500,
            messages=[{"role": "user", "content": prompt}]
        )

        text = result.content[0].text
        start = text.find('{')
        end = text.rfind('}') + 1
        if start >= 0 and end > start:
            eval_result = json.loads(text[start:end])
            return (
                eval_result.get("passed", False),
                eval_result.get("reason", ""),
                eval_result.get("feature_scores", {})
            )
    except Exception as e:
        print(f"    AI evaluation error: {e}")

    return simple_validate(response, expected_features, validation)


def simple_validate(
    response: Dict[str, Any],
    expected_features: List[str],
    validation: Dict[str, Any]
) -> Tuple[bool, str, Dict[str, Any]]:
    """Simple validation without LLM."""
    feature_scores = {}

    # Check expected features
    if "workflow_generated" in expected_features:
        has_workflow = bool(response.get("workflow_ga") or response.get("success"))
        feature_scores["workflow_generated"] = has_workflow

    if "citations_available" in expected_features:
        has_citations = bool(response.get("citations")) or bool(response.get("methods_section"))
        feature_scores["citations_available"] = has_citations

    if "quick_response" in expected_features:
        feature_scores["quick_response"] = True  # Will be validated by timing

    if "pilot_run_suggested" in expected_features:
        suggests_pilot = response.get("pilot_run_suggested", False)
        feature_scores["pilot_run_suggested"] = suggests_pilot

    # Check validation criteria
    for key, expected in validation.items():
        if key == "no_workflow_generated":
            feature_scores[key] = not bool(response.get("workflow_ga"))
        elif key == "workflow_generated":
            feature_scores[key] = bool(response.get("workflow_ga"))

    all_passed = all(feature_scores.values()) if feature_scores else True
    reason = "All features present" if all_passed else f"Missing: {[k for k, v in feature_scores.items() if not v]}"

    return all_passed, reason, feature_scores


def ai_generate_followup(
    conversation: List[Dict],
    persona: str,
    current_response: str
) -> Optional[str]:
    """Generate a follow-up question as the user."""
    if not anthropic:
        return None

    prompt = f"""{persona}

The AI assistant just responded: {current_response[:500]}...

Generate a brief follow-up question (1-2 sentences) to:
- Request citations or methods section
- Ask about pilot run options
- Clarify parameters
- Or confirm you're satisfied

Respond with just the follow-up question or "SATISFIED" if the response is complete."""

    try:
        result = anthropic.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=150,
            messages=[{"role": "user", "content": prompt}]
        )
        return result.content[0].text.strip()
    except:
        return None


# =============================================================================
# Test Execution
# =============================================================================

class ComprehensiveTestRunner:
    """Run comprehensive E2E tests."""

    def __init__(self, base_url: str = BASE_URL):
        self.base_url = base_url
        self.session = requests.Session()
        self.results: List[TestResult] = []
        self.timing_data: Dict[str, List[float]] = {}

    def run_scenario(self, scenario: Dict) -> TestResult:
        """Run a single test scenario."""
        start_time = time.time()

        test_id = scenario["id"]
        name = scenario["name"]
        category = scenario["category"]
        priority = scenario["priority"]

        print(f"\n  [{test_id}] {name}")
        print(f"      Category: {category.value}, Priority: {priority.name}")

        try:
            # Make API request
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/generate_workflow",
                json={"request_text": scenario["initial_query"], "context": {}},
                timeout=60
            )

            duration_ms = (time.time() - start_time) * 1000

            if response.status_code == 200:
                data = response.json()

                # Evaluate response
                passed, reason, metrics = ai_evaluate_response(
                    scenario["initial_query"],
                    data,
                    scenario.get("expected_features", []),
                    scenario.get("validation", {})
                )

                # Check timing for efficiency tests
                max_time = scenario.get("max_response_time_ms")
                if max_time and duration_ms > max_time:
                    passed = False
                    reason = f"Too slow: {duration_ms:.0f}ms > {max_time}ms"

                result = TestResult(
                    test_id=test_id,
                    name=name,
                    category=category,
                    priority=priority,
                    passed=passed,
                    duration_ms=duration_ms,
                    details=reason,
                    metrics=metrics
                )

            else:
                result = TestResult(
                    test_id=test_id,
                    name=name,
                    category=category,
                    priority=priority,
                    passed=False,
                    duration_ms=duration_ms,
                    error=f"HTTP {response.status_code}: {response.text[:200]}"
                )

        except Exception as e:
            duration_ms = (time.time() - start_time) * 1000
            result = TestResult(
                test_id=test_id,
                name=name,
                category=category,
                priority=priority,
                passed=False,
                duration_ms=duration_ms,
                error=str(e)
            )

        # Log result
        status = "PASS" if result.passed else "FAIL"
        print(f"      [{status}] {result.duration_ms:.0f}ms - {result.details or result.error}")

        # Track timing
        if category.value not in self.timing_data:
            self.timing_data[category.value] = []
        self.timing_data[category.value].append(duration_ms)

        return result

    def run_citation_api_tests(self) -> List[TestResult]:
        """Run citation-specific API tests."""
        results = []

        print("\n  [CITE-API] Citation Export API Test")
        start_time = time.time()

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/citations/export",
                json={
                    "workflow_ga": {
                        "name": "Test Workflow",
                        "steps": {
                            "0": {"id": 0, "type": "tool", "name": "FastQC", "tool_id": "fastqc"},
                            "1": {"id": 1, "type": "tool", "name": "STAR", "tool_id": "star"}
                        }
                    },
                    "include_all": True
                },
                timeout=30
            )

            duration_ms = (time.time() - start_time) * 1000

            if response.status_code == 200:
                data = response.json()
                passed = data.get("success", False)
                results.append(TestResult(
                    test_id="CITE-API-01",
                    name="Citation Export API",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.HIGH,
                    passed=passed,
                    duration_ms=duration_ms,
                    details=f"Exported {data.get('tools_with_citations', 0)} citations",
                    metrics={"tools_with_citations": data.get("tools_with_citations", 0)}
                ))
            else:
                results.append(TestResult(
                    test_id="CITE-API-01",
                    name="Citation Export API",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.HIGH,
                    passed=False,
                    duration_ms=duration_ms,
                    error=f"HTTP {response.status_code}"
                ))
        except Exception as e:
            results.append(TestResult(
                test_id="CITE-API-01",
                name="Citation Export API",
                category=TestCategory.FUNCTION,
                priority=TestPriority.HIGH,
                passed=False,
                duration_ms=0,
                error=str(e)
            ))

        print(f"      [{'PASS' if results[-1].passed else 'FAIL'}] {results[-1].details or results[-1].error}")

        # Methods section test
        print("\n  [CITE-API] Methods Section Generation Test")
        start_time = time.time()

        for style in ["short", "apa", "numbered"]:
            try:
                response = self.session.post(
                    f"{self.base_url}/api/ai_assistant/citations/methods",
                    params={"style": style},
                    json={"workflow_ga": {"name": "Test", "steps": {}}, "include_all": True},
                    timeout=30
                )

                duration_ms = (time.time() - start_time) * 1000
                passed = response.status_code == 200 and response.json().get("success", False)

                results.append(TestResult(
                    test_id=f"CITE-API-02-{style}",
                    name=f"Methods Section ({style})",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.MEDIUM,
                    passed=passed,
                    duration_ms=duration_ms,
                    details=f"Generated {len(response.json().get('methods_text', ''))} chars" if passed else "",
                    error="" if passed else f"HTTP {response.status_code}"
                ))
                print(f"      [{style}] {'PASS' if passed else 'FAIL'}")
            except Exception as e:
                results.append(TestResult(
                    test_id=f"CITE-API-02-{style}",
                    name=f"Methods Section ({style})",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.MEDIUM,
                    passed=False,
                    duration_ms=0,
                    error=str(e)
                ))

        return results

    def run_pilot_api_tests(self) -> List[TestResult]:
        """Run pilot run API tests."""
        results = []

        print("\n  [PILOT-API] Pilot Run Lifecycle Test")

        # Start pilot
        start_time = time.time()
        pilot_id = None

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/pilot/start",
                json={
                    "workflow_id": "test-workflow",
                    "total_samples": 100,
                    "config": {"pilot_fraction": 0.1}
                },
                timeout=30
            )

            duration_ms = (time.time() - start_time) * 1000

            if response.status_code == 200:
                data = response.json()
                pilot_id = data.get("pilot_id")
                passed = bool(pilot_id)
                results.append(TestResult(
                    test_id="PILOT-API-01",
                    name="Pilot Run Start",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.HIGH,
                    passed=passed,
                    duration_ms=duration_ms,
                    details=f"pilot_id: {pilot_id}" if passed else "",
                    metrics={"pilot_id": pilot_id, "pilot_size": data.get("pilot_size")}
                ))
            else:
                results.append(TestResult(
                    test_id="PILOT-API-01",
                    name="Pilot Run Start",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.HIGH,
                    passed=False,
                    duration_ms=duration_ms,
                    error=f"HTTP {response.status_code}"
                ))
        except Exception as e:
            results.append(TestResult(
                test_id="PILOT-API-01",
                name="Pilot Run Start",
                category=TestCategory.FUNCTION,
                priority=TestPriority.HIGH,
                passed=False,
                duration_ms=0,
                error=str(e)
            ))

        print(f"      [Start] {'PASS' if results[-1].passed else 'FAIL'}")

        # Check status if we got a pilot_id
        if pilot_id:
            try:
                response = self.session.get(
                    f"{self.base_url}/api/ai_assistant/pilot/{pilot_id}/status",
                    timeout=30
                )
                passed = response.status_code == 200
                results.append(TestResult(
                    test_id="PILOT-API-02",
                    name="Pilot Run Status",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.MEDIUM,
                    passed=passed,
                    duration_ms=0,
                    details=f"status: {response.json().get('status')}" if passed else "",
                    error="" if passed else f"HTTP {response.status_code}"
                ))
                print(f"      [Status] {'PASS' if passed else 'FAIL'}")
            except Exception as e:
                results.append(TestResult(
                    test_id="PILOT-API-02",
                    name="Pilot Run Status",
                    category=TestCategory.FUNCTION,
                    priority=TestPriority.MEDIUM,
                    passed=False,
                    duration_ms=0,
                    error=str(e)
                ))

        return results

    def run_all(self, scenarios: Optional[List[Dict]] = None) -> Dict[str, Any]:
        """Run all tests and generate report."""
        if scenarios is None:
            scenarios = PRIORITY_SCENARIOS

        print("\n" + "=" * 70)
        print("  BIOMATE COMPREHENSIVE E2E TEST SUITE")
        print("=" * 70)
        print(f"  Base URL: {self.base_url}")
        print(f"  Scenarios: {len(scenarios)}")
        print(f"  Started: {datetime.now().isoformat()}")

        # Run main scenarios
        print("\n" + "-" * 70)
        print("  SCENARIO TESTS")
        print("-" * 70)

        for scenario in scenarios:
            result = self.run_scenario(scenario)
            self.results.append(result)

        # Run API-specific tests
        print("\n" + "-" * 70)
        print("  API TESTS")
        print("-" * 70)

        self.results.extend(self.run_citation_api_tests())
        self.results.extend(self.run_pilot_api_tests())

        # Generate summary
        return self.generate_report()

    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report."""

        # Calculate statistics by category
        by_category = {}
        for result in self.results:
            cat = result.category.value
            if cat not in by_category:
                by_category[cat] = {"passed": 0, "failed": 0, "total": 0, "avg_time_ms": 0}
            by_category[cat]["total"] += 1
            if result.passed:
                by_category[cat]["passed"] += 1
            else:
                by_category[cat]["failed"] += 1

        # Calculate timing stats
        for cat, times in self.timing_data.items():
            if cat in by_category and times:
                by_category[cat]["avg_time_ms"] = statistics.mean(times)

        # Calculate by priority
        by_priority = {}
        for result in self.results:
            pri = result.priority.name
            if pri not in by_priority:
                by_priority[pri] = {"passed": 0, "failed": 0}
            if result.passed:
                by_priority[pri]["passed"] += 1
            else:
                by_priority[pri]["failed"] += 1

        total_passed = sum(1 for r in self.results if r.passed)
        total = len(self.results)

        # Print summary
        print("\n" + "=" * 70)
        print("  TEST SUMMARY")
        print("=" * 70)

        print(f"\n  Overall: {total_passed}/{total} passed ({100*total_passed/total:.1f}%)")

        print("\n  By Category:")
        for cat, stats in by_category.items():
            pct = 100 * stats["passed"] / stats["total"] if stats["total"] else 0
            print(f"    {cat}: {stats['passed']}/{stats['total']} ({pct:.0f}%) - avg {stats['avg_time_ms']:.0f}ms")

        print("\n  By Priority:")
        for pri, stats in by_priority.items():
            total_pri = stats["passed"] + stats["failed"]
            pct = 100 * stats["passed"] / total_pri if total_pri else 0
            print(f"    {pri}: {stats['passed']}/{total_pri} ({pct:.0f}%)")

        # List failures
        failures = [r for r in self.results if not r.passed]
        if failures:
            print("\n  Failed Tests:")
            for r in failures:
                print(f"    [{r.test_id}] {r.name}: {r.error or r.details}")

        print("\n" + "=" * 70)

        return {
            "timestamp": datetime.now().isoformat(),
            "base_url": self.base_url,
            "total": total,
            "passed": total_passed,
            "failed": total - total_passed,
            "pass_rate": total_passed / total if total else 0,
            "by_category": by_category,
            "by_priority": by_priority,
            "results": [asdict(r) for r in self.results],
            "timing_data": self.timing_data
        }


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="BioMate Comprehensive E2E Tests")
    parser.add_argument("--base-url", default=BASE_URL, help="Base URL")
    parser.add_argument("--output", help="Output JSON file")
    parser.add_argument("--category", choices=["ux", "function", "efficiency"], help="Filter by category")
    parser.add_argument("--priority", choices=["CRITICAL", "HIGH", "MEDIUM", "LOW"], help="Filter by priority")

    args = parser.parse_args()

    # Filter scenarios if requested
    scenarios = PRIORITY_SCENARIOS

    if args.category:
        cat_map = {"ux": TestCategory.UX, "function": TestCategory.FUNCTION, "efficiency": TestCategory.EFFICIENCY}
        scenarios = [s for s in scenarios if s["category"] == cat_map[args.category]]

    if args.priority:
        pri_map = {"CRITICAL": TestPriority.CRITICAL, "HIGH": TestPriority.HIGH,
                   "MEDIUM": TestPriority.MEDIUM, "LOW": TestPriority.LOW}
        scenarios = [s for s in scenarios if s["priority"] == pri_map[args.priority]]

    runner = ComprehensiveTestRunner(base_url=args.base_url)
    report = runner.run_all(scenarios)

    if args.output:
        with open(args.output, "w") as f:
            json.dump(report, f, indent=2, default=str)
        print(f"\nReport saved to: {args.output}")

    sys.exit(0 if report["failed"] == 0 else 1)


if __name__ == "__main__":
    main()
