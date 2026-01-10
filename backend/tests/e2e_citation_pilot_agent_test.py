#!/usr/bin/env python3
"""
Citation & Pilot Run LLM Agent E2E Test

Uses Claude as a simulated researcher to test:
1. Citation display and export functionality
2. Pilot run configuration and monitoring
3. Parameter recommendations and application
4. Methods section generation

Tests via BioMate interface with AI-driven conversation.
"""

import os
import sys
import time
import json
from datetime import datetime
from typing import Dict, Any, List, Optional

from anthropic import Anthropic
from playwright.sync_api import sync_playwright, Page, Browser

BASE_URL = os.environ.get("BIOMATE_URL", "http://localhost:5000")
SCREENSHOT_DIR = "/home/yzhang/biomate/backend/tests/screenshots/citation_pilot"
os.makedirs(SCREENSHOT_DIR, exist_ok=True)

# Initialize Claude as the simulated user
anthropic = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))


# =============================================================================
# Test Scenarios - Citation and Pilot Run Features
# =============================================================================

CITATION_PILOT_SCENARIOS = [
    {
        "name": "RNA-seq Workflow with Citation Check",
        "category": "citation",
        "researcher_persona": """You are Dr. Sarah Chen, a computational biologist.
You are preparing a methods section for a publication and need proper citations.
You want to generate an RNA-seq analysis workflow and ensure all tools are properly cited.""",
        "initial_request": """I need to analyze RNA-seq data for my paper.
Can you create a workflow with FastQC for quality control, STAR for alignment, and DESeq2 for differential expression?
I'll need the citations for my methods section.""",
        "validation_checks": [
            "citation_badge_visible",
            "workflow_generated",
        ],
        "follow_up_actions": [
            "view_citations",
            "copy_methods_section",
            "export_bibtex"
        ]
    },
    {
        "name": "Large Dataset with Pilot Run Suggestion",
        "category": "pilot_run",
        "researcher_persona": """You are Dr. Michael Torres, a genomics researcher.
You have a large dataset with 200 samples and want to optimize parameters before running the full analysis.
You appreciate efficiency and want to avoid wasting computational resources.""",
        "initial_request": """I have 200 RNA-seq samples to analyze.
Can you create a comprehensive workflow for differential expression analysis?
I want to make sure the parameters are optimal before running the full dataset.""",
        "validation_checks": [
            "workflow_generated",
            "pilot_run_suggested",
        ],
        "follow_up_actions": [
            "configure_pilot_run",
            "start_pilot_run",
            "view_pilot_results"
        ]
    },
    {
        "name": "Methods Section Generation with Style Selection",
        "category": "citation",
        "researcher_persona": """You are Dr. Emily Watson, preparing a manuscript for Nature Methods.
You need a professionally formatted methods section with proper APA citations.
You want to regenerate the methods in different citation styles.""",
        "initial_request": """I'm writing up my variant calling pipeline for publication.
Please create a workflow using BWA for alignment and GATK for variant calling.
I need a publication-ready methods section with APA-style citations.""",
        "validation_checks": [
            "workflow_generated",
            "citation_badge_visible",
            "methods_section_available"
        ],
        "follow_up_actions": [
            "view_citations",
            "change_citation_style",
            "copy_methods_section"
        ]
    },
    {
        "name": "Parameter Recommendations from Pilot Run",
        "category": "pilot_run",
        "researcher_persona": """You are Dr. James Liu, a bioinformatics specialist.
You ran a pilot and want to review the recommended parameter changes.
You're interested in optimizing thread count and memory usage.""",
        "initial_request": """I need to set up a ChIP-seq analysis pipeline for peak calling.
I have 150 samples and limited compute resources.
Can you help me optimize the workflow parameters?""",
        "validation_checks": [
            "workflow_generated",
        ],
        "follow_up_actions": [
            "request_pilot_run",
            "apply_recommendations"
        ]
    },
    {
        "name": "Export All Citations as BibTeX",
        "category": "citation",
        "researcher_persona": """You are Dr. Anna Schmidt, a postdoc managing references in Zotero.
You want to export all tool citations as a BibTeX file for your reference manager.
You value automation and efficiency.""",
        "initial_request": """Create a metagenomics workflow with Kraken2 for classification and MetaPhlAn for profiling.
I need to export all the citations as a BibTeX file for my reference manager.""",
        "validation_checks": [
            "workflow_generated",
            "citation_badge_visible"
        ],
        "follow_up_actions": [
            "view_citations",
            "export_bibtex",
            "verify_download"
        ]
    }
]


