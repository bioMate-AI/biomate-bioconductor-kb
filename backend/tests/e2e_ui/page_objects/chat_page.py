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
        self.workflow_message = page.locator('[data-testid="workflow-generated-message"]')
        self.chat_messages = page.locator('[data-testid^="chat-message-"]')

    def navigate(self, base_url: str = "http://localhost:3000"):
        """Navigate to chat interface"""
        self.page.goto(base_url)
        self.page.wait_for_load_state("networkidle")

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
            The workflow message element
        """
        self.workflow_message.wait_for(state="visible", timeout=timeout)
        return self.workflow_message

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
        return self.workflow_message.is_visible()

    def clear_input(self):
        """Clear the chat input field"""
        self.chat_input.clear()

    def get_input_value(self) -> str:
        """Get current value of chat input"""
        return self.chat_input.input_value()
