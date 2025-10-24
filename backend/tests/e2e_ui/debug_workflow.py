#!/usr/bin/env python3
"""
Debug script to see what's happening with workflow generation
"""
import time
from playwright.sync_api import sync_playwright

def debug_workflow():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=1000)
        page = browser.new_page()

        # Listen to console logs
        console_messages = []
        page.on("console", lambda msg: console_messages.append(f"[{msg.type}] {msg.text}"))

        # Listen to network requests
        network_requests = []
        page.on("request", lambda req: network_requests.append(f"→ {req.method} {req.url}"))
        page.on("response", lambda res: network_requests.append(f"← {res.status} {res.url}"))

        # Navigate
        print("1. Navigating to http://localhost:5173")
        page.goto("http://localhost:5173")
        page.wait_for_load_state("networkidle")
        time.sleep(2)

        # Check if chat input exists
        print("2. Looking for chat input...")
        chat_input = page.locator('[data-testid="chat-input"]')
        if chat_input.is_visible():
            print("   ✓ Chat input found")
        else:
            print("   ✗ Chat input NOT found")
            print("   Available test IDs:", page.locator('[data-testid]').all())

        # Send message
        print("3. Sending message...")
        chat_input.fill("Run DIA LC-MS protein analysis")
        send_button = page.locator('[data-testid="chat-send-button"]')
        send_button.click()
        print("   ✓ Message sent")

        # Wait and check messages
        print("4. Waiting for response...")
        time.sleep(35)  # Galaxy backend takes 20-30s to respond

        # Check all messages
        messages = page.locator('[data-testid^="chat-message-"]').all()
        print(f"   Found {len(messages)} messages")

        # Check for workflow message
        print("5. Checking for workflow-generated-message...")
        workflow_msg = page.locator('[data-testid="workflow-generated-message"]')
        if workflow_msg.count() > 0:
            print(f"   ✓ Found {workflow_msg.count()} workflow messages")
        else:
            print("   ✗ NO workflow messages found")

        # Get all data-testids on page
        print("6. All data-testids on page:")
        all_testids = page.evaluate("""
            () => {
                const elements = document.querySelectorAll('[data-testid]');
                return Array.from(elements).map(el => el.getAttribute('data-testid'));
            }
        """)
        for testid in all_testids:
            print(f"   - {testid}")

        # Check console logs
        print("7. Page title:", page.title())
        print("8. Page URL:", page.url)

        print("\n9. Console messages:")
        for msg in console_messages[-20:]:  # Last 20 messages
            print(f"   {msg}")

        print("\n10. Network requests (API calls):")
        for req in network_requests[-20:]:  # Last 20 requests
            if '/api/' in req:
                print(f"   {req}")

        print("\nDone!")

        browser.close()

if __name__ == "__main__":
    debug_workflow()