# =============================================================================
# AI Agent Functions
# =============================================================================

def ai_researcher_responds(
    conversation_history: List[Dict],
    biomate_message: str,
    persona: str,
    current_goal: str = ""
) -> str:
    """
    AI agent acts as a researcher responding to BioMate's questions.
    Focuses on driving toward citation and pilot run feature testing.
    """

    system_prompt = f"""{persona}

CURRENT GOAL: {current_goal}

IMPORTANT BEHAVIORS FOR TESTING:
- When a workflow is generated, ask to see the citations
- If pilot run is suggested, express interest in configuring it
- Be specific about wanting to export citations or copy methods sections
- Confirm parameters and proceed with suggested optimizations
- Ask about citation styles (APA, short, numbered) when viewing methods
- Request BibTeX export when viewing citations

When responding:
- Be natural but focused on testing the citation/pilot features
- Keep responses concise (1-3 sentences)
- Explicitly mention wanting to use citation or pilot run features
"""

    messages = conversation_history + [{
        "role": "user",
        "content": f"BioMate says: {biomate_message}\n\nRespond as the researcher (1-3 sentences):"
    }]

    response = anthropic.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=300,
        system=system_prompt,
        messages=messages
    )

    answer = response.content[0].text.strip()

    # Update conversation history
    conversation_history.append({"role": "user", "content": biomate_message})
    conversation_history.append({"role": "assistant", "content": answer})

    return answer


def ai_decides_next_action(
    page_state: Dict[str, Any],
    scenario: Dict,
    completed_actions: List[str]
) -> Optional[str]:
    """
    AI agent decides what action to take next based on page state.
    Returns the next action to perform or None if done.
    """

    pending_actions = [a for a in scenario["follow_up_actions"] if a not in completed_actions]

    if not pending_actions:
        return None

    # Determine next action based on page state and pending actions
    next_action = pending_actions[0]

    # Check if prerequisites are met
    if next_action == "view_citations" and not page_state.get("citation_badge_visible"):
        return None  # Can't view citations if badge not visible

    if next_action in ["start_pilot_run", "view_pilot_results"] and not page_state.get("pilot_panel_open"):
        if "configure_pilot_run" in pending_actions:
            return "configure_pilot_run"

    return next_action


# =============================================================================
# Page Interaction Helpers
# =============================================================================

def wait_for_ai_response(page: Page, timeout_ms: int = 90000) -> bool:
    """Wait for AI to finish typing."""
    print("    Waiting for AI response...")
    start_time = time.time()
    max_wait = timeout_ms / 1000

    page.wait_for_timeout(2000)

    while time.time() - start_time < max_wait:
        typing_indicator = page.locator("text=AI is typing").first
        loading_indicator = page.locator("[data-testid='loading-indicator']").first

        if typing_indicator.count() == 0 and loading_indicator.count() == 0:
            page.wait_for_timeout(1500)
            print(f"    Response completed after {time.time() - start_time:.1f}s")
            return True
        page.wait_for_timeout(1000)

    print(f"    Timeout after {max_wait}s")
    return False


def extract_biomate_response(page: Page) -> Optional[str]:
    """Extract the last response from BioMate."""
    try:
        page.wait_for_timeout(1500)

        # Try to get chat messages
        messages = page.locator("[data-testid^='chat-message-']").all()
        if messages:
            last_message = messages[-1].inner_text()
            if last_message and len(last_message) > 20:
                return last_message

        # Fallback to chat container
        chat_container = page.locator("[data-testid='chat-messages']").first
        if chat_container.count() > 0:
            return chat_container.inner_text()

    except Exception as e:
        print(f"    Error extracting message: {e}")
    return None


