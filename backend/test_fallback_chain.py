#!/usr/bin/env python3
"""
Quick test to verify the LLM fallback chain loads correctly.

Usage:
    export GOOGLE_API_KEY="AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI"
    cd /Users/kky/biomate/backend
    python3 test_fallback_chain.py
"""

import os
import sys

# Set API keys for testing
os.environ['GOOGLE_API_KEY'] = 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI'
os.environ['OPENAI_API_KEY'] = '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'

# Add lib to path
sys.path.insert(0, '/Users/kky/biomate/backend/lib')

print("=" * 60)
print("Testing LLM Fallback Chain Configuration")
print("=" * 60)

# Test 1: Load fallback manager
print("\n1. Loading FallbackChainManager...")
try:
    from galaxy.ai.llm_client_fallback_implementation import FallbackChainManager
    manager = FallbackChainManager()
    print("   ✅ FallbackChainManager loaded successfully")
except Exception as e:
    print(f"   ❌ Failed to load manager: {e}")
    sys.exit(1)

# Test 2: Get provider chain
print("\n2. Getting provider chain...")
try:
    chain = manager.get_provider_chain()
    print(f"   ✅ Found {len(chain)} providers:")
    for i, provider in enumerate(chain, 1):
        available = "✅" if provider.is_available() else "❌"
        print(f"      {i}. {available} {provider.provider}:{provider.model}")
except Exception as e:
    print(f"   ❌ Failed to get chain: {e}")
    sys.exit(1)

# Test 3: Load LLMClient
print("\n3. Loading LLMClient...")
try:
    from galaxy.ai.llm_client import LLMClient
    from galaxy.ai.config import AIConfig

    config = AIConfig({
        'llm_provider': 'gemini',
        'llm_model': 'gemini-3.1-pro-preview'
    })
    client = LLMClient(config)
    print("   ✅ LLMClient initialized successfully")
    print(f"      Primary: {client.provider}:{client.model}")
except Exception as e:
    print(f"   ❌ Failed to load client: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 4: Check fallback manager is attached
print("\n4. Verifying fallback manager...")
try:
    assert hasattr(client, 'fallback_manager'), "fallback_manager not attached to client"
    assert client.fallback_manager is not None, "fallback_manager is None"
    print("   ✅ Fallback manager attached to client")
except AssertionError as e:
    print(f"   ❌ {e}")
    sys.exit(1)

print("\n" + "=" * 60)
print("✅ All tests passed! Fallback chain is ready.")
print("=" * 60)
print("\nExpected priority order:")
for i, provider in enumerate(chain, 1):
    print(f"  {i}. {provider.model}")
print("\nReady to deploy!")
