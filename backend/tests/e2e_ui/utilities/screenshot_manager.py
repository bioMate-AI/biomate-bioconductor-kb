"""
Screenshot Manager for E2E UI Tests

Organizes and captures screenshots during test execution.
Generates HTML snippets for test reports.
"""

import os
from pathlib import Path
from datetime import datetime
from typing import Optional
from playwright.sync_api import Page


class ScreenshotManager:
    """
    Manage screenshot capture and organization for E2E tests.

    Features:
    - Automatic numbering (01_, 02_, etc.)
    - Descriptive filenames
    - HTML report generation
    - Directory organization per test
    """

    def __init__(self, test_name: str, base_dir: Optional[Path] = None):
        """
        Initialize screenshot manager for a test case.

        Args:
            test_name: Name of the test (e.g., "test_01_dia_lcms")
            base_dir: Base directory for screenshots (default: ../test_screenshots)
        """
        self.test_name = test_name
        self.step_counter = 0
        self.screenshots = []

        # Set base directory
        if base_dir is None:
            base_dir = Path(__file__).parent.parent / "test_screenshots"

        # Create test-specific directory
        self.test_dir = base_dir / test_name
        self.test_dir.mkdir(parents=True, exist_ok=True)

        # Timestamp for this test run
        self.timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    def capture(
        self,
        page: Page,
        description: str,
        full_page: bool = False
    ) -> str:
        """
        Capture a screenshot with automatic numbering.

        Args:
            page: Playwright page object
            description: Description of what's being captured
            full_page: Whether to capture full scrollable page

        Returns:
            Filename of captured screenshot

        Example:
            screenshot_manager.capture(page, "chat_input")
            # Creates: 01_chat_input.png
        """
        self.step_counter += 1

        # Create filename
        # Remove special characters and replace spaces with underscores
        clean_description = "".join(
            c if c.isalnum() or c in (' ', '_') else '_'
            for c in description
        ).replace(' ', '_').lower()

        filename = f"{self.step_counter:02d}_{clean_description}.png"
        filepath = self.test_dir / filename

        # Capture screenshot
        page.screenshot(path=str(filepath), full_page=full_page)

        # Record metadata
        self.screenshots.append({
            "step": self.step_counter,
            "description": description,
            "filename": filename,
            "filepath": str(filepath),
            "timestamp": datetime.now().isoformat()
        })

        print(f"[Screenshot {self.step_counter:02d}] {description} → {filename}")

        return filename

    def capture_with_annotation(
        self,
        page: Page,
        description: str,
        annotation: str,
        full_page: bool = False
    ) -> str:
        """
        Capture screenshot with additional annotation.

        Args:
            page: Playwright page object
            description: Description of screenshot
            annotation: Additional context (e.g., "Expected: organism=mouse")
            full_page: Whether to capture full page

        Returns:
            Filename of captured screenshot
        """
        filename = self.capture(page, description, full_page)

        # Update last screenshot with annotation
        if self.screenshots:
            self.screenshots[-1]["annotation"] = annotation

        return filename

    def get_screenshot_count(self) -> int:
        """Get total number of screenshots captured."""
        return self.step_counter

    def get_screenshots(self) -> list:
        """Get list of all captured screenshots with metadata."""
        return self.screenshots.copy()

    def generate_html_snippet(self) -> str:
        """
        Generate HTML snippet for test report.

        Returns:
            HTML string with screenshot gallery
        """
        html = f"""
        <div class="test-screenshots" id="{self.test_name}">
            <h3>Screenshots ({len(self.screenshots)} total)</h3>
            <div class="screenshot-gallery">
        """

        for screenshot in self.screenshots:
            step = screenshot["step"]
            desc = screenshot["description"]
            filename = screenshot["filename"]
            filepath = screenshot["filepath"]
            annotation = screenshot.get("annotation", "")

            html += f"""
                <div class="screenshot-item">
                    <div class="screenshot-header">
                        <span class="step-number">Step {step}</span>
                        <span class="description">{desc}</span>
                    </div>
                    <img src="{filepath}" alt="{desc}" loading="lazy">
                    {f'<div class="annotation">{annotation}</div>' if annotation else ''}
                </div>
            """

        html += """
            </div>
        </div>
        """

        # Save HTML snippet to file
        html_file = self.test_dir / f"{self.test_name}_screenshots.html"
        with open(html_file, 'w') as f:
            f.write(html)

        return html

    def save_metadata(self):
        """Save screenshot metadata to JSON file."""
        import json

        metadata_file = self.test_dir / f"{self.test_name}_metadata.json"
        with open(metadata_file, 'w') as f:
            json.dump({
                "test_name": self.test_name,
                "timestamp": self.timestamp,
                "total_screenshots": len(self.screenshots),
                "screenshots": self.screenshots
            }, f, indent=2)

    def __repr__(self):
        return f"ScreenshotManager(test={self.test_name}, screenshots={self.step_counter})"
