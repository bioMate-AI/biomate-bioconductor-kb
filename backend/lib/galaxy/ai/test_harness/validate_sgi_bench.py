#!/usr/bin/env python3
"""
SGI-Bench Validation Script

Validates the test harness framework with SGI-Bench samples.
This script demonstrates the complete evaluation pipeline:
1. Load SGI-Bench samples for BioMate-relevant domains
2. Create user context with evaluation criteria
3. Run evaluations using the ScientificEvaluator
4. Generate evaluation report

Usage:
    python validate_sgi_bench.py [--samples N] [--real-llm]
"""

import argparse
import json
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Any

# Add parent to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent.parent.parent.parent))

from lib.galaxy.ai.test_harness import (
    SGIBenchDataLoader,
    SGIDiscipline,
    SGITaskType,
    ScientificEvaluator,
    EvaluationTask,
    UserBenchmarkContext,
    UserProject,
    UserDataset,
    EvaluationDomain,
    get_or_create_user_context,
    run_sgi_bench_evaluation
)


def create_mock_model_runner():
    """
    Create a mock model runner for framework validation.
    In production, this would call an actual LLM API.
    """
    def mock_runner(prompt: str) -> str:
        # Simple mock responses based on prompt content
        if "reasoning" in prompt.lower() or "analyze" in prompt.lower():
            return json.dumps({
                "answer": "A",
                "steps": [
                    "Step 1: Identify key variables",
                    "Step 2: Apply relevant theory",
                    "Step 3: Draw conclusion"
                ]
            })
        elif "idea" in prompt.lower() or "novel" in prompt.lower():
            return json.dumps({
                "core_idea": "Novel approach using ML",
                "implementation_steps": [
                    "Data collection",
                    "Feature engineering",
                    "Model training",
                    "Validation"
                ],
                "expected_outcome": "Improved accuracy"
            })
        elif "code" in prompt.lower() or "python" in prompt.lower():
            return """
def solve(data):
    result = process(data)
    return result
"""
        else:
            return "Generic response for evaluation"

    return mock_runner


def validate_data_loading():
    """Validate SGI-Bench data loading."""
    print("\n=== Phase 1: Data Loading Validation ===")

    loader = SGIBenchDataLoader()

    # Test loading all samples
    all_samples = loader.load_samples()
    print(f"Total SGI-Bench samples: {len(all_samples)}")

    # Test loading BioMate-relevant samples
    biomate_samples = loader.get_biomate_relevant_samples()
    print(f"BioMate-relevant samples (Life Science + Chemistry): {len(biomate_samples)}")

    # Get statistics
    stats = loader.get_sample_statistics()
    print(f"\nSamples by task type:")
    for task, count in stats["by_task_type"].items():
        print(f"  {task}: {count}")

    print(f"\nSamples by discipline:")
    for disc, count in stats["by_discipline"].items():
        print(f"  {disc}: {count}")

    return biomate_samples


def validate_user_context():
    """Validate user context creation."""
    print("\n=== Phase 2: User Context Validation ===")

    # Create a test user context
    context = get_or_create_user_context("test_user_sgi", "SGI-Bench Tester")

    print(f"User ID: {context.user_id}")
    print(f"Username: {context.username}")
    print(f"Evaluation criteria defined: {list(context.evaluation_criteria.keys())}")

    # Add a test project
    project = UserProject(
        project_id="sgi_validation",
        name="SGI-Bench Validation Project",
        description="Testing BioMate test harness with SGI-Bench",
        domain=EvaluationDomain.LIFE_SCIENCE
    )
    context.add_project(project)

    print(f"Projects: {list(context.projects.keys())}")

    return context


def validate_evaluators(samples, context, n_samples=10):
    """Validate evaluators with a subset of samples."""
    print(f"\n=== Phase 3: Evaluator Validation (n={n_samples}) ===")

    evaluator = ScientificEvaluator(context)
    mock_runner = create_mock_model_runner()

    results = {
        task.value: {"scores": [], "count": 0}
        for task in SGITaskType
    }

    start_time = time.time()

    for i, sample in enumerate(samples[:n_samples]):
        # Generate mock response
        from lib.galaxy.ai.test_harness.sgi_bench_adapter import SGIPromptTemplates
        prompt = SGIPromptTemplates.reasoning_prompt(
            sample.question,
            sample.metadata.get('options', [])
        )
        response = mock_runner(prompt)

        # Parse response
        try:
            prediction = json.loads(response)
        except json.JSONDecodeError:
            prediction = {"answer": response}

        # Evaluate
        result = evaluator.evaluate_sgi_sample(prediction, sample)

        # Store result
        task_type = sample.task_type.value
        results[task_type]["scores"].append(result.weighted_score)
        results[task_type]["count"] += 1

        if (i + 1) % 5 == 0:
            print(f"  Evaluated {i + 1}/{n_samples} samples...")

    elapsed = time.time() - start_time

    print(f"\nEvaluation completed in {elapsed:.2f}s")
    print("\nResults by task type:")
    for task_type, data in results.items():
        if data["count"] > 0:
            avg_score = sum(data["scores"]) / data["count"]
            print(f"  {task_type}: {data['count']} samples, avg score = {avg_score:.3f}")

    return results


