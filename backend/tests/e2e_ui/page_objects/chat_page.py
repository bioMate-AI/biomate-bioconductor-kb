"""
Chat Page Object

Encapsulates all interactions with the chat interface for E2E testing.
Provides clean, reusable methods for sending messages and waiting for responses.
"""

from playwright.sync_api import Page, expect


class ChatPage:
    """Page object for BioMate chat interface"""

    def __init__(self, page: Page):
        self.page = page

        # Locators using test IDs
        self.chat_input = page.locator('[data-testid="chat-input"]')
        self.send_button = page.locator('[data-testid="chat-send-button"]')
        self.workflow_button = page.locator('[data-testid="button-create-workflow"]').last
        self.chat_messages = page.locator('[data-testid^="chat-message-"]')
        self.new_chat_button = page.locator('[data-testid="button-new-chat"]')

    def navigate(self, base_url: str = "http://localhost:3000"):
        """Navigate to chat interface"""
        self.page.goto(base_url)
        self.page.wait_for_load_state("networkidle")

    def start_new_chat(self):
        """
        Start a new chat session by clicking the New Chat button.
        This ensures test isolation by clearing the current chat/workflow context.
        """
        self.new_chat_button.click()
        self.page.wait_for_timeout(500)  # Brief wait for UI to update

    def send_message(self, message: str):
        """
        Send a chat message

        Args:
            message: The text message to send
        """
        self.chat_input.fill(message)
        self.send_button.click()

    def wait_for_workflow_generation(self, timeout: int = 60000):
        """
        Wait for workflow to be generated and displayed

        Args:
            timeout: Maximum wait time in milliseconds (default 60s)

        Returns:
            The workflow button element
        """
        self.workflow_button.wait_for(state="visible", timeout=timeout)
        return self.workflow_button

    def load_workflow_to_builder(self):
        """
        Click the "Create Workflow" button to load the generated workflow into the builder.
        This should be called after wait_for_workflow_generation().
        """
        # Wait a bit longer to ensure message metadata is fully saved
        self.page.wait_for_timeout(2000)

        # Log what we're clicking for debugging
        button_count = self.page.locator('[data-testid="button-create-workflow"]').count()
        print(f"  Found {button_count} 'Create Workflow' buttons, clicking the last one")

        self.workflow_button.click()

        # Wait for workflow to load in builder
        self.page.wait_for_timeout(2000)

    def get_latest_message(self):
        """Get the most recent chat message"""
        messages = self.chat_messages.all()
        return messages[-1] if messages else None

    def get_all_messages(self):
        """Get all chat messages"""
        return self.chat_messages.all()

    def wait_for_response(self, timeout: int = 30000):
        """
        Wait for any new response message

        Args:
            timeout: Maximum wait time in milliseconds (default 30s)
        """
        initial_count = self.chat_messages.count()
        self.page.wait_for_function(
            f"document.querySelectorAll('[data-testid^=\"chat-message-\"]').length > {initial_count}",
            timeout=timeout
        )

    def is_workflow_generated(self) -> bool:
        """Check if workflow has been generated"""
        return self.workflow_button.is_visible()

    def clear_input(self):
        """Clear the chat input field"""
        self.chat_input.clear()

    def get_input_value(self) -> str:
        """Get current value of chat input"""
        return self.chat_input.input_value()

    def upload_file(self, file_path: str):
        """
        Upload a file via the chat interface

        Args:
            file_path: Absolute path to the file to upload
        """
        # Use data-testid selector for file input
        file_input = self.page.locator('[data-testid="file-upload-input"]')
        file_input.set_input_files(file_path)

    def upload_files(self, file_paths: list[str]):
        """
        Upload multiple files via the chat interface

        Args:
            file_paths: List of absolute paths to files to upload
        """
        # Use data-testid selector for file input
        file_input = self.page.locator('[data-testid="file-upload-input"]')
        file_input.set_input_files(file_paths)
