#!/usr/bin/env python3
"""
Debug script to check actual step IDs in workflow graph
"""
import time
from playwright.sync_api import sync_playwright

def debug_step_ids():
    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False, slow_mo=500)
        page = browser.new_page()

        # Navigate
        print("1. Navigating to http://localhost:5173")
        page.goto("http://localhost:5173")
        page.wait_for_load_state("networkidle")
        time.sleep(2)

        # Send message
        print("2. Sending message...")
        chat_input = page.locator('[data-testid="chat-input"]')
        chat_input.fill("Analyze DIA LC-MS data for protein identification and quantification")
        send_button = page.locator('[data-testid="chat-send-button"]')
        send_button.click()
        print("   ✓ Message sent")

        # Wait for response
        print("3. Waiting for workflow generation (35s)...")
        time.sleep(35)

        # Get all graph node testids
        print("4. Finding all graph-node test IDs...")
        all_testids = page.evaluate("""
            () => {
                const elements = document.querySelectorAll('[data-testid^="graph-node-"]');
                return Array.from(elements).map(el => ({
                    testid: el.getAttribute('data-testid'),
                    tag: el.tagName
                }));
            }
        """)

        print(f"\\nFound {len(all_testids)} graph nodes:")
        for item in all_testids:
            print(f"  - {item['testid']} ({item['tag']})")

        # Try clicking first node
        if all_testids:
            first_node_id = all_testids[0]['testid'].replace('graph-node-', '')
            print(f"\\n5. Trying to click node: {first_node_id}")
            try:
                node = page.locator(f'[data-testid="graph-node-{first_node_id}"]')
                node.click()
                time.sleep(1)
                print("   ✓ Node clicked (should now show edit button)")

                # Check if edit button appears
                edit_button = page.locator(f'[data-testid="button-graph-edit-{first_node_id}"]')
                if edit_button.is_visible():
                    print(f"   ✓ Edit button visible: button-graph-edit-{first_node_id}")
                else:
                    print(f"   ✗ Edit button NOT visible")

                    # Check all button testids
                    all_buttons = page.evaluate("""
                        () => {
                            const buttons = document.querySelectorAll('[data-testid^="button-graph-"]');
                            return Array.from(buttons).map(b => b.getAttribute('data-testid'));
                        }
                    """)
                    print(f"\\n   Available button testids:")
                    for btn in all_buttons:
                        print(f"     - {btn}")
            except Exception as e:
                print(f"   ✗ Error: {e}")

        print("\\nDone! Press Ctrl+C to close...")
        time.sleep(30)
        browser.close()

if __name__ == "__main__":
    debug_step_ids()
