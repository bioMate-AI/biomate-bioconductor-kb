#!/usr/bin/env python3
"""
BioMate E2E Demo Recording - Complete Workflow
Records a video demo of the full user journey:
Registration -> Chat -> Generate Workflow -> Execute -> Progress -> Output -> Report
"""

import os
import time
from datetime import datetime
from playwright.sync_api import sync_playwright, Page

BASE_URL = "http://localhost:5000"
DEMO_DIR = "/home/yzhang/biomate/backend/tests/demo_recordings"
os.makedirs(DEMO_DIR, exist_ok=True)

# Demo scenario - Simple database query (no file upload needed)
DEMO_SCENARIO = {
    "name": "UniProt Protein Query Demo",
    "request": """I need to look up information about the BRCA1 protein from UniProt. Can you query the database to get its sequence and functional annotations?""",
}


def wait_for_ai_response(page: Page, timeout_sec=90):
    """Wait for AI to finish responding"""
    print("    Waiting for AI response...")
    start = time.time()

    # Wait a bit for typing to start
    page.wait_for_timeout(3000)

    while time.time() - start < timeout_sec:
        typing = page.locator("text=AI is typing").first
        if typing.count() == 0:
            page.wait_for_timeout(2000)
            print(f"    AI response complete ({time.time() - start:.1f}s)")
            return True
        page.wait_for_timeout(1500)

    print(f"    Timeout after {timeout_sec}s")
    return False


def wait_for_workflow_completion(page: Page, timeout_sec=180):
    """Wait for workflow execution to complete with progress tracking"""
    print("    Monitoring workflow execution...")
    start = time.time()
    last_progress = ""

    while time.time() - start < timeout_sec:
        # Check for progress indicators
        progress_bar = page.locator("[role='progressbar']").first
        step_text = page.locator("text=/Step \\d+/").first
        running_badge = page.locator("text=Running").first
        completed_badge = page.locator("text=Completed").first

        # Track progress
        current_progress = ""
        if step_text.count() > 0:
            try:
                current_progress = step_text.text_content()
            except:
                pass

        if current_progress and current_progress != last_progress:
            print(f"    Progress: {current_progress}")
            last_progress = current_progress

        # Check for completion states
        completion_indicators = [
            page.locator("text=Workflow completed").first,
            page.locator("text=completed successfully").first,
            page.locator("text=Execution complete").first,
            page.locator("button:has-text('View Results')").first,
            page.locator("button:has-text('View Outputs')").first,
            page.locator("text=View Results").first,
        ]

        for indicator in completion_indicators:
            if indicator.count() > 0:
                print(f"    Workflow completed! ({time.time() - start:.1f}s)")
                return True

        # Check for error states
        error_indicators = [
            page.locator("text=Workflow failed").first,
            page.locator("text=execution failed").first,
            page.locator("text=Error:").first,
        ]

        for error in error_indicators:
            if error.count() > 0:
                try:
                    error_text = error.text_content()
                    print(f"    Workflow error: {error_text}")
                except:
                    print("    Workflow encountered an error")
                return False

        # Check if still running
        if running_badge.count() > 0:
            page.wait_for_timeout(3000)
            continue

        # Check if AI is responding (might be processing results)
        if page.locator("text=AI is typing").first.count() > 0:
            page.wait_for_timeout(2000)
            continue

        page.wait_for_timeout(3000)

    print(f"    Timeout waiting for completion ({timeout_sec}s)")
    return False


def capture_screenshot(page: Page, video_dir: str, name: str):
    """Capture a screenshot with a descriptive name"""
    path = f"{video_dir}/{name}.png"
    page.screenshot(path=path, full_page=True)
    print(f"    Screenshot: {name}.png")
    return path


