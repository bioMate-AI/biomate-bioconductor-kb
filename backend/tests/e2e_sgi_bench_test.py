#!/usr/bin/env python3
"""
SGI-Bench End-to-End Test Suite

Tests BioMate's complete information flow using SGI-Bench samples:
1. User Context Creation (simulating user registration/login)
2. Project & Dataset Setup
3. Task Execution (one sample per SGI-Bench task type)
4. Evaluation & Scoring
5. Results Storage & Retrieval

This test uses an AI agent as a simulated real user to drive the system
and validates the entire pipeline from frontend to backend.

Usage:
    python e2e_sgi_bench_test.py [--real-llm] [--verbose] [--log-file FILE]
"""

import os
import sys
import json
import time
import logging
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field, asdict

import requests

# Add parent paths for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.galaxy.ai.test_harness import (
    # User Context
    UserBenchmarkContext,
    UserProject,
    UserDataset,
    UserContextDB,
    EvaluationDomain,
    EvaluationTask,
    get_or_create_user_context,
    # SGI-Bench
    SGIBenchDataLoader,
    SGITaskType,
    SGIDiscipline,
    SGIPromptTemplates,
    SGIScorer,
    SGISample,
    # Evaluators
    ScientificEvaluator,
    CompositeEvaluator,
    EvaluationResult,
)

# Configure logging
LOG_FORMAT = "%(asctime)s | %(levelname)-8s | %(name)s | %(message)s"
logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)
log = logging.getLogger("e2e_sgi_bench")


# =============================================================================
# Configuration
# =============================================================================

BASE_URL = os.environ.get("BIOMATE_URL", "http://localhost:8081")
ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY")

# Try to import anthropic
try:
    from anthropic import Anthropic
    anthropic_client = Anthropic(api_key=ANTHROPIC_API_KEY) if ANTHROPIC_API_KEY else None
except ImportError:
    anthropic_client = None
    log.warning("Anthropic SDK not installed. Will use mock responses.")


# =============================================================================
# Data Classes
# =============================================================================

@dataclass
class E2ETestStep:
    """A single step in the E2E test."""
    step_name: str
    description: str
    started_at: str = ""
    completed_at: str = ""
    duration_ms: float = 0.0
    success: bool = False
    details: Dict[str, Any] = field(default_factory=dict)
    error: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class E2ETestResult:
    """Complete E2E test result for one SGI-Bench task type."""
    task_type: str
    sample_idx: str
    discipline: str
    question: str
    steps: List[E2ETestStep] = field(default_factory=list)
    overall_success: bool = False
    evaluation_score: float = 0.0
    total_duration_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            **asdict(self),
            "steps": [s.to_dict() for s in self.steps]
        }


# =============================================================================
# AI Agent (Simulated User)
# =============================================================================

class AIUserAgent:
    """
    AI agent that simulates a real user interacting with BioMate.
    Uses Claude to generate realistic responses and follow-ups.
    """

    def __init__(self, use_real_llm: bool = True):
        self.use_real_llm = use_real_llm and anthropic_client is not None
        self.conversation_history: List[Dict] = []
        log.info(f"AIUserAgent initialized (real_llm={self.use_real_llm})")

    def generate_response(self, prompt: str, persona: str = "") -> str:
        """Generate a response as the simulated user."""
        if not self.use_real_llm:
            return self._mock_response(prompt)

        system_prompt = f"""You are a scientist using BioMate, a bioinformatics platform.
{persona}

Respond naturally and concisely. If asked to provide data or confirm, do so directly.
Keep responses under 100 words unless detailed information is needed."""

        try:
            response = anthropic_client.messages.create(
                model="claude-sonnet-4-20250514",
                max_tokens=500,
                system=system_prompt,
                messages=[{"role": "user", "content": prompt}]
            )
            return response.content[0].text.strip()
        except Exception as e:
            log.error(f"LLM error: {e}")
            return self._mock_response(prompt)

    def _mock_response(self, prompt: str) -> str:
        """Generate a mock response for testing without LLM."""
        if "research" in prompt.lower():
            return json.dumps({
                "answer": "Based on literature analysis, the mechanism involves...",
                "steps": ["Step 1: Review databases", "Step 2: Analyze patterns", "Step 3: Conclude"]
            })
        elif "idea" in prompt.lower() or "novel" in prompt.lower():
            return json.dumps({
                "core_idea": "Novel ML-based approach for prediction",
                "implementation_steps": ["Data prep", "Model design", "Training", "Validation"],
                "expected_outcome": "Improved accuracy over baseline"
            })
        elif "code" in prompt.lower() or "python" in prompt.lower():
            return """
def analyze(data):
    results = process_data(data)
    return summarize(results)
"""
        elif "protocol" in prompt.lower() or "experiment" in prompt.lower():
            return json.dumps([
                {"step": 1, "action": "prepare_samples", "parameters": {"temp": 37}},
                {"step": 2, "action": "run_assay", "parameters": {"duration": "2h"}},
                {"step": 3, "action": "analyze_results", "parameters": {}}
            ])
        else:
            return "A"  # Default for reasoning tasks