def get_page_state(page: Page) -> Dict[str, Any]:
    """Analyze current page state for decision making."""
    state = {
        "workflow_generated": False,
        "citation_badge_visible": False,
        "citation_panel_open": False,
        "pilot_button_visible": False,
        "pilot_panel_open": False,
        "methods_section_visible": False,
        "export_button_visible": False,
        "pilot_results_visible": False,
        "recommendations_visible": False
    }

    try:
        # Check for workflow artifact
        workflow_card = page.locator("[data-testid='workflow-artifact']").first
        if workflow_card.count() == 0:
            workflow_card = page.locator("text=Generated Workflow").first
        state["workflow_generated"] = workflow_card.count() > 0

        # Check for citation badge (e.g., "5 citations")
        citation_badge = page.locator("button:has-text('citation')").first
        if citation_badge.count() == 0:
            citation_badge = page.locator("text=/\\d+ citation/").first
        state["citation_badge_visible"] = citation_badge.count() > 0

        # Check if citation panel is open
        citation_panel = page.locator("text=Tool Citations").first
        state["citation_panel_open"] = citation_panel.count() > 0

        # Check for pilot run button
        pilot_button = page.locator("button:has-text('Pilot')").first
        state["pilot_button_visible"] = pilot_button.count() > 0

        # Check if pilot panel is open
        pilot_panel = page.locator("text=Pilot Run Configuration").first
        if pilot_panel.count() == 0:
            pilot_panel = page.locator("text=Pilot Size").first
        state["pilot_panel_open"] = pilot_panel.count() > 0

        # Check for methods section tab
        methods_tab = page.locator("text=Methods Section").first
        state["methods_section_visible"] = methods_tab.count() > 0

        # Check for export button
        export_btn = page.locator("button:has-text('Export BibTeX')").first
        state["export_button_visible"] = export_btn.count() > 0

        # Check for pilot results
        pilot_results = page.locator("text=Pilot Run Complete").first
        if pilot_results.count() == 0:
            pilot_results = page.locator("text=Full Run Estimate").first
        state["pilot_results_visible"] = pilot_results.count() > 0

        # Check for parameter recommendations
        recommendations = page.locator("text=recommended").first
        state["recommendations_visible"] = recommendations.count() > 0

    except Exception as e:
        print(f"    Error getting page state: {e}")

    return state


