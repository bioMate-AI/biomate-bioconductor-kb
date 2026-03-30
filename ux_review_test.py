#!/usr/bin/env python3
"""
BioMate UX Review Test Script
Performs a hands-on walkthrough of the application and captures observations.
"""
import asyncio
import time
from playwright.async_api import async_playwright, Page, expect
import json
from datetime import datetime

class UXReviewer:
    def __init__(self):
        self.observations = {
            "first_impression": [],
            "navigation": [],
            "chat_interaction": [],
            "workflow_execution": [],
            "results_interaction": [],
            "issues": [],
            "positive_findings": []
        }
        
    def log(self, category: str, observation: str, severity: str = "info"):
        """Log an observation"""
        entry = {
            "timestamp": datetime.now().isoformat(),
            "observation": observation,
            "severity": severity
        }
        self.observations[category].append(entry)
        print(f"[{category.upper()}] {severity.upper()}: {observation}")
    
    async def take_screenshot(self, page: Page, name: str):
        """Take a screenshot for documentation"""
        await page.screenshot(path=f"/tmp/biomate_ux_{name}.png")
        print(f"Screenshot saved: {name}")
    
    async def review_first_impression(self, page: Page):
        """Step 1: First impression and onboarding"""
        print("\n=== STEP 1: First Impression & Onboarding ===")
        
        await page.goto("http://localhost:5300", wait_until="networkidle")
        await asyncio.sleep(2)
        await self.take_screenshot(page, "01_landing")
        
        # Check page title
        title = await page.title()
        self.log("first_impression", f"Page title: {title}")
        
        # Look for key elements
        try:
            # Check for header/branding
            header = page.locator("header, [role='banner'], h1").first
            if await header.count() > 0:
                header_text = await header.text_content()
                self.log("first_impression", f"Header found: {header_text}", "info")
            else:
                self.log("first_impression", "No clear header/branding visible", "medium")
        except Exception as e:
            self.log("first_impression", f"Error checking header: {str(e)}", "low")
        
        # Check for onboarding/welcome message
        try:
            welcome_elements = await page.locator("text=/welcome|getting started|introduction/i").all()
            if welcome_elements:
                self.log("first_impression", f"Found {len(welcome_elements)} onboarding elements", "info")
            else:
                self.log("first_impression", "No obvious onboarding/welcome message", "low")
        except Exception as e:
            pass
        
        # Check for chat interface
        try:
            chat_input = page.locator("textarea, input[type='text'], [contenteditable='true']").first
            if await chat_input.count() > 0:
                placeholder = await chat_input.get_attribute("placeholder") or ""
                self.log("first_impression", f"Chat input found with placeholder: '{placeholder}'", "info")
                if not placeholder:
                    self.log("first_impression", "Chat input has no placeholder text - unclear what to type", "medium")
            else:
                self.log("first_impression", "No chat input immediately visible", "high")
        except Exception as e:
            self.log("first_impression", f"Error checking chat input: {str(e)}", "medium")
        
        # Check for navigation elements
        nav_items = await page.locator("nav, [role='navigation'], a[href]").count()
        self.log("first_impression", f"Found {nav_items} navigation elements", "info")
        
        # Check for trust cues (logos, documentation links, etc.)
        links = await page.locator("a").all()
        link_texts = []
        for link in links[:10]:  # Check first 10 links
            text = await link.text_content()
            if text and text.strip():
                link_texts.append(text.strip())
        self.log("first_impression", f"Visible links: {', '.join(link_texts[:5])}", "info")
    
    async def test_chat_workflow_request(self, page: Page):
        """Step 2: Send workflow request in chat"""
        print("\n=== STEP 2: Chat Workflow Request ===")
        
        # Find chat input
        chat_input = page.locator("textarea, input[type='text'], [contenteditable='true']").first
        
        if await chat_input.count() == 0:
            self.log("chat_interaction", "Cannot find chat input field", "critical")
            return False
        
        # Type the workflow request
        workflow_request = "Build me a quality control workflow for RNA-seq FASTQ files"
        await chat_input.click()
        await asyncio.sleep(0.5)
        await chat_input.fill(workflow_request)
        self.log("chat_interaction", f"Typed request: '{workflow_request}'", "info")
        await self.take_screenshot(page, "02_typed_request")
        
        # Find and click send button
        send_button = page.locator("button:has-text('Send'), button[type='submit'], button:has(svg)").first
        if await send_button.count() > 0:
            await send_button.click()
            self.log("chat_interaction", "Send button clicked", "info")
        else:
            # Try pressing Enter
            await chat_input.press("Enter")
            self.log("chat_interaction", "Pressed Enter to send (no visible send button)", "low")
        
        await asyncio.sleep(1)
        await self.take_screenshot(page, "03_request_sent")
        
        # Wait for response
        self.log("chat_interaction", "Waiting for AI response...", "info")
        try:
            # Wait for new content to appear (timeout 30s)
            await page.wait_for_function(
                "document.body.innerText.length > arguments[0]",
                arg=len(await page.locator("body").text_content()),
                timeout=30000
            )
            await asyncio.sleep(2)  # Let animations finish
            self.log("chat_interaction", "Response received", "info")
        except Exception as e:
            self.log("chat_interaction", f"Timeout waiting for response: {str(e)}", "high")
            return False
        
        await self.take_screenshot(page, "04_response_received")
        return True
    
    async def examine_response_artifact(self, page: Page):
        """Step 3: Examine response clarity and controls"""
        print("\n=== STEP 3: Examine Response Artifact ===")
        
        # Get all visible text to analyze response
        body_text = await page.locator("body").text_content()
        
        # Check for workflow artifact/card
        workflow_cards = await page.locator("[class*='workflow'], [class*='artifact'], [data-testid*='workflow']").count()
        self.log("workflow_execution", f"Found {workflow_cards} workflow-related elements", "info")
        
        # Look for action buttons (Run, Execute, etc.)
        action_buttons = await page.locator("button:has-text('Run'), button:has-text('Execute'), button:has-text('Start')").all()
        if action_buttons:
            self.log("workflow_execution", f"Found {len(action_buttons)} action buttons", "info")
            for btn in action_buttons[:3]:
                btn_text = await btn.text_content()
                is_visible = await btn.is_visible()
                is_enabled = await btn.is_enabled()
                self.log("workflow_execution", 
                        f"Button '{btn_text}' - visible: {is_visible}, enabled: {is_enabled}", "info")
        else:
            self.log("workflow_execution", "No obvious Run/Execute buttons found", "high")
        
        # Check for workflow description/explanation
        if "quality control" in body_text.lower() and "rna-seq" in body_text.lower():
            self.log("workflow_execution", "Response mentions QC and RNA-seq (relevant)", "info")
        else:
            self.log("workflow_execution", "Response may not be relevant to request", "medium")
        
        # Check for parameter inputs or configuration options
        inputs = await page.locator("input, select, textarea").count()
        self.log("workflow_execution", f"Found {inputs} input fields (parameters?)", "info")
        
        await self.take_screenshot(page, "05_artifact_examined")
    
    async def execute_workflow(self, page: Page):
        """Step 4: Execute workflow using run control"""
        print("\n=== STEP 4: Execute Workflow ===")
        
        # Find Run button
        run_button = page.locator("button:has-text('Run'), button:has-text('Execute'), button:has-text('Start')").first
        
        if await run_button.count() == 0:
            self.log("workflow_execution", "Cannot find Run button to execute workflow", "critical")
            return False
        
        # Check if button is enabled
        if not await run_button.is_enabled():
            self.log("workflow_execution", "Run button is disabled - unclear why", "high")
            # Check for error messages or requirements
            error_msgs = await page.locator("[class*='error'], [role='alert']").all()
            for msg in error_msgs:
                text = await msg.text_content()
                self.log("workflow_execution", f"Error/alert visible: {text}", "medium")
            return False
        
        # Click Run button
        await run_button.click()
        self.log("workflow_execution", "Clicked Run button", "info")
        await asyncio.sleep(1)
        await self.take_screenshot(page, "06_workflow_started")
        
        return True
    
    async def observe_progress(self, page: Page):
        """Step 5: Observe progress and status transitions"""
        print("\n=== STEP 5: Observe Progress ===")
        
        # Look for progress indicators
        progress_elements = await page.locator("[class*='progress'], [role='progressbar'], [class*='status']").count()
        self.log("workflow_execution", f"Found {progress_elements} progress-related elements", "info")
        
        # Monitor for status changes over 20 seconds
        for i in range(10):
            await asyncio.sleep(2)
            
            # Check for status text
            status_texts = await page.locator("[class*='status'], [class*='state']").all()
            for status in status_texts[:5]:
                if await status.is_visible():
                    text = await status.text_content()
                    if text and text.strip():
                        self.log("workflow_execution", f"Status at {i*2}s: {text.strip()}", "info")
            
            # Check for completion indicators
            if await page.locator("text=/completed|finished|success|done/i").count() > 0:
                self.log("workflow_execution", "Workflow appears completed", "info")
                await self.take_screenshot(page, "07_workflow_completed")
                break
            
            # Check for error indicators
            if await page.locator("text=/failed|error/i").count() > 0:
                self.log("workflow_execution", "Workflow appears to have failed", "high")
                await self.take_screenshot(page, "07_workflow_failed")
                break
        else:
            self.log("workflow_execution", "Workflow still running after 20s", "info")
            await self.take_screenshot(page, "07_workflow_running")
    
    async def interact_with_results(self, page: Page):
        """Step 6-7: Inspect outputs and interact with result controls"""
        print("\n=== STEP 6-7: Results Interaction ===")
        
        # Look for result/output sections
        result_sections = await page.locator("[class*='result'], [class*='output'], [data-testid*='result']").count()
        self.log("results_interaction", f"Found {result_sections} result-related sections", "info")
        
        # Check for visualization elements
        viz_elements = await page.locator("canvas, svg, img[src*='plot'], [class*='chart']").count()
        self.log("results_interaction", f"Found {viz_elements} visualization elements", "info")
        
        # Look for download buttons
        download_buttons = await page.locator("button:has-text('Download'), a[download], button:has-text('Export')").all()
        if download_buttons:
            self.log("results_interaction", f"Found {len(download_buttons)} download controls", "info")
            for btn in download_buttons[:3]:
                text = await btn.text_content()
                is_visible = await btn.is_visible()
                self.log("results_interaction", f"Download option: '{text}' (visible: {is_visible})", "info")
        else:
            self.log("results_interaction", "No download controls found", "medium")
        
        # Look for View/Hide toggles
        toggle_buttons = await page.locator("button:has-text('View'), button:has-text('Hide'), button:has-text('Show')").all()
        if toggle_buttons:
            self.log("results_interaction", f"Found {len(toggle_buttons)} view toggle controls", "info")
        
        # Look for output cards
        cards = await page.locator("[class*='card'], [class*='output-item']").count()
        self.log("results_interaction", f"Found {cards} card-like elements", "info")
        
        # Try clicking a download button if available
        if download_buttons:
            try:
                first_download = download_buttons[0]
                if await first_download.is_visible() and await first_download.is_enabled():
                    await first_download.click()
                    self.log("results_interaction", "Clicked first download button", "info")
                    await asyncio.sleep(1)
            except Exception as e:
                self.log("results_interaction", f"Error clicking download: {str(e)}", "low")
        
        await self.take_screenshot(page, "08_results_final")
    
    async def check_for_issues(self, page: Page):
        """Step 8: Check for confusing labels, missing feedback, errors"""
        print("\n=== STEP 8: Issue Detection ===")
        
        # Check for console errors
        console_errors = []
        page.on("console", lambda msg: console_errors.append(msg.text) if msg.type == "error" else None)
        
        # Check for visible error messages
        error_elements = await page.locator("[class*='error'], [role='alert'], [class*='warning']").all()
        for elem in error_elements:
            if await elem.is_visible():
                text = await elem.text_content()
                self.log("issues", f"Visible error/warning: {text}", "medium")
        
        # Check for broken images
        images = await page.locator("img").all()
        for img in images:
            src = await img.get_attribute("src")
            natural_width = await img.evaluate("img => img.naturalWidth")
            if natural_width == 0:
                self.log("issues", f"Broken image: {src}", "low")
        
        # Check for empty states or dead ends
        body_text = await page.locator("body").text_content()
        if "404" in body_text or "not found" in body_text.lower():
            self.log("issues", "Possible 404 or 'not found' state", "high")
        
        # Check for loading states that never resolve
        loading_elements = await page.locator("[class*='loading'], [class*='spinner']").all()
        for elem in loading_elements:
            if await elem.is_visible():
                self.log("issues", "Persistent loading indicator visible", "medium")
        
        # Check for disabled buttons without explanation
        disabled_buttons = await page.locator("button:disabled").all()
        for btn in disabled_buttons[:5]:
            text = await btn.text_content()
            # Check if there's a tooltip or explanation nearby
            parent = await btn.evaluate_handle("el => el.parentElement")
            parent_text = await parent.evaluate("el => el.textContent")
            if "disabled" not in parent_text.lower() and "cannot" not in parent_text.lower():
                self.log("issues", f"Disabled button '{text}' without clear explanation", "medium")
    
    async def run_review(self):
        """Run the complete UX review"""
        async with async_playwright() as p:
            browser = await p.chromium.launch(headless=True)
            context = await browser.new_context(viewport={"width": 1920, "height": 1080})
            page = await context.new_page()
            
            try:
                await self.review_first_impression(page)
                
                success = await self.test_chat_workflow_request(page)
                if success:
                    await self.examine_response_artifact(page)
                    
                    execution_success = await self.execute_workflow(page)
                    if execution_success:
                        await self.observe_progress(page)
                        await self.interact_with_results(page)
                
                await self.check_for_issues(page)
                
            except Exception as e:
                self.log("issues", f"Critical error during review: {str(e)}", "critical")
            finally:
                await browser.close()
        
        return self.observations
    
    def generate_report(self):
        """Generate the final UX report"""
        print("\n" + "="*80)
        print("BIOMATE UX REVIEW REPORT")
        print("="*80)
        
        # Categorize findings
        critical_issues = []
        high_issues = []
        medium_issues = []
        low_issues = []
        positive_findings = []
        
        for category, entries in self.observations.items():
            for entry in entries:
                severity = entry.get("severity", "info")
                obs = entry["observation"]
                
                if severity == "critical":
                    critical_issues.append((category, obs))
                elif severity == "high":
                    high_issues.append((category, obs))
                elif severity == "medium":
                    medium_issues.append((category, obs))
                elif severity == "low":
                    low_issues.append((category, obs))
                elif "found" in obs.lower() and any(x in obs.lower() for x in ["button", "element", "input"]):
                    positive_findings.append((category, obs))
        
        print("\n## WHAT WORKS WELL")
        print("-" * 80)
        if positive_findings:
            for category, finding in positive_findings[:10]:
                print(f"  • [{category}] {finding}")
        else:
            print("  (Limited positive findings observed)")
        
        print("\n## WHAT IS UNCLEAR/CONFUSING")
        print("-" * 80)
        for category, issue in medium_issues + low_issues:
            print(f"  • [{category}] {issue}")
        
        print("\n## WHAT APPEARS BROKEN OR RISKY")
        print("-" * 80)
        for category, issue in critical_issues + high_issues:
            print(f"  • [{category}] {issue}")
        
        print("\n## UX SEVERITY RANKING")
        print("-" * 80)
        print(f"  CRITICAL: {len(critical_issues)} issues")
        print(f"  HIGH:     {len(high_issues)} issues")
        print(f"  MEDIUM:   {len(medium_issues)} issues")
        print(f"  LOW:      {len(low_issues)} issues")
        
        print("\n## TOP 10 PRIORITIZED UX FIXES")
        print("-" * 80)
        
        all_issues = (
            [(i, "CRITICAL") for i in critical_issues] +
            [(i, "HIGH") for i in high_issues] +
            [(i, "MEDIUM") for i in medium_issues]
        )
        
        for idx, ((category, issue), severity) in enumerate(all_issues[:10], 1):
            print(f"\n{idx}. [{severity}] {issue}")
            print(f"   Category: {category}")
            
            # Add rationale
            if "cannot find" in issue.lower() or "no" in issue.lower():
                print(f"   Rationale: Missing critical UI element blocks user progress")
            elif "disabled" in issue.lower():
                print(f"   Rationale: Unclear affordances frustrate users")
            elif "unclear" in issue.lower() or "no placeholder" in issue.lower():
                print(f"   Rationale: Lack of guidance increases cognitive load")
            elif "timeout" in issue.lower() or "failed" in issue.lower():
                print(f"   Rationale: Functional failures prevent task completion")
            else:
                print(f"   Rationale: Impacts user experience and task flow")
        
        print("\n" + "="*80)
        print("Review complete. Screenshots saved to /tmp/biomate_ux_*.png")
        print("="*80)

async def main():
    reviewer = UXReviewer()
    await reviewer.run_review()
    reviewer.generate_report()

if __name__ == "__main__":
    asyncio.run(main())
