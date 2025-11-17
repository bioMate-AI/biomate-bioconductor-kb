"""
Mode Validator for E2E UI Tests

Validates mode detection decisions (iterative vs legacy) against expected values.
Tracks accuracy, latency, and provides detailed validation reports.
"""

from typing import List, Dict, Any, Optional
from enum import Enum


class ExpectedMode(str, Enum):
    """Expected mode types for validation"""
    ITERATIVE = "iterative"
    LEGACY = "legacy"
    EITHER = "either"  # For ambiguous cases where both are acceptable


class ExpertiseLevel(str, Enum):
    """User expertise levels"""
    BEGINNER = "beginner"
    INTERMEDIATE = "intermediate"
    EXPERT = "expert"


class ModeValidator:
    """
    Validate mode detection decisions from Galaxy AI Assistant.

    Validates:
    - Mode decision (iterative vs legacy) matches expected
    - Latency is within acceptable bounds
    - Confidence scores meet thresholds (if available)
    - Accuracy by expertise level
    """

    def __init__(self):
        """Initialize mode validator."""
        self.validation_history = []
        self.accuracy_by_expertise = {
            "beginner": {"passed": 0, "failed": 0},
            "intermediate": {"passed": 0, "failed": 0},
            "expert": {"passed": 0, "failed": 0}
        }

    def validate_mode_decision(
        self,
        scenario_id: str,
        query: str,
        actual_mode: str,
        expected_mode: str,
        expertise_level: str,
        latency_ms: Optional[float] = None,
        confidence: Optional[float] = None,
        reasoning: Optional[str] = None,
        max_latency_ms: float = 10000.0
    ) -> Dict[str, Any]:
        """
        Validate a single mode detection decision.

        Args:
            scenario_id: Unique identifier for the test scenario
            query: The user query being tested
            actual_mode: Mode detected by the system ("iterative" or "legacy")
            expected_mode: Expected mode ("iterative", "legacy", or "either")
            expertise_level: User expertise level ("beginner", "intermediate", "expert")
            latency_ms: Time taken for mode detection in milliseconds
            confidence: Confidence score (0-1) if available
            reasoning: System's reasoning for the decision
            max_latency_ms: Maximum acceptable latency (default 10 seconds)

        Returns:
            Validation result dictionary:
                {
                    "scenario_id": "test_01",
                    "passed": True/False,
                    "mode_correct": True/False,
                    "latency_ok": True/False,
                    "confidence_ok": True/False,
                    "details": {...}
                }
        """
        # Validate mode decision
        mode_correct = self._check_mode_match(actual_mode, expected_mode)

        # Validate latency (if provided)
        latency_ok = True
        if latency_ms is not None:
            latency_ok = latency_ms <= max_latency_ms

        # Validate confidence (if provided)
        confidence_ok = True
        if confidence is not None:
            # Higher threshold for beginners (should be more certain)
            if expertise_level == ExpertiseLevel.BEGINNER:
                confidence_ok = confidence >= 0.7
            # Medium threshold for intermediate
            elif expertise_level == ExpertiseLevel.INTERMEDIATE:
                confidence_ok = confidence >= 0.6
            # Lower threshold for experts (more complex queries)
            else:
                confidence_ok = confidence >= 0.5

        # Overall pass/fail
        passed = mode_correct and latency_ok and confidence_ok

        # Update expertise-level tracking
        if expertise_level in self.accuracy_by_expertise:
            if passed:
                self.accuracy_by_expertise[expertise_level]["passed"] += 1
            else:
                self.accuracy_by_expertise[expertise_level]["failed"] += 1

        # Build result
        result = {
            "scenario_id": scenario_id,
            "query": query,
            "expected_mode": expected_mode,
            "actual_mode": actual_mode,
            "expertise_level": expertise_level,
            "passed": passed,
            "mode_correct": mode_correct,
            "latency_ok": latency_ok,
            "confidence_ok": confidence_ok,
            "latency_ms": latency_ms,
            "confidence": confidence,
            "reasoning": reasoning,
            "max_latency_ms": max_latency_ms,
            "details": {
                "mode_match": mode_correct,
                "expected": expected_mode,
                "actual": actual_mode,
                "latency_status": "ok" if latency_ok else f"too_slow ({latency_ms}ms > {max_latency_ms}ms)",
                "confidence_status": "ok" if confidence_ok else f"too_low ({confidence})"
            }
        }

        # Save to history
        self.validation_history.append(result)

        return result

    def _check_mode_match(self, actual: str, expected: str) -> bool:
        """
        Check if actual mode matches expected mode.

        Args:
            actual: Actual mode detected ("iterative" or "legacy")
            expected: Expected mode ("iterative", "legacy", or "either")

        Returns:
            True if modes match
        """
        # Normalize to lowercase
        actual = actual.lower().strip()
        expected = expected.lower().strip()

        # Handle "either" case
        if expected == ExpectedMode.EITHER:
            return actual in [ExpectedMode.ITERATIVE, ExpectedMode.LEGACY]

        # Direct comparison
        return actual == expected

    def extract_mode_from_response(
        self,
        response_data: Dict[str, Any],
        response_text: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Extract mode decision from API response or UI state.

        Args:
            response_data: Response data from API (e.g., /api/chat/respond)
            response_text: Text response content for parsing

        Returns:
            Extracted mode information:
                {
                    "mode": "iterative" or "legacy",
                    "confidence": 0.85,
                    "reasoning": "...",
                    "latency_ms": 150
                }
        """
        extracted = {
            "mode": None,
            "confidence": None,
            "reasoning": None,
            "latency_ms": None
        }

        # Try to extract from structured response
        if response_data:
            # Check for explicit mode field
            if "mode" in response_data:
                extracted["mode"] = response_data["mode"]

            # Check for mode decision in nested structure
            if "mode_decision" in response_data:
                decision = response_data["mode_decision"]
                extracted["mode"] = decision.get("mode")
                extracted["confidence"] = decision.get("confidence")
                extracted["reasoning"] = decision.get("reasoning")

            # Check for confidence scores
            if "confidence" in response_data:
                extracted["confidence"] = response_data["confidence"]

            # Check for timing information
            if "latency_ms" in response_data:
                extracted["latency_ms"] = response_data["latency_ms"]
            elif "processing_time_ms" in response_data:
                extracted["latency_ms"] = response_data["processing_time_ms"]

        # Try to infer mode from response text
        if extracted["mode"] is None and response_text:
            extracted["mode"] = self._infer_mode_from_text(response_text)

        return extracted

    def _infer_mode_from_text(self, text: str) -> Optional[str]:
        """
        Infer mode from response text based on patterns.

        Args:
            text: Response text to analyze

        Returns:
            "iterative" or "legacy" if detected, None otherwise
        """
        text_lower = text.lower()

        # Iterative mode indicators
        iterative_patterns = [
            "i have a few questions",
            "let me clarify",
            "to help you better",
            "could you provide more information",
            "what kind of",
            "which organism",
            "what is your",
            "before i proceed"
        ]

        # Legacy mode indicators
        legacy_patterns = [
            "here's your workflow",
            "i've generated",
            "workflow created",
            "the workflow includes",
            "generated workflow"
        ]

        # Count pattern matches
        iterative_score = sum(1 for p in iterative_patterns if p in text_lower)
        legacy_score = sum(1 for p in legacy_patterns if p in text_lower)

        # Determine mode based on scores
        if iterative_score > legacy_score:
            return ExpectedMode.ITERATIVE
        elif legacy_score > iterative_score:
            return ExpectedMode.LEGACY
        else:
            return None  # Ambiguous

    def validate_batch(
        self,
        test_scenarios: List[Dict[str, Any]],
        results: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """
        Validate a batch of test scenarios.

        Args:
            test_scenarios: List of expected scenario specifications
                [
                    {
                        "scenario_id": "test_01",
                        "query": "I have some samples...",
                        "expected_mode": "iterative",
                        "expertise_level": "beginner",
                        "max_latency_ms": 5000
                    }
                ]
            results: List of actual results from test execution
                [
                    {
                        "scenario_id": "test_01",
                        "actual_mode": "iterative",
                        "latency_ms": 1200,
                        "confidence": 0.85
                    }
                ]

        Returns:
            Batch validation summary
        """
        batch_results = {
            "total": len(test_scenarios),
            "passed": 0,
            "failed": 0,
            "validations": []
        }

        # Create lookup for results
        results_map = {r["scenario_id"]: r for r in results}

        for scenario in test_scenarios:
            scenario_id = scenario["scenario_id"]
            result = results_map.get(scenario_id)

            if not result:
                # Scenario not executed
                validation = {
                    "scenario_id": scenario_id,
                    "passed": False,
                    "error": "Scenario not executed"
                }
            else:
                # Validate scenario
                validation = self.validate_mode_decision(
                    scenario_id=scenario_id,
                    query=scenario["query"],
                    actual_mode=result.get("actual_mode", "unknown"),
                    expected_mode=scenario["expected_mode"],
                    expertise_level=scenario["expertise_level"],
                    latency_ms=result.get("latency_ms"),
                    confidence=result.get("confidence"),
                    reasoning=result.get("reasoning"),
                    max_latency_ms=scenario.get("max_latency_ms", 10000.0)
                )

            if validation["passed"]:
                batch_results["passed"] += 1
            else:
                batch_results["failed"] += 1

            batch_results["validations"].append(validation)

        # Calculate accuracy
        batch_results["accuracy"] = (
            batch_results["passed"] / batch_results["total"]
            if batch_results["total"] > 0 else 0.0
        )

        return batch_results

    def calculate_overall_accuracy(self) -> float:
        """
        Calculate overall mode detection accuracy.

        Returns:
            Accuracy score (0-1) representing % of correct mode decisions
        """
        if not self.validation_history:
            return 0.0

        passed = sum(1 for v in self.validation_history if v["passed"])
        total = len(self.validation_history)

        return passed / total if total > 0 else 0.0

    def calculate_accuracy_by_expertise(self) -> Dict[str, float]:
        """
        Calculate accuracy broken down by expertise level.

        Returns:
            Dictionary mapping expertise level to accuracy:
                {
                    "beginner": 0.90,
                    "intermediate": 0.85,
                    "expert": 0.80
                }
        """
        accuracy_by_level = {}

        for level, counts in self.accuracy_by_expertise.items():
            total = counts["passed"] + counts["failed"]
            if total > 0:
                accuracy_by_level[level] = counts["passed"] / total
            else:
                accuracy_by_level[level] = 0.0

        return accuracy_by_level

    def get_summary(self) -> Dict[str, Any]:
        """
        Get comprehensive summary of all validations.

        Returns:
            Summary statistics including accuracy, latency, confidence
        """
        if not self.validation_history:
            return {
                "total_validations": 0,
                "overall_accuracy": 0.0,
                "accuracy_by_expertise": {},
                "avg_latency_ms": 0.0,
                "avg_confidence": 0.0
            }

        total = len(self.validation_history)
        passed = sum(1 for v in self.validation_history if v["passed"])
        mode_correct = sum(1 for v in self.validation_history if v["mode_correct"])

        # Latency stats (only for validations with latency data)
        latencies = [v["latency_ms"] for v in self.validation_history if v["latency_ms"] is not None]
        avg_latency = sum(latencies) / len(latencies) if latencies else 0.0
        max_latency = max(latencies) if latencies else 0.0

        # Confidence stats (only for validations with confidence data)
        confidences = [v["confidence"] for v in self.validation_history if v["confidence"] is not None]
        avg_confidence = sum(confidences) / len(confidences) if confidences else 0.0

        return {
            "total_validations": total,
            "passed": passed,
            "failed": total - passed,
            "overall_accuracy": passed / total,
            "mode_accuracy": mode_correct / total,
            "accuracy_by_expertise": self.calculate_accuracy_by_expertise(),
            "latency_stats": {
                "avg_ms": avg_latency,
                "max_ms": max_latency,
                "count": len(latencies)
            },
            "confidence_stats": {
                "avg": avg_confidence,
                "count": len(confidences)
            }
        }

    def generate_validation_report(self, output_path: Optional[str] = None) -> str:
        """
        Generate detailed validation report.

        Args:
            output_path: Optional path to save report as JSON

        Returns:
            Formatted report string
        """
        summary = self.get_summary()

        # Build report
        lines = [
            "=" * 80,
            "MODE DETECTION VALIDATION REPORT",
            "=" * 80,
            "",
            f"Total Scenarios: {summary['total_validations']}",
            f"Passed: {summary['passed']} ({summary['overall_accuracy']:.1%})",
            f"Failed: {summary['failed']}",
            "",
            "Accuracy by Expertise Level:",
        ]

        for level, accuracy in summary['accuracy_by_expertise'].items():
            counts = self.accuracy_by_expertise[level]
            total = counts['passed'] + counts['failed']
            lines.append(f"  {level.capitalize()}: {accuracy:.1%} ({counts['passed']}/{total})")

        lines.extend([
            "",
            "Performance Metrics:",
            f"  Avg Latency: {summary['latency_stats']['avg_ms']:.2f}ms",
            f"  Max Latency: {summary['latency_stats']['max_ms']:.2f}ms",
            f"  Avg Confidence: {summary['confidence_stats']['avg']:.2f}",
            "",
            "=" * 80,
            "FAILED SCENARIOS:",
            "=" * 80,
            ""
        ])

        # List failed scenarios
        failed_validations = [v for v in self.validation_history if not v["passed"]]
        if failed_validations:
            for v in failed_validations:
                lines.extend([
                    f"Scenario: {v['scenario_id']} ({v['expertise_level']})",
                    f"  Query: {v['query'][:80]}...",
                    f"  Expected: {v['expected_mode']} | Actual: {v['actual_mode']}",
                    f"  Mode Correct: {v['mode_correct']}",
                    f"  Latency: {v['latency_ms']}ms (OK: {v['latency_ok']})",
                    f"  Confidence: {v['confidence']} (OK: {v['confidence_ok']})",
                    ""
                ])
        else:
            lines.append("No failed scenarios! 🎉")

        report = "\n".join(lines)

        # Save to file if requested
        if output_path:
            import json
            report_data = {
                "summary": summary,
                "validations": self.validation_history
            }
            with open(output_path, 'w') as f:
                json.dump(report_data, f, indent=2)

        return report

    def __repr__(self):
        summary = self.get_summary()
        return (
            f"ModeValidator("
            f"validations={summary['total_validations']}, "
            f"accuracy={summary['overall_accuracy']:.2%}, "
            f"avg_latency={summary['latency_stats']['avg_ms']:.1f}ms)"
        )