def perform_action(page: Page, action: str, scenario_num: int) -> bool:
    """Perform a specific UI action and return success status."""
    print(f"    Performing action: {action}")

    try:
        if action == "view_citations":
            # Click on citation badge/button
            citation_btn = page.locator("button:has-text('citation')").first
            if citation_btn.count() > 0:
                citation_btn.click()
                page.wait_for_timeout(1500)
                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True
            return False

        elif action == "copy_methods_section":
            # Click Methods Section tab, then Copy button
            methods_tab = page.locator("text=Methods Section").first
            if methods_tab.count() > 0:
                methods_tab.click()
                page.wait_for_timeout(1000)

                copy_btn = page.locator("button:has-text('Copy')").first
                if copy_btn.count() > 0:
                    copy_btn.click()
                    page.wait_for_timeout(500)
                    page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                    return True
            return False

        elif action == "export_bibtex":
            # Click Export BibTeX button
            export_btn = page.locator("button:has-text('Export BibTeX')").first
            if export_btn.count() > 0:
                # Set up download handler
                with page.expect_download(timeout=10000) as download_info:
                    export_btn.click()
                download = download_info.value
                print(f"    Downloaded: {download.suggested_filename}")
                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True
            return False

        elif action == "configure_pilot_run":
            # Click Pilot Run button to open panel
            pilot_btn = page.locator("button:has-text('Pilot')").first
            if pilot_btn.count() > 0:
                pilot_btn.click()
                page.wait_for_timeout(1500)
                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True
            return False

        elif action == "start_pilot_run":
            # Click Start Pilot Run button
            start_btn = page.locator("button:has-text('Start Pilot')").first
            if start_btn.count() > 0:
                start_btn.click()
                page.wait_for_timeout(2000)

                # Wait for pilot to complete (up to 30s for simulated pilot)
                for _ in range(15):
                    complete = page.locator("text=Pilot Run Complete").first
                    if complete.count() > 0:
                        break
                    page.wait_for_timeout(2000)

                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True
            return False

        elif action == "view_pilot_results":
            # Just verify results are visible
            results = page.locator("text=Full Run Estimate").first
            page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
            return results.count() > 0

        elif action == "change_citation_style":
            # Click style selector and change to APA
            style_select = page.locator("button:has-text('Short')").first
            if style_select.count() == 0:
                style_select = page.locator("[role='combobox']").first

            if style_select.count() > 0:
                style_select.click()
                page.wait_for_timeout(500)

                apa_option = page.locator("text=APA").first
                if apa_option.count() > 0:
                    apa_option.click()
                    page.wait_for_timeout(2000)
                    page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                    return True
            return False

        elif action == "apply_recommendations":
            # Click Apply All or individual Apply buttons
            apply_all_btn = page.locator("button:has-text('Apply All')").first
            if apply_all_btn.count() > 0:
                apply_all_btn.click()
                page.wait_for_timeout(1000)
                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True

            # Try individual apply button
            apply_btn = page.locator("button:has-text('Apply')").first
            if apply_btn.count() > 0:
                apply_btn.click()
                page.wait_for_timeout(1000)
                page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
                return True
            return False

        elif action == "request_pilot_run":
            # Send message asking for pilot run
            chat_input = page.locator("textarea").first
            chat_input.fill("Can we run a pilot on a subset of samples first to optimize the parameters?")
            chat_input.press("Enter")
            page.wait_for_timeout(2000)
            wait_for_ai_response(page)
            page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
            return True

        elif action == "verify_download":
            # Just take a screenshot, download was handled in export_bibtex
            page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}.png")
            return True

        else:
            print(f"    Unknown action: {action}")
            return False

    except Exception as e:
        print(f"    Action failed: {e}")
        page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_{action}_error.png")
        return False


# =============================================================================
# Scenario Runner
# =============================================================================