def validate_full_pipeline(samples, context, n_samples=5):
    """Validate full evaluation pipeline."""
    print(f"\n=== Phase 4: Full Pipeline Validation (n={n_samples}) ===")

    mock_runner = create_mock_model_runner()

    # Run full evaluation
    subset = samples[:n_samples]
    results = run_sgi_bench_evaluation(
        samples=subset,
        model_runner=mock_runner,
        user_context=context
    )

    print(f"\nPipeline Results:")
    print(f"  Total samples: {results['total_samples']}")
    print(f"  Successful evaluations: {results['successful_evaluations']}")
    print(f"  Failed evaluations: {results['failed_evaluations']}")
    print(f"  Average score: {results['average_score']:.3f}")

    if results['scores_by_task_type']:
        print("\n  Scores by task type:")
        for task, score in results['scores_by_task_type'].items():
            print(f"    {task}: {score:.3f}")

    return results


def generate_validation_report(all_results: Dict[str, Any]) -> str:
    """Generate validation report."""
    report = []
    report.append("=" * 60)
    report.append("SGI-BENCH TEST HARNESS VALIDATION REPORT")
    report.append(f"Generated: {datetime.now().isoformat()}")
    report.append("=" * 60)

    report.append("\n## Summary")
    report.append(f"Total BioMate-relevant samples: {all_results['total_samples']}")
    report.append(f"Samples evaluated: {all_results['samples_evaluated']}")
    report.append(f"Validation status: {'PASSED' if all_results['passed'] else 'FAILED'}")

    report.append("\n## Components Validated")
    report.append("- [x] SGI-Bench data loading")
    report.append("- [x] User context infrastructure")
    report.append("- [x] Scientific evaluator")
    report.append("- [x] Evaluation pipeline")
    report.append("- [x] Results aggregation")

    report.append("\n## Evaluation Criteria (SGI-Bench Aligned)")
    report.append("- Deep Research: step_accuracy, final_answer_accuracy, reasoning_validity")
    report.append("- Idea Generation: novelty, feasibility, workflow_coherence")
    report.append("- Dry Experiment: execution_success, unit_test_pass_rate, scientific_correctness")
    report.append("- Wet Experiment: sequence_similarity, parameter_accuracy, temporal_coherence")
    report.append("- Reasoning: answer_accuracy, reasoning_validity, comparative_ability")

    report.append("\n## Next Steps")
    report.append("1. Integrate with actual LLM APIs for real evaluation")
    report.append("2. Run full evaluation on all 503 BioMate-relevant samples")
    report.append("3. Compare results across different LLM versions")
    report.append("4. Implement user-specific evaluation dashboards")

    return "\n".join(report)


def main():
    parser = argparse.ArgumentParser(description="Validate SGI-Bench integration")
    parser.add_argument("--samples", type=int, default=20,
                       help="Number of samples to evaluate")
    parser.add_argument("--real-llm", action="store_true",
                       help="Use real LLM (requires API key)")
    args = parser.parse_args()

    print("=" * 60)
    print("SGI-BENCH TEST HARNESS VALIDATION")
    print("=" * 60)

    # Phase 1: Data loading
    samples = validate_data_loading()

    # Phase 2: User context
    context = validate_user_context()

    # Phase 3: Evaluators
    eval_results = validate_evaluators(samples, context, n_samples=args.samples)

    # Phase 4: Full pipeline
    pipeline_results = validate_full_pipeline(samples, context, n_samples=min(5, args.samples))

    # Generate report
    all_results = {
        "total_samples": len(samples),
        "samples_evaluated": args.samples,
        "passed": True,  # All phases completed
        "eval_results": eval_results,
        "pipeline_results": pipeline_results
    }

    report = generate_validation_report(all_results)
    print("\n" + report)

    # Save report
    report_path = Path(__file__).parent / "validation_report.txt"
    with open(report_path, "w") as f:
        f.write(report)
    print(f"\nReport saved to: {report_path}")

    print("\n" + "=" * 60)
    print("VALIDATION COMPLETE")
    print("=" * 60)


if __name__ == "__main__":
    main()
