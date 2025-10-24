#!/usr/bin/env python3
"""Debug script to capture console messages"""

from playwright.sync_api import sync_playwright
import time

errors = []
logs = []

def handle_console(msg):
    if msg.type == 'error':
        errors.append(f"ERROR: {msg.text}")
    logs.append(f"[{msg.type}] {msg.text}")

with sync_playwright() as p:
    browser = p.chromium.launch(headless=False, slow_mo=500)
    context = browser.new_context()
    page = context.new_page()

    # Capture console messages
    page.on("console", handle_console)

    print("Opening page and clearing storage...")
    page.goto("http://localhost:5173")
    page.wait_for_load_state("networkidle")
    page.evaluate("localStorage.clear(); sessionStorage.clear();")
    page.reload()
    page.wait_for_load_state("networkidle")
    time.sleep(2)

    print("\nSending message...")
    page.locator('[data-testid="chat-input"]').fill("test message")
    page.locator('[data-testid="chat-send-button"]').click()

    print("Waiting 5 seconds for API call...")
    time.sleep(5)

    print("\n" + "="*80)
    print("Console output:")
    print("="*80)
    for log in logs[-20:]:  # Last 20 messages
        print(log)

    if errors:
        print("\n" + "="*80)
        print(f"ERRORS FOUND ({len(errors)}):")
        print("="*80)
        for error in errors:
            print(error)

    time.sleep(3)
    browser.close()