def run_scenario(page: Page, scenario: Dict, scenario_num: int) -> Dict[str, Any]:
    """Run a single test scenario with AI-driven conversation."""

    result = {
        "name": scenario["name"],
        "category": scenario["category"],
        "success": False,
        "validation_passed": [],
        "validation_failed": [],
        "actions_completed": [],
        "actions_failed": [],
        "turns": 0,
        "error": None
    }

    print(f"\n{'='*80}")
    print(f"  SCENARIO {scenario_num}: {scenario['name']}")
    print(f"  Category: {scenario['category']}")
    print(f"{'='*80}")

    conversation_history = []
    completed_actions = []

    try:
        # Send initial request
        print(f"\n[Initial Request]")
        print(f"  Researcher: {scenario['initial_request'][:100]}...")

        chat_input = page.locator("textarea").first
        chat_input.fill(scenario["initial_request"])
        page.wait_for_timeout(500)
        chat_input.press("Enter")

        page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_01_request.png")

        # Conversation loop - up to 8 turns
        for turn in range(8):
            result["turns"] = turn + 1
            print(f"\n[Turn {turn + 1}]")

            # Wait for AI response
            wait_for_ai_response(page, timeout_ms=90000)

            page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_turn_{turn}.png")

            # Get current page state
            page_state = get_page_state(page)
            print(f"    Page state: workflow={page_state['workflow_generated']}, "
                  f"citations={page_state['citation_badge_visible']}, "
                  f"pilot={page_state['pilot_button_visible']}")

            # Validate required checks
            for check in scenario["validation_checks"]:
                if check in page_state and page_state[check]:
                    if check not in result["validation_passed"]:
                        result["validation_passed"].append(check)
                        print(f"    Validation PASSED: {check}")

            # Check if we should perform UI actions
            next_action = ai_decides_next_action(page_state, scenario, completed_actions)

            if next_action:
                success = perform_action(page, next_action, scenario_num)
                if success:
                    completed_actions.append(next_action)
                    result["actions_completed"].append(next_action)
                    print(f"    Action completed: {next_action}")
                else:
                    result["actions_failed"].append(next_action)
                    print(f"    Action failed: {next_action}")

                # Update page state after action
                page_state = get_page_state(page)

            # Check if all validations and actions are complete
            all_validated = all(
                check in result["validation_passed"]
                for check in scenario["validation_checks"]
            )
            all_actions = all(
                action in completed_actions
                for action in scenario["follow_up_actions"]
            )

            if all_validated and all_actions:
                print(f"\n  All validations passed and actions completed!")
                result["success"] = True
                break

            # Continue conversation if needed
            biomate_message = extract_biomate_response(page)

            if biomate_message and len(biomate_message) > 20:
                # Determine current goal for AI
                pending_validations = [
                    v for v in scenario["validation_checks"]
                    if v not in result["validation_passed"]
                ]
                pending_actions = [
                    a for a in scenario["follow_up_actions"]
                    if a not in completed_actions
                ]

                current_goal = ""
                if pending_validations:
                    current_goal = f"Need to see: {', '.join(pending_validations)}"
                elif pending_actions:
                    current_goal = f"Want to: {', '.join(pending_actions)}"

                # AI responds
                ai_response = ai_researcher_responds(
                    conversation_history,
                    biomate_message,
                    scenario["researcher_persona"],
                    current_goal
                )
                print(f"  Researcher: {ai_response[:100]}...")

                # Send response
                chat_input = page.locator("textarea").first
                chat_input.fill(ai_response)
                chat_input.press("Enter")
                page.wait_for_timeout(2000)

        # Final validation check
        page_state = get_page_state(page)
        for check in scenario["validation_checks"]:
            if check not in result["validation_passed"]:
                if check in page_state and page_state[check]:
                    result["validation_passed"].append(check)
                else:
                    result["validation_failed"].append(check)

        # Mark success if all critical validations passed
        critical_passed = len(result["validation_failed"]) == 0
        actions_mostly_done = len(result["actions_completed"]) >= len(scenario["follow_up_actions"]) // 2

        if critical_passed and actions_mostly_done:
            result["success"] = True

        page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_final.png")

    except Exception as e:
        result["error"] = str(e)
        print(f"  Error: {e}")
        page.screenshot(path=f"{SCREENSHOT_DIR}/scenario_{scenario_num}_error.png")

    status = "PASS" if result["success"] else "FAIL"
    print(f"\n  Result: {status}")
    print(f"  Validations: {len(result['validation_passed'])}/{len(scenario['validation_checks'])}")
    print(f"  Actions: {len(result['actions_completed'])}/{len(scenario['follow_up_actions'])}")

    return result


# =============================================================================
# Main Test Runner
# =============================================================================

