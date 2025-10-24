#!/usr/bin/env python3
"""
Manual test to verify chat session auto-creation fix

This script opens a browser to test the fix for the chat session bug.
It verifies that:
1. Chat works without pre-existing session
2. Messages are displayed correctly
3. Workflow generation appears
"""

from playwright.sync_api import sync_playwright
import time

def test_chat_session_creation():
    print("="*80)
    print("Manual Test: Chat Session Auto-Creation")
    print("="*80)

    with sync_playwright() as p:
        # Launch browser (visible)
        browser = p.chromium.launch(headless=False, slow_mo=500)
        context = browser.new_context(
            viewport={"width": 1920, "height": 1080}
        )

        # Clear storage to simulate fresh environment
        context.clear_cookies()

        page = context.new_page()

        print("\n1. Navigating to http://localhost:5173")
        page.goto("http://localhost:5173")
        page.wait_for_load_state("networkidle")
        time.sleep(2)

        # Clear localStorage via JavaScript
        print("2. Clearing localStorage (simulating fresh user)")
        page.evaluate("localStorage.clear()")
        page.reload()
        page.wait_for_load_state("networkidle")
        time.sleep(1)

        print("3. Looking for chat input...")
        chat_input = page.locator('[data-testid="chat-input"]')
        if not chat_input.is_visible():
            print("   ❌ Chat input not visible!")
            browser.close()
            return False
        print("   ✅ Chat input visible")

        print("4. Typing message: 'DIA-LCMS proteomics analysis'")
        chat_input.fill("DIA-LCMS proteomics analysis")
        time.sleep(1)

        print("5. Clicking send button...")
        send_button = page.locator('[data-testid="chat-send-button"]')
        send_button.click()
        time.sleep(2)

        print("6. Checking if user message appears...")
        user_messages = page.locator('[data-testid^="chat-message-"]').all()
        print(f"   Found {len(user_messages)} chat message(s)")

        if len(user_messages) == 0:
            print("   ❌ User message not displayed!")
            print("   This means the auto-session creation didn't work")
            browser.close()
            return False
        print("   ✅ User message displayed")

        print("\n7. Waiting for AI response (max 40 seconds)...")
        print("   (Backend takes ~20-30s to generate workflow)")

        try:
            # Wait for any AI message to appear
            page.wait_for_function(
                "document.querySelectorAll('[data-testid^=\"chat-message-\"]').length > 1",
                timeout=40000
            )

            messages_after = page.locator('[data-testid^="chat-message-"]').all()
            print(f"   ✅ AI response appeared! Total messages: {len(messages_after)}")

            # Check for workflow card
            print("\n8. Checking for workflow card...")
            workflow_card = page.locator('[data-testid="workflow-generated-message"]')

            if workflow_card.is_visible():
                print("   ✅ SUCCESS! Workflow card is visible")
                print("   The fix works correctly!")
                time.sleep(3)  # Keep browser open to see result
                browser.close()
                return True
            else:
                print("   ⚠️  AI response appeared but workflow card not visible")
                print("   This may indicate a metadata issue")
                time.sleep(5)  # Keep browser open to inspect
                browser.close()
                return False

        except Exception as e:
            print(f"   ❌ Timeout waiting for AI response: {e}")
            print("   Backend may not be running or API call failed")
            time.sleep(3)
            browser.close()
            return False

if __name__ == "__main__":
    result = test_chat_session_creation()
    print("\n" + "="*80)
    if result:
        print("✅ TEST PASSED - Chat session auto-creation works!")
    else:
        print("❌ TEST FAILED - Issue remains")
    print("="*80)