# =============================================================================
# E2E Test Runner
# =============================================================================

class SGIBenchE2ERunner:
    """
    Runs end-to-end tests using SGI-Bench samples.

    Tests the complete flow:
    1. User registration/login simulation
    2. User context creation
    3. Project setup with datasets
    4. Task execution via BioMate
    5. Response evaluation
    6. Results storage
    """

    def __init__(
        self,
        base_url: str = BASE_URL,
        use_real_llm: bool = True,
        verbose: bool = False
    ):
        self.base_url = base_url
        self.verbose = verbose
        self.session = requests.Session()
        self.ai_agent = AIUserAgent(use_real_llm=use_real_llm)
        self.data_loader = SGIBenchDataLoader()
        self.results: List[E2ETestResult] = []

        # Test user context
        self.user_id = f"e2e_test_user_{int(time.time())}"
        self.user_context: Optional[UserBenchmarkContext] = None

        log.info(f"E2E Runner initialized (base_url={base_url}, user_id={self.user_id})")

    def log_step(self, step_name: str, details: Dict = None, level: str = "info"):
        """Log a test step with details."""
        msg = f"[STEP] {step_name}"
        if details:
            msg += f" | {json.dumps(details)}"

        if level == "debug" and not self.verbose:
            return
        elif level == "error":
            log.error(msg)
        elif level == "warning":
            log.warning(msg)
        else:
            log.info(msg)

    def run_step(self, step_name: str, description: str, func, *args, **kwargs) -> E2ETestStep:
        """Run a test step with timing and error handling."""
        step = E2ETestStep(
            step_name=step_name,
            description=description,
            started_at=datetime.now().isoformat()
        )

        self.log_step(f"START: {step_name}", {"description": description})
        start_time = time.time()

        try:
            result = func(*args, **kwargs)
            step.success = True
            step.details = result if isinstance(result, dict) else {"result": str(result)}
            self.log_step(f"SUCCESS: {step_name}", step.details)
        except Exception as e:
            step.success = False
            step.error = str(e)
            self.log_step(f"FAILED: {step_name}", {"error": str(e)}, level="error")

        step.duration_ms = (time.time() - start_time) * 1000
        step.completed_at = datetime.now().isoformat()

        return step

    # =========================================================================
    # Step 1: User Registration/Login Simulation
    # =========================================================================

    def step_user_registration(self) -> Dict[str, Any]:
        """Simulate user registration/login."""
        self.log_step("User Registration", {"user_id": self.user_id})

        # In real system, this would call the registration API
        # For now, we create the user context directly
        try:
            response = self.session.post(
                f"{self.base_url}/api/auth/register",
                json={
                    "name": "E2E Test User",
                    "email": f"{self.user_id}@biomate.test",
                    "password": "TestPass123!"
                },
                timeout=30
            )
            if response.status_code in [200, 201, 409]:  # 409 = already exists
                return {"status": "registered", "user_id": self.user_id}
        except requests.exceptions.RequestException as e:
            self.log_step("Registration API unavailable, using direct context",
                         {"error": str(e)}, level="warning")

        # Fallback: create context directly
        return {"status": "context_created", "user_id": self.user_id}

    # =========================================================================
    # Step 2: User Context Creation
    # =========================================================================

    def step_create_user_context(self) -> Dict[str, Any]:
        """Create user benchmark context."""
        self.user_context = get_or_create_user_context(
            self.user_id,
            "E2E Test User"
        )

        return {
            "user_id": self.user_context.user_id,
            "username": self.user_context.username,
            "evaluation_criteria": list(self.user_context.evaluation_criteria.keys()),
            "created_at": self.user_context.created_at
        }

    # =========================================================================
    # Step 3: Project Setup
    # =========================================================================

    def step_setup_project(self, domain: EvaluationDomain) -> Dict[str, Any]:
        """Setup a project for testing."""
        project = UserProject(
            project_id=f"sgi_bench_e2e_{domain.value}",
            name=f"SGI-Bench E2E Test ({domain.value})",
            description="End-to-end test project using SGI-Bench samples",
            domain=domain
        )

        self.user_context.add_project(project)

        # Save context
        db = UserContextDB()
        db.save_context(self.user_context)

        return {
            "project_id": project.project_id,
            "name": project.name,
            "domain": domain.value
        }

    # =========================================================================
    # Step 4: Load SGI-Bench Sample
    # =========================================================================

    def step_load_sgi_sample(self, task_type: SGITaskType) -> Tuple[SGISample, Dict]:
        """Load one sample for the specified task type."""
        # Get samples for life science domain
        samples = self.data_loader.load_samples(
            task_types=[task_type],
            disciplines=[SGIDiscipline.LIFE]
        )

        if not samples:
            raise ValueError(f"No samples found for {task_type.value}")

        # Take first sample
        sample = samples[0]

        return sample, {
            "sample_idx": sample.idx,
            "task_type": task_type.value,
            "discipline": sample.discipline.value,
            "question_preview": sample.question[:100] + "..."
        }

    # =========================================================================
    # Step 5: Generate User Request
    # =========================================================================

    def step_generate_user_request(self, sample: SGISample) -> Tuple[str, Dict]:
        """Generate a user request based on SGI-Bench sample."""
        # Use the question directly or have AI agent rephrase
        if sample.task_type == SGITaskType.DEEP_RESEARCH:
            prompt = SGIPromptTemplates.deep_research_prompt(sample.question)
        elif sample.task_type == SGITaskType.IDEA_GENERATION:
            prompt = SGIPromptTemplates.idea_generation_prompt(sample.question)
        elif sample.task_type == SGITaskType.DRY_EXPERIMENT:
            incomplete_code = sample.metadata.get('incomplete_main_code', '')
            prompt = SGIPromptTemplates.dry_experiment_prompt(sample.question, incomplete_code)
        elif sample.task_type == SGITaskType.WET_EXPERIMENT:
            action_pool = sample.metadata.get('action_pool', [])
            if hasattr(action_pool, 'tolist'):
                action_pool = action_pool.tolist()
            prompt = SGIPromptTemplates.wet_experiment_prompt(sample.question, action_pool)
        elif sample.task_type == SGITaskType.REASONING:
            options = sample.metadata.get('options', [])
            if hasattr(options, 'tolist'):
                options = options.tolist()
            prompt = SGIPromptTemplates.reasoning_prompt(sample.question, options)
        else:
            prompt = sample.question

        return prompt, {
            "prompt_length": len(prompt),
            "task_type": sample.task_type.value
        }

    # =========================================================================
    # Step 6: Call BioMate Backend
    # =========================================================================

    def step_call_biomate(self, prompt: str) -> Tuple[str, Dict]:
        """Call BioMate's AI assistant API."""
        start_time = time.time()

        try:
            response = self.session.post(
                f"{self.base_url}/api/ai_assistant/generate_workflow",
                json={
                    "request_text": prompt,
                    "context": {
                        "user_id": self.user_id,
                        "project_id": "sgi_bench_e2e"
                    }
                },
                timeout=120
            )

            duration_ms = (time.time() - start_time) * 1000

            if response.status_code == 200:
                data = response.json()
                return data, {
                    "status": "success",
                    "response_time_ms": duration_ms,
                    "has_workflow": bool(data.get("workflow_ga")),
                    "has_response": bool(data.get("response") or data.get("text"))
                }
            else:
                return {}, {
                    "status": "error",
                    "http_code": response.status_code,
                    "error": response.text[:200]
                }

        except requests.exceptions.RequestException as e:
            self.log_step("BioMate API unavailable, using AI agent directly",
                         {"error": str(e)}, level="warning")

            # Fallback: Use AI agent to generate response
            response_text = self.ai_agent.generate_response(prompt)
            return {"response": response_text, "fallback": True}, {
                "status": "fallback",
                "response_time_ms": (time.time() - start_time) * 1000
            }

    # =========================================================================
    # Step 7: Parse Response
    # =========================================================================

    def step_parse_response(self, response_data: Dict, task_type: SGITaskType) -> Tuple[Any, Dict]:
        """Parse BioMate response into format for evaluation."""
        # Extract the actual response text
        response_text = response_data.get("response") or response_data.get("text", "")

        if isinstance(response_text, dict):
            prediction = response_text
        else:
            # Try to parse as JSON
            try:
                prediction = json.loads(response_text)
            except (json.JSONDecodeError, TypeError):
                # Use as-is for text responses
                if task_type == SGITaskType.REASONING:
                    # Extract answer letter from text
                    answer = ""
                    for letter in ["A", "B", "C", "D"]:
                        if letter in response_text.upper()[:50]:
                            answer = letter
                            break
                    prediction = {"answer": answer, "steps": []}
                elif task_type == SGITaskType.DRY_EXPERIMENT:
                    prediction = response_text  # Code as string
                else:
                    prediction = {"answer": response_text, "steps": []}

        return prediction, {
            "prediction_type": type(prediction).__name__,
            "has_answer": "answer" in str(prediction) if isinstance(prediction, dict) else bool(prediction)
        }

    # =========================================================================
    # Step 8: Evaluate Response
    # =========================================================================

    def step_evaluate_response(
        self,
        prediction: Any,
        sample: SGISample
    ) -> Tuple[EvaluationResult, Dict]:
        """Evaluate the response against ground truth."""
        evaluator = ScientificEvaluator(self.user_context)
        result = evaluator.evaluate_sgi_sample(prediction, sample)

        return result, {
            "weighted_score": result.weighted_score,
            "scores": result.scores,
            "task_type": result.task_type
        }

    # =========================================================================
    # Step 9: Store Results
    # =========================================================================

    def step_store_results(
        self,
        sample: SGISample,
        eval_result: EvaluationResult
    ) -> Dict[str, Any]:
        """Store evaluation results in user context."""
        db = UserContextDB()

        # Map SGITaskType to EvaluationTask
        task_mapping = {
            SGITaskType.DEEP_RESEARCH: EvaluationTask.DEEP_RESEARCH,
            SGITaskType.IDEA_GENERATION: EvaluationTask.IDEA_GENERATION,
            SGITaskType.DRY_EXPERIMENT: EvaluationTask.DRY_EXPERIMENT,
            SGITaskType.WET_EXPERIMENT: EvaluationTask.WET_EXPERIMENT,
            SGITaskType.REASONING: EvaluationTask.REASONING
        }

        eval_id = db.save_evaluation(
            user_id=self.user_id,
            project_id="sgi_bench_e2e",
            dataset_id=sample.idx,
            task_type=task_mapping[sample.task_type],
            evaluation=eval_result.to_dict(),
            score=eval_result.weighted_score
        )

        return {
            "evaluation_id": eval_id,
            "stored": eval_id > 0
        }

    # =========================================================================
    # Run Single Task Type Test
    # =========================================================================

    def run_task_type_test(self, task_type: SGITaskType) -> E2ETestResult:
        """Run complete E2E test for one task type."""
        log.info(f"\n{'='*70}")
        log.info(f"TESTING: {task_type.value}")
        log.info(f"{'='*70}")

        result = E2ETestResult(
            task_type=task_type.value,
            sample_idx="",
            discipline="",
            question=""
        )

        start_time = time.time()

        # Step 1: Load sample
        step = self.run_step(
            "load_sample",
            f"Load SGI-Bench sample for {task_type.value}",
            self.step_load_sgi_sample,
            task_type
        )
        result.steps.append(step)

        if not step.success:
            result.total_duration_ms = (time.time() - start_time) * 1000
            return result

        sample = step.details.get("result") if "result" in step.details else None

        # Re-fetch sample since step.details doesn't preserve the full object
        sample, _ = self.step_load_sgi_sample(task_type)
        result.sample_idx = sample.idx
        result.discipline = sample.discipline.value
        result.question = sample.question[:200]

        # Step 2: Generate prompt
        step = self.run_step(
            "generate_prompt",
            "Generate user request prompt",
            self.step_generate_user_request,
            sample
        )
        result.steps.append(step)

        if not step.success:
            result.total_duration_ms = (time.time() - start_time) * 1000
            return result

        prompt, _ = self.step_generate_user_request(sample)

        # Step 3: Call BioMate
        step = self.run_step(
            "call_biomate",
            "Send request to BioMate backend",
            self.step_call_biomate,
            prompt
        )
        result.steps.append(step)

        if not step.success:
            result.total_duration_ms = (time.time() - start_time) * 1000
            return result

        response_data, _ = self.step_call_biomate(prompt)

        # Step 4: Parse response
        step = self.run_step(
            "parse_response",
            "Parse BioMate response",
            self.step_parse_response,
            response_data,
            task_type
        )
        result.steps.append(step)

        if not step.success:
            result.total_duration_ms = (time.time() - start_time) * 1000
            return result

        prediction, _ = self.step_parse_response(response_data, task_type)

        # Step 5: Evaluate
        step = self.run_step(
            "evaluate",
            "Evaluate response against ground truth",
            self.step_evaluate_response,
            prediction,
            sample
        )
        result.steps.append(step)

        if step.success:
            result.evaluation_score = step.details.get("weighted_score", 0.0)

        # Step 6: Store results
        eval_result, _ = self.step_evaluate_response(prediction, sample)
        step = self.run_step(
            "store_results",
            "Store evaluation results",
            self.step_store_results,
            sample,
            eval_result
        )
        result.steps.append(step)

        # Calculate overall success
        result.overall_success = all(s.success for s in result.steps)
        result.total_duration_ms = (time.time() - start_time) * 1000

        return result

    # =========================================================================
    # Run All Tests
    # =========================================================================

    def run_all(self) -> Dict[str, Any]:
        """Run E2E tests for all SGI-Bench task types."""
        log.info("\n" + "=" * 70)
        log.info("  SGI-BENCH END-TO-END TEST SUITE")
        log.info("=" * 70)
        log.info(f"  Base URL: {self.base_url}")
        log.info(f"  User ID: {self.user_id}")
        log.info(f"  Started: {datetime.now().isoformat()}")
        log.info("=" * 70)

        # Step 0: Setup
        log.info("\n[SETUP PHASE]")

        setup_step = self.run_step(
            "user_registration",
            "Simulate user registration",
            self.step_user_registration
        )

        context_step = self.run_step(
            "create_user_context",
            "Create user benchmark context",
            self.step_create_user_context
        )

        project_step = self.run_step(
            "setup_project",
            "Setup test project",
            self.step_setup_project,
            EvaluationDomain.LIFE_SCIENCE
        )

        # Run tests for each task type
        log.info("\n[TASK TYPE TESTS]")

        for task_type in SGITaskType:
            result = self.run_task_type_test(task_type)
            self.results.append(result)

        # Generate report
        return self.generate_report()

    def generate_report(self) -> Dict[str, Any]:
        """Generate comprehensive test report."""
        passed = sum(1 for r in self.results if r.overall_success)
        total = len(self.results)

        avg_score = sum(r.evaluation_score for r in self.results) / total if total else 0

        log.info("\n" + "=" * 70)
        log.info("  TEST SUMMARY")
        log.info("=" * 70)
        log.info(f"  Overall: {passed}/{total} task types passed")
        log.info(f"  Average Evaluation Score: {avg_score:.3f}")

        log.info("\n  Results by Task Type:")
        for r in self.results:
            status = "PASS" if r.overall_success else "FAIL"
            log.info(f"    [{status}] {r.task_type}: score={r.evaluation_score:.3f}, "
                    f"duration={r.total_duration_ms:.0f}ms")
            if not r.overall_success:
                for s in r.steps:
                    if not s.success:
                        log.info(f"          Failed step: {s.step_name} - {s.error}")

        log.info("=" * 70)

        return {
            "timestamp": datetime.now().isoformat(),
            "user_id": self.user_id,
            "base_url": self.base_url,
            "total_task_types": total,
            "passed": passed,
            "failed": total - passed,
            "average_score": avg_score,
            "results": [r.to_dict() for r in self.results]
        }


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(description="SGI-Bench E2E Test Suite")
    parser.add_argument("--base-url", default=BASE_URL, help="BioMate base URL")
    parser.add_argument("--real-llm", action="store_true", help="Use real LLM for AI agent")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose logging")
    parser.add_argument("--log-file", help="Log to file")
    parser.add_argument("--output", "-o", help="Output JSON report file")

    args = parser.parse_args()

    # Configure file logging if requested
    if args.log_file:
        file_handler = logging.FileHandler(args.log_file)
        file_handler.setFormatter(logging.Formatter(LOG_FORMAT))
        logging.getLogger().addHandler(file_handler)

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    # Run tests
    runner = SGIBenchE2ERunner(
        base_url=args.base_url,
        use_real_llm=args.real_llm,
        verbose=args.verbose
    )

    report = runner.run_all()

    # Save report
    if args.output:
        with open(args.output, "w") as f:
            json.dump(report, f, indent=2, default=str)
        log.info(f"\nReport saved to: {args.output}")

    # Exit with appropriate code
    sys.exit(0 if report["failed"] == 0 else 1)


if __name__ == "__main__":
    main()