def run_citation_pilot_e2e_test(scenarios: Optional[List[Dict]] = None) -> List[Dict]:
    """Run all citation and pilot run E2E test scenarios."""

    if scenarios is None:
        scenarios = CITATION_PILOT_SCENARIOS

    print("\n" + "="*80)
    print("  CITATION & PILOT RUN LLM AGENT E2E TEST SUITE")
    print("  Testing: Citations, Methods Section, Pilot Runs, Parameter Recommendations")
    print("="*80)
    print(f"  Base URL: {BASE_URL}")
    print(f"  Screenshot Dir: {SCREENSHOT_DIR}")
    print(f"  Scenarios: {len(scenarios)}")

    results = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        context = browser.new_context(
            viewport={"width": 1600, "height": 1000},
            accept_downloads=True  # Enable download handling
        )
        page = context.new_page()

        try:
            # Register new test user
            print("\n[SETUP] User Registration")
            email = f"citation_test_{int(time.time())}@biomate.test"
            password = "TestPass123!"

            page.goto(f"{BASE_URL}/register")
            page.wait_for_load_state("networkidle")

            # Wait for registration form
            print("    Waiting for registration form...")
            page.wait_for_selector("#name", state="visible", timeout=30000)

            page.fill("#name", "Citation Test User")
            page.fill("#email", email)
            page.fill("#password", password)
            page.fill("#confirmPassword", password)

            terms_checkbox = page.locator("#terms")
            if terms_checkbox.count() > 0:
                terms_checkbox.click()

            page.click("button[type='submit']")
            page.wait_for_timeout(5000)

            print(f"    Registered: {email}")

            # Navigate to chat
            page.goto(BASE_URL)
            page.wait_for_timeout(3000)
            page.screenshot(path=f"{SCREENSHOT_DIR}/setup_complete.png")

            # Run each test scenario
            for i, scenario in enumerate(scenarios, 1):
                # Try to start new chat
                new_chat_btn = page.locator("button:has-text('New Chat')").first
                if new_chat_btn.count() > 0:
                    new_chat_btn.click()
                    page.wait_for_timeout(2000)
                else:
                    # Refresh page for clean state
                    page.goto(BASE_URL)
                    page.wait_for_timeout(3000)

                result = run_scenario(page, scenario, i)
                results.append(result)

                # Pause between scenarios
                page.wait_for_timeout(2000)

        except Exception as e:
            print(f"\nTest suite error: {e}")
            page.screenshot(path=f"{SCREENSHOT_DIR}/suite_error.png")

        finally:
            browser.close()

    # Print summary
    print("\n" + "="*80)
    print("  TEST SUMMARY")
    print("="*80)

    passed = sum(1 for r in results if r["success"])
    total = len(results)

    by_category = {}
    for r in results:
        cat = r["category"]
        if cat not in by_category:
            by_category[cat] = {"passed": 0, "total": 0}
        by_category[cat]["total"] += 1
        if r["success"]:
            by_category[cat]["passed"] += 1

    print("\nBy Category:")
    for cat, stats in by_category.items():
        print(f"  {cat}: {stats['passed']}/{stats['total']}")

    print("\nDetailed Results:")
    for r in results:
        status = "PASS" if r["success"] else "FAIL"
        validations = f"{len(r['validation_passed'])}/{len(r['validation_passed']) + len(r['validation_failed'])}"
        actions = f"{len(r['actions_completed'])}/{len(r['actions_completed']) + len(r['actions_failed'])}"
        error_msg = f" - {r['error'][:40]}" if r.get("error") else ""

        print(f"  [{status}] {r['name']}")
        print(f"         Validations: {validations}, Actions: {actions}, Turns: {r['turns']}{error_msg}")

    print(f"\nOverall: {passed}/{total} scenarios passed")
    print(f"Screenshots: {SCREENSHOT_DIR}")
    print("="*80 + "\n")

    # Save results to JSON
    results_file = f"{SCREENSHOT_DIR}/results_{int(time.time())}.json"
    with open(results_file, "w") as f:
        json.dump({
            "timestamp": datetime.now().isoformat(),
            "total": total,
            "passed": passed,
            "failed": total - passed,
            "scenarios": results
        }, f, indent=2)
    print(f"Results saved to: {results_file}")

    return results


def main():
    """Main entry point."""
    import argparse

    parser = argparse.ArgumentParser(description="Citation & Pilot Run LLM Agent E2E Tests")
    parser.add_argument(
        "--base-url",
        default=os.environ.get("BIOMATE_URL", "http://localhost:5000"),
        help="Base URL for BioMate server"
    )
    parser.add_argument(
        "--scenario",
        type=int,
        help="Run specific scenario by number (1-indexed)"
    )
    parser.add_argument(
        "--category",
        choices=["citation", "pilot_run"],
        help="Run only scenarios of this category"
    )

    args = parser.parse_args()

    global BASE_URL
    BASE_URL = args.base_url

    # Filter scenarios if requested
    scenarios = CITATION_PILOT_SCENARIOS

    if args.scenario:
        if 1 <= args.scenario <= len(scenarios):
            scenarios = [scenarios[args.scenario - 1]]
        else:
            print(f"Invalid scenario number. Must be 1-{len(scenarios)}")
            sys.exit(1)

    if args.category:
        scenarios = [s for s in scenarios if s["category"] == args.category]

    if not scenarios:
        print("No scenarios to run!")
        sys.exit(1)

    results = run_citation_pilot_e2e_test(scenarios)

    # Exit with appropriate code
    failed = sum(1 for r in results if not r["success"])
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