def run_demo():
    """Run the complete demo with video recording"""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    video_dir = f"{DEMO_DIR}/{timestamp}"
    os.makedirs(video_dir, exist_ok=True)

    print("\n" + "="*70)
    print("  BIOMATE E2E DEMO RECORDING - COMPLETE WORKFLOW")
    print(f"  Output: {video_dir}")
    print("="*70)

    with sync_playwright() as p:
        # Launch browser with video recording
        browser = p.chromium.launch(
            headless=True,
            args=['--no-sandbox']
        )

        context = browser.new_context(
            viewport={"width": 1920, "height": 1080},
            record_video_dir=video_dir,
            record_video_size={"width": 1920, "height": 1080}
        )

        page = context.new_page()

        try:
            # ========== STEP 1: REGISTRATION ==========
            print("\n[STEP 1] User Registration")
            email = f"demo_user_{int(time.time())}@biomate.demo"
            password = "DemoPass123!"

            page.goto(f"{BASE_URL}/register")
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(2000)

            # Wait for form
            page.wait_for_selector("#name", state="visible", timeout=30000)
            print("    Registration form loaded")

            # Fill form
            page.fill("#name", "Demo Researcher")
            page.wait_for_timeout(300)
            page.fill("#email", email)
            page.wait_for_timeout(300)
            page.fill("#password", password)
            page.wait_for_timeout(300)
            page.fill("#confirmPassword", password)
            page.wait_for_timeout(300)

            # Accept terms
            page.click("#terms")
            page.wait_for_timeout(500)

            capture_screenshot(page, video_dir, "01_registration_form")

            # Submit
            page.click("button[type='submit']")
            print(f"    Registered: {email}")
            page.wait_for_timeout(5000)

            # ========== STEP 2: NAVIGATE TO CHAT ==========
            print("\n[STEP 2] Navigate to Chat Interface")
            page.goto(BASE_URL)
            page.wait_for_load_state("networkidle")
            page.wait_for_timeout(3000)

            # Look for chat interface
            chat_input = page.locator("textarea").first
            if chat_input.count() == 0:
                print("    Looking for chat input...")
                page.wait_for_selector("textarea", timeout=30000)

            print("    Chat interface ready")
            capture_screenshot(page, video_dir, "02_chat_interface")

            # ========== STEP 3: SEND RESEARCH REQUEST ==========
            print("\n[STEP 3] Send Research Request")
            print(f"    Request: {DEMO_SCENARIO['request'][:80]}...")

            chat_input = page.locator("textarea").first
            chat_input.fill(DEMO_SCENARIO['request'])
            page.wait_for_timeout(1000)

            capture_screenshot(page, video_dir, "03_research_request")

            # Send message
            chat_input.press("Enter")
            page.wait_for_timeout(2000)
            print("    Message sent")

            # ========== STEP 4: WAIT FOR AI RESPONSE ==========
            print("\n[STEP 4] AI Processing Request")
            wait_for_ai_response(page, timeout_sec=120)
            page.wait_for_timeout(3000)

            capture_screenshot(page, video_dir, "04_workflow_generated")

            # ========== STEP 5: FIND AND CLICK RUN BUTTON ==========
            print("\n[STEP 5] Execute Workflow")

            # Look for run/execute buttons - try multiple selectors
            run_selectors = [
                "button:has-text('Run')",
                "button:has-text('Execute')",
                "button:has-text('Start Workflow')",
                "button:has-text('Run Workflow')",
                "[data-testid='run-workflow']",
            ]

            run_btn = None
            for selector in run_selectors:
                btn = page.locator(selector).first
                if btn.count() > 0:
                    run_btn = btn
                    print(f"    Found button: {selector}")
                    break

            if run_btn is None:
                print("    ERROR: No run button found!")
                capture_screenshot(page, video_dir, "05_error_no_run_button")
                # Try to scroll down to find it
                page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
                page.wait_for_timeout(2000)

                for selector in run_selectors:
                    btn = page.locator(selector).first
                    if btn.count() > 0:
                        run_btn = btn
                        print(f"    Found button after scroll: {selector}")
                        break

            if run_btn:
                # Check if there's a "Skip pilot" option to speed up demo
                skip_pilot = page.locator("button:has-text('Skip pilot')").first
                if skip_pilot.count() > 0:
                    print("    Skipping pilot run for demo speed...")
                    skip_pilot.click()
                    page.wait_for_timeout(1000)

                # Click the run button
                print("    Clicking Run button...")
                run_btn.click()
                page.wait_for_timeout(3000)

                capture_screenshot(page, video_dir, "05_workflow_executing")

                # ========== STEP 6: TRACK EXECUTION PROGRESS ==========
                print("\n[STEP 6] Tracking Workflow Execution")

                # Wait for workflow to complete
                completed = wait_for_workflow_completion(page, timeout_sec=180)

                page.wait_for_timeout(3000)
                capture_screenshot(page, video_dir, "06_workflow_progress")

                # ========== STEP 7: VIEW OUTPUTS ==========
                print("\n[STEP 7] Viewing Outputs")

                # Wait for AI to respond with results
                wait_for_ai_response(page, timeout_sec=60)
                page.wait_for_timeout(3000)

                capture_screenshot(page, video_dir, "07_workflow_results")

                # Look for output/result viewing options
                output_selectors = [
                    "button:has-text('View Results')",
                    "button:has-text('View Outputs')",
                    "button:has-text('Show Results')",
                    "button:has-text('Download')",
                    "[data-testid='view-outputs']",
                ]

                for selector in output_selectors:
                    output_btn = page.locator(selector).first
                    if output_btn.count() > 0:
                        print(f"    Found output button: {selector}")
                        output_btn.click()
                        page.wait_for_timeout(3000)
                        capture_screenshot(page, video_dir, "08_output_view")
                        break

                # ========== STEP 8: CHECK WORKFLOW HISTORY ==========
                print("\n[STEP 8] Checking Workflow History")

                # Look for workflow history button
                history_btn = page.locator("button:has-text('My Workflows')").first
                if history_btn.count() == 0:
                    history_btn = page.locator("button:has-text('Workflow History')").first

                if history_btn.count() > 0:
                    print("    Opening Workflow History...")
                    history_btn.click()
                    page.wait_for_timeout(3000)
                    capture_screenshot(page, video_dir, "09_workflow_history")

                    # Look for the completed workflow in history
                    history_items = page.locator("[class*='Card']").all()
                    print(f"    Found {len(history_items)} workflow(s) in history")

                    # Close history panel
                    close_btn = page.locator("button[aria-label='Close']").first
                    if close_btn.count() > 0:
                        close_btn.click()
                        page.wait_for_timeout(1000)

                # ========== STEP 9: VIEW WORKFLOW REPORT ==========
                print("\n[STEP 9] Checking for Workflow Report")

                report_selectors = [
                    "button:has-text('View Report')",
                    "button:has-text('Report')",
                    "button:has-text('Analysis Summary')",
                    "[data-testid='workflow-report']",
                ]

                for selector in report_selectors:
                    report_btn = page.locator(selector).first
                    if report_btn.count() > 0:
                        print(f"    Found report button: {selector}")
                        report_btn.click()
                        page.wait_for_timeout(3000)
                        capture_screenshot(page, video_dir, "10_workflow_report")
                        break
                else:
                    print("    No separate report button found (results may be inline)")

            else:
                print("    ERROR: Could not find any Run button!")
                capture_screenshot(page, video_dir, "error_no_workflow")

            # ========== FINAL: Capture final state ==========
            print("\n[FINAL] Capturing Final State")
            page.wait_for_timeout(2000)
            capture_screenshot(page, video_dir, "99_final_state")
            page.wait_for_timeout(3000)

            print("\n" + "="*70)
            print("  DEMO RECORDING COMPLETE")
            print("="*70)

        except Exception as e:
            print(f"\nError during demo: {e}")
            import traceback
            traceback.print_exc()
            capture_screenshot(page, video_dir, "error_state")
            raise

        finally:
            # Close context to save video
            context.close()
            browser.close()

    # Find and rename the video file
    print(f"\nLooking for video in {video_dir}...")
    for f in os.listdir(video_dir):
        if f.endswith('.webm'):
            video_path = os.path.join(video_dir, f)
            # Rename to something meaningful
            final_video = os.path.join(video_dir, f"biomate_demo_{timestamp}.webm")
            os.rename(video_path, final_video)
            print(f"Video saved: {final_video}")

            # Convert to MP4 if ffmpeg available
            mp4_path = final_video.replace('.webm', '.mp4')
            os.system(f"ffmpeg -i '{final_video}' -c:v libx264 -crf 23 '{mp4_path}' 2>/dev/null && echo 'MP4 conversion complete: {mp4_path}'")

            return final_video

    print("Warning: Video file not found")
    return None


if __name__ == "__main__":
    video_file = run_demo()
    if video_file:
        print(f"\n✓ Demo video ready: {video_file}")
    else:
        print("\n✗ Demo recording failed")
