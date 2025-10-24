#!/usr/bin/env python3
"""Debug script to inspect message content"""

from playwright.sync_api import sync_playwright
import time
import json

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False, slow_mo=500)
    context = browser.new_context()
    page = context.new_page()

    print("Opening page and clearing storage...")
    page.goto("http://localhost:5173")
    page.wait_for_load_state("networkidle")
    page.evaluate("localStorage.clear(); sessionStorage.clear();")
    page.reload()
    page.wait_for_load_state("networkidle")
    time.sleep(2)

    print("\nSending message...")
    page.locator('[data-testid="chat-input"]').fill("DIA-LCMS proteomics analysis")
    page.locator('[data-testid="chat-send-button"]').click()
    time.sleep(2)

    print("Waiting for AI response...")
    try:
        page.wait_for_function(
            "document.querySelectorAll('[data-testid^=\"chat-message-\"]').length >= 2",
            timeout=45000
        )
        time.sleep(2)
    except:
        print("Timeout waiting for response")

    print("\n" + "="*80)
    print("Inspecting page content...")
    print("="*80)

    # Check all messages
    messages = page.locator('[data-testid^="chat-message-"]').all()
    print(f"\nFound {len(messages)} messages")

    for i, msg in enumerate(messages):
        print(f"\nMessage {i+1}:")
        inner_text = msg.inner_text()[:200]
        print(f"  Text preview: {inner_text}")

    # Check for workflow card
    workflow_cards = page.locator('[data-testid="workflow-generated-message"]').all()
    print(f"\nWorkflow cards found: {len(workflow_cards)}")

    # Check localStorage
    print("\n" + "="*80)
    print("Checking localStorage...")
    print("="*80)
    storage = page.evaluate("() => { return JSON.stringify(localStorage) }")
    storage_obj = json.loads(storage)
    print(f"localStorage keys: {list(storage_obj.keys())}")

    if 'chat-sessions' in storage_obj:
        sessions = json.loads(storage_obj['chat-sessions'])
        print(f"\nNumber of sessions: {len(sessions)}")
        if sessions:
            latest = sessions[0]
            print(f"Latest session ID: {latest.get('id', 'N/A')}")
            print(f"Number of messages: {len(latest.get('messages', []))}")

            # Check last message metadata
            if latest.get('messages'):
                last_msg = latest['messages'][-1]
                print(f"\nLast message:")
                print(f"  Role: {last_msg.get('role', 'N/A')}")
                print(f"  Content: {last_msg.get('content', 'N/A')[:100]}")
                print(f"  Has metadata: {bool(last_msg.get('metadata'))}")
                if last_msg.get('metadata'):
                    print(f"  Metadata type: {last_msg['metadata'].get('type', 'N/A')}")
                    print(f"  Has workflow: {bool(last_msg['metadata'].get('workflow'))}")

    time.sleep(5)
    browser.close()
