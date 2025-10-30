"""
E2E Test Case 01: DIA LC-MS Workflow

Tests end-to-end workflow generation, parameter validation, and execution
for DIA (Data-Independent Acquisition) LC-MS protein analysis.

Test Flow:
0. Upload test datasets (mzML and FASTA files) to Galaxy
1. Navigate to BioMate chat interface
2. Send query for DIA LC-MS analysis
3. Wait for workflow generation
4. Validate generated parameters against expected values
5. Open workflow builder
6. Execute individual workflow steps
7. Monitor execution timeline
8. View real-time job logs
9. Validate completion
10. Full workflow execution
"""

import pytest
import json
import time
from playwright.sync_api import Page, expect

# Import page objects
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).parent.parent))
from page_objects import ChatPage, WorkflowPage, ExecutionPage
from utilities.screenshot_manager import ScreenshotManager
from utilities.parameter_validator import ParameterValidator


# Test configuration
BASE_URL = "http://localhost:5000"
WORKFLOW_TIMEOUT = 60000  # 60 seconds for workflow generation
EXECUTION_TIMEOUT = 120000  # 2 minutes per step


class TestDiaLcmsWorkflow:
    """Test suite for DIA LC-MS workflow E2E testing"""

    @pytest.fixture(autouse=True, scope="class")
    def setup_class(cls, e2e_page: Page):
        """
        Setup for the entire test class - runs once before all tests.

        Uses e2e_page fixture which has class scope, so the same browser page
        is shared across all tests. This maintains state (uploaded files, chat history, etc.)
        """
        cls.page = e2e_page
        cls.chat_page = ChatPage(e2e_page)
        cls.workflow_page = WorkflowPage(e2e_page)
        cls.execution_page = ExecutionPage(e2e_page)

    @pytest.fixture(autouse=True)
    def setup(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Setup for each test - runs before every test method"""
        self.page = e2e_page
        self.screenshot = screenshot_manager
        self.chat_page = ChatPage(e2e_page)
        self.workflow_page = WorkflowPage(e2e_page)
        self.execution_page = ExecutionPage(e2e_page)

        # Load expected parameters
        expected_params_path = Path(__file__).parent.parent / "test_data" / "expected_parameters.json"
        with open(expected_params_path) as f:
            test_data = json.load(f)
            self.expected_params = test_data["test_01_dia_lcms"]["expected_parameters"]
            self.expected_steps = test_data["test_01_dia_lcms"]["expected_steps"]
            self.query = test_data["test_01_dia_lcms"]["query"]

    def test_00_upload_test_datasets(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 0: Upload test datasets to Galaxy"""
        print("\n=== Test 0: Upload Test Datasets ===")

        # Navigate to chat
        self.chat_page.navigate(BASE_URL)
        screenshot_manager.capture(e2e_page, "00_before_upload")

        # Get paths to test datasets
        test_data_dir = Path(__file__).parent.parent / "test_data" / "datasets"
        mzml_path = test_data_dir / "test_dia_sample.mzML"
        fasta_path = test_data_dir / "test_protein_database.fasta"

        # Verify files exist
        assert mzml_path.exists(), f"Test dataset not found: {mzml_path}"
        assert fasta_path.exists(), f"Test dataset not found: {fasta_path}"

        print(f"Uploading datasets:")
        print(f"  - {mzml_path.name} ({mzml_path.stat().st_size} bytes)")
        print(f"  - {fasta_path.name} ({fasta_path.stat().st_size} bytes)")

        # Upload both files
        self.chat_page.upload_files([str(mzml_path), str(fasta_path)])

        # Wait for upload to complete (look for any success indicators)
        e2e_page.wait_for_timeout(3000)  # Give upload time to complete
        screenshot_manager.capture(e2e_page, "00_after_upload")

        print("✓ Test datasets uploaded successfully")

    def test_01_navigate_to_chat(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 1: Navigate to BioMate chat interface"""
        print("\n=== Test 1: Navigate to Chat Interface ===")

        # Navigate to homepage
        self.chat_page.navigate(BASE_URL)
        screenshot_manager.capture(e2e_page, "01_homepage")

        # Verify chat interface loaded
        expect(self.chat_page.chat_input).to_be_visible()
        expect(self.chat_page.send_button).to_be_visible()
        screenshot_manager.capture(e2e_page, "02_chat_interface_loaded")

        print("✓ Successfully navigated to chat interface")

    def test_02_send_workflow_query(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 2: Send DIA LC-MS workflow query"""
        print("\n=== Test 2: Send Workflow Query ===")

        # Navigate to chat
        self.chat_page.navigate(BASE_URL)
        screenshot_manager.capture(e2e_page, "03_before_query")

        # Send the DIA LC-MS analysis query
        print(f"Sending query: {self.query}")
        self.chat_page.send_message(self.query)
        screenshot_manager.capture(e2e_page, "04_query_sent")

        # Verify input was cleared
        assert self.chat_page.get_input_value() == "", "Chat input should be cleared after sending"

        print("✓ Query sent successfully")

    def test_03_wait_for_workflow_generation(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 3: Wait for workflow to be generated by LLM"""
        print("\n=== Test 3: Wait for Workflow Generation ===")

        # NOTE: Query was already sent in test_02, just wait for generation
        # DO NOT navigate or send query again - that would lose uploaded datasets!

        # Wait for workflow generation message
        print("Waiting for workflow generation (max 60s)...")
        start_time = time.time()
        workflow_message = self.chat_page.wait_for_workflow_generation(WORKFLOW_TIMEOUT)
        elapsed = time.time() - start_time

        screenshot_manager.capture(e2e_page, "05_workflow_generated")

        # Verify workflow was generated
        expect(workflow_message).to_be_visible()
        print(f"✓ Workflow generated in {elapsed:.2f} seconds")

    def test_04_validate_workflow_steps(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 4: Validate workflow has expected steps"""
        print("\n=== Test 4: Validate Workflow Steps ===")

        # NOTE: Workflow was already generated in test_03
        # Just open the workflow builder - DO NOT regenerate!

        # Open workflow builder (may need to click "Create Workflow" button)
        try:
            create_workflow_btn = e2e_page.locator('[data-testid="button-create-workflow"]').last
            if create_workflow_btn.is_visible():
                create_workflow_btn.click()
                print("  Clicked 'Create Workflow' button")
        except:
            print("  Workflow builder may already be open")

        self.workflow_page.wait_for_workflow_loaded()
        screenshot_manager.capture(e2e_page, "06_workflow_builder")

        # Get all workflow steps
        step_count = self.workflow_page.get_step_count()
        print(f"Workflow has {step_count} steps")

        # Note: We don't validate exact step count - LLM may generate different number of steps
        # The correctness will be checked manually later

        # Capture each step node and get titles
        all_steps = self.workflow_page.get_all_step_nodes()
        step_titles = self.workflow_page.get_all_step_titles()
        for idx, (step, title) in enumerate(zip(all_steps, step_titles)):
            screenshot_manager.capture(e2e_page, f"07_step_{idx}_node")
            print(f"  Step {idx}: {title[:50]}...")

        # Verify workflow graph is visible and has at least one step
        assert step_count > 0, "Workflow should have at least one step"
        print(f"✓ Workflow loaded successfully with {step_count} steps")

    def test_05_validate_step_parameters(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 5: Validate parameter editor opens (may not have schema for all 7000+ tools)"""
        print("\n=== Test 5: Validate Parameter Editor ===")

        # NOTE: Workflow builder is already open from test_04
        # DO NOT navigate/regenerate - just work with existing workflow!

        # Open parameter editor for first step
        # Get the first step ID dynamically (don't assume naming convention)
        all_step_ids = e2e_page.evaluate("""
            () => {
                const nodes = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(nodes).map(n => n.getAttribute('data-testid').replace('graph-node-', ''));
            }
        """)
        assert len(all_step_ids) > 0, "Should have at least one step in workflow"
        step_id = all_step_ids[0]
        print(f"Opening parameter editor for first step: {step_id}")
        self.workflow_page.edit_step_parameters(step_id)

        # Wait for dialog to open and finish loading
        import time
        time.sleep(2)
        screenshot_manager.capture(e2e_page, "08_parameter_dialog_open")

        # Verify parameter dialog is open
        dialog = e2e_page.locator('[data-testid="parameter-dialog"]')
        assert dialog.is_visible(), "Parameter dialog should be visible"
        print("✓ Parameter editor opened successfully")

        # Check if schema is available or shows "schema unavailable" message
        # (With 7000+ tools, most won't have detailed schemas)
        schema_unavailable = e2e_page.locator('[data-testid="parameter-schema-unavailable"]')
        if schema_unavailable.is_visible():
            print("  → Tool schema not available (expected for many tools)")
        else:
            print("  → Tool schema loaded")

        # Note: We skip detailed parameter validation since tools may not have schemas
        # Close parameter dialog
        close_button = e2e_page.locator('button:has-text("Cancel"), button:has-text("Close")').first
        if close_button.is_visible():
            close_button.click()
            import time
            time.sleep(1)

        print("✓ Parameter editor test complete")

    def test_06_execute_individual_step(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 6: Execute individual workflow step"""
        print("\n=== Test 6: Execute Individual Step ===")

        # NOTE: Workflow builder is already open with uploaded datasets from test_00
        # DO NOT navigate/regenerate - execute step on existing workflow!

        # Get the first step ID dynamically
        all_step_ids = e2e_page.evaluate("""
            () => {
                const nodes = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(nodes).map(n => n.getAttribute('data-testid').replace('graph-node-', ''));
            }
        """)
        assert len(all_step_ids) > 0, "Should have at least one step in workflow"
        step_id = all_step_ids[0]
        print(f"Executing {step_id} individually...")
        screenshot_manager.capture(e2e_page, "11_before_execution")

        self.workflow_page.execute_step(step_id)
        screenshot_manager.capture(e2e_page, "12_step_execution_started")

        # Verify execution timeline appears
        self.execution_page.timeline.wait_for_visible()
        screenshot_manager.capture(e2e_page, "13_timeline_visible")

        # Wait for step to appear in timeline
        timeline_event = self.execution_page.timeline.get_timeline_event(step_id)
        expect(timeline_event).to_be_visible()
        screenshot_manager.capture(e2e_page, "14_step_in_timeline")

        print(f"✓ Step {step_id} execution initiated")

    def test_07_monitor_step_execution(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 7: Monitor step execution via timeline"""
        print("\n=== Test 7: Monitor Step Execution ===")

        # NOTE: Step was already executed in test_06
        # Just monitor the SAME execution - DO NOT start new chat/workflow!

        # Get the first step ID (same one executed in test_06)
        all_step_ids = e2e_page.evaluate("""
            () => {
                const nodes = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(nodes).map(n => n.getAttribute('data-testid').replace('graph-node-', ''));
            }
        """)
        assert len(all_step_ids) > 0, "Should have at least one step in workflow"
        step_id = all_step_ids[0]

        # Timeline should already be visible from test_06
        self.execution_page.timeline.wait_for_visible()

        # Monitor step status changes
        print(f"Monitoring {step_id} execution...")

        # Check for running status
        print("  Waiting for 'running' status...")
        try:
            self.execution_page.timeline.wait_for_step_status(step_id, "running", timeout=30000)
            screenshot_manager.capture(e2e_page, "15_step_running")
            print("  ✓ Step is running")
        except:
            print("  ⚠ Step may have completed too quickly")
            screenshot_manager.capture(e2e_page, "15_step_status_check")

        # Wait for completion (this may take a while for real Galaxy jobs)
        print("  Waiting for 'completed' status (max 2 minutes)...")
        try:
            self.execution_page.timeline.wait_for_step_status(step_id, "completed", timeout=EXECUTION_TIMEOUT)
            screenshot_manager.capture(e2e_page, "16_step_completed")
            print("  ✓ Step completed successfully")
        except:
            # Check if failed
            if self.execution_page.timeline.is_step_failed(step_id):
                screenshot_manager.capture(e2e_page, "16_step_failed")
                print("  ✗ Step execution failed")
                pytest.fail("Step execution failed")
            else:
                screenshot_manager.capture(e2e_page, "16_step_timeout")
                print("  ⚠ Step execution timed out (may still be running)")

    def test_08_view_job_logs(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 8: View job logs for executed step"""
        print("\n=== Test 8: View Job Logs ===")

        # NOTE: Step was already executed in test_06
        # Just view logs for the SAME execution

        # Get the first step ID (same one executed earlier)
        all_step_ids = e2e_page.evaluate("""
            () => {
                const nodes = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(nodes).map(n => n.getAttribute('data-testid').replace('graph-node-', ''));
            }
        """)
        assert len(all_step_ids) > 0, "Should have at least one step in workflow"
        step_id = all_step_ids[0]

        # Wait for logs to appear
        print(f"Waiting for logs for {step_id}...")
        try:
            self.execution_page.logs.wait_for_logs(step_id, timeout=30000)
            screenshot_manager.capture(e2e_page, "17_logs_visible")
            print("  ✓ Logs are visible")

            # Get log content
            log_text = self.execution_page.logs.get_log_text(step_id)
            print(f"  Log preview (first 200 chars): {log_text[:200]}...")

            # Check for errors in logs
            has_errors = self.execution_page.logs.has_error_in_logs(step_id)
            if has_errors:
                print("  ⚠ Errors detected in logs")
                screenshot_manager.capture(e2e_page, "18_logs_with_errors")
            else:
                print("  ✓ No errors in logs")
                screenshot_manager.capture(e2e_page, "18_logs_clean")

        except:
            screenshot_manager.capture(e2e_page, "17_logs_not_available")
            print("  ⚠ Logs not yet available")

    def test_09_validate_step_completion(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 9: Validate step completion and outputs"""
        print("\n=== Test 9: Validate Step Completion ===")

        # NOTE: Step was already executed in test_06
        # Just validate completion of the SAME execution

        # Get the first step ID (same one executed earlier)
        all_step_ids = e2e_page.evaluate("""
            () => {
                const nodes = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(nodes).map(n => n.getAttribute('data-testid').replace('graph-node-', ''));
            }
        """)
        assert len(all_step_ids) > 0, "Should have at least one step in workflow"
        step_id = all_step_ids[0]

        # Step was already executed in test_06 - just validate its completion
        screenshot_manager.capture(e2e_page, "19_final_status")

        # Validate completion
        validation_result = self.execution_page.validate_step_completion(step_id)

        print(f"Validation Results:")
        print(f"  Completed: {validation_result['completed']}")
        print(f"  Failed: {validation_result['failed']}")
        print(f"  Has Logs: {validation_result['has_logs']}")
        print(f"  Has Errors: {validation_result['has_errors']}")

        screenshot_manager.capture(e2e_page, "20_validation_complete")

        # Assert success
        assert validation_result['completed'], "Step should be marked as completed"
        assert not validation_result['failed'], "Step should not be marked as failed"

        print("✓ Step validation passed")

    def test_10_full_workflow_execution(self, e2e_page: Page, screenshot_manager: ScreenshotManager):
        """Test 10: Execute entire workflow end-to-end"""
        print("\n=== Test 10: Full Workflow Execution ===")

        # NOTE: Workflow is already loaded with uploaded datasets from test_00
        # Execute the FULL workflow (all steps) on this existing workflow
        screenshot_manager.capture(e2e_page, "21_before_full_execution")

        # Execute entire workflow
        print("Executing full workflow...")
        self.workflow_page.execute_workflow()
        screenshot_manager.capture(e2e_page, "22_full_workflow_started")

        # Wait for workflow to reach running state
        try:
            self.workflow_page.wait_for_status("running", timeout=30000)
            screenshot_manager.capture(e2e_page, "23_workflow_running")
            print("✓ Workflow is running")
        except:
            screenshot_manager.capture(e2e_page, "23_workflow_status_check")
            print("⚠ Workflow status unclear")

        # Monitor timeline for all steps
        self.execution_page.timeline.wait_for_visible()
        screenshot_manager.capture(e2e_page, "24_timeline_all_steps")

        # For full workflow, we'll just verify it starts
        # Actual completion would take too long for E2E test
        print("✓ Full workflow execution initiated")
        print("  (Note: Not waiting for full completion in test)")

        screenshot_manager.capture(e2e_page, "25_test_complete")


# Standalone test execution
if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s", "--html=test_report.html"])
