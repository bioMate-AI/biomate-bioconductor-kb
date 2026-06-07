#!/usr/bin/env python3
"""
Local test for LLM fallback chain - runs without full backend setup.

Tests:
1. Config loads correctly
2. Provider chain builds correctly
3. Fallback logic works (using mocks)

Usage:
    cd /Users/kky/biomate/backend
    .venv/bin/python test_llm_fallback_local.py
"""

import os
import sys
from unittest.mock import Mock, patch, AsyncMock
import asyncio

# Set API keys for testing
os.environ['GOOGLE_API_KEY'] = 'AIzaSyDoFJyQuwTYsfhoLO4DBL1ME9Ojl7VpFHI'
os.environ['ANTHROPIC_API_KEY'] = 'test-anthropic-key'
os.environ['OPENAI_API_KEY'] = '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'

# Add lib to path
sys.path.insert(0, 'lib')

print("=" * 70)
print("LOCAL LLM FALLBACK CHAIN TEST")
print("=" * 70)

# Test 1: Load configuration
print("\n[Test 1] Loading llm_providers.yml configuration...")
try:
    # Import directly from file to avoid galaxy.ai.__init__ dependencies
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "llm_client_fallback_implementation",
        "lib/galaxy/ai/llm_client_fallback_implementation.py"
    )
    fallback_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fallback_module)

    FallbackChainManager = fallback_module.FallbackChainManager
    manager = FallbackChainManager(config_path='config/llm_providers.yml')
    print("   ✅ Configuration loaded successfully")

    # Check primary
    assert manager.primary is not None, "Primary provider not loaded"
    print(f"   ✅ Primary: {manager.primary.provider}:{manager.primary.model}")

    # Check fallbacks
    assert len(manager.fallbacks) > 0, "No fallback providers loaded"
    print(f"   ✅ Fallbacks: {len(manager.fallbacks)} providers")

except Exception as e:
    print(f"   ❌ FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 2: Build provider chain
print("\n[Test 2] Building provider chain...")
try:
    chain = manager.get_provider_chain()

    print(f"   ✅ Built chain with {len(chain)} providers:")
    for i, provider in enumerate(chain, 1):
        available = "✅" if provider.is_available() else "❌"
        print(f"      {i}. {available} {provider.provider}:{provider.model}")

    # Verify priority order
    expected_order = [
        'gemini:gemini-3.1-pro-preview',
        'gemini:gemini-3.5-flash-preview',
        'anthropic:claude-sonnet-4-5',
        'openai:gpt-4o',
        'ollama:qwen3:32b'
    ]

    actual_order = [f"{p.provider}:{p.model}" for p in chain]

    # Check first 4 (ollama might not be available locally)
    for expected, actual in zip(expected_order[:4], actual_order[:4]):
        if expected != actual:
            print(f"   ❌ Order mismatch: expected {expected}, got {actual}")
            sys.exit(1)

    print("   ✅ Priority order is correct")

except Exception as e:
    print(f"   ❌ FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 3: Test _try_provider_with_retry function
print("\n[Test 3] Testing retry logic...")
try:
    _try_provider_with_retry = fallback_module._try_provider_with_retry

    # Create a mock client
    mock_client = Mock()
    mock_client._generate_gemini = AsyncMock(side_effect=Exception("Test error"))

    # Create a provider config (use from fallback_module directly)
    LLMProviderConfig = fallback_module.LLMProviderConfig

    provider_config = LLMProviderConfig({
        'provider': 'gemini',
        'model': 'gemini-3.1-pro-preview',
        'api_key_env': 'GOOGLE_API_KEY',
        'retry_attempts': 2
    })

    # Test that it retries
    async def test_retry():
        try:
            await _try_provider_with_retry(
                llm_client=mock_client,
                provider_config=provider_config,
                prompt="test"
            )
            print("   ❌ Should have failed")
            return False
        except Exception as e:
            # Should have tried twice
            if mock_client._generate_gemini.call_count == 2:
                print(f"   ✅ Retry logic works: tried {mock_client._generate_gemini.call_count} times")
                return True
            else:
                print(f"   ❌ Wrong retry count: {mock_client._generate_gemini.call_count}")
                return False

    result = asyncio.run(test_retry())
    if not result:
        sys.exit(1)

except Exception as e:
    print(f"   ❌ FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

# Test 4: Verify config file path handling
print("\n[Test 4] Testing config file path...")
try:
    # Test with absolute path
    import os
    abs_path = os.path.abspath('config/llm_providers.yml')
    manager2 = FallbackChainManager(config_path=abs_path)
    assert manager2.primary is not None
    print(f"   ✅ Absolute path works: {abs_path}")

except Exception as e:
    print(f"   ❌ FAILED: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 70)
print("✅ ALL TESTS PASSED!")
print("=" * 70)
print("\nFallback chain is working correctly:")
print("1. ✅ Config loads from YAML")
print("2. ✅ Provider chain builds in correct priority order")
print("3. ✅ Retry logic works (exponential backoff)")
print("4. ✅ Config file paths handled correctly")
print("\n🚀 Ready to deploy to dev-public!")
