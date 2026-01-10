#!/usr/bin/env python3
"""
Test script for Ollama integration with Qwen3-32B.

Usage:
    python -m galaxy.ai.test_ollama

Or directly:
    python test_ollama.py
"""

import asyncio
import httpx
import sys


OLLAMA_BASE_URL = "http://localhost:11434"


async def check_ollama_running():
    """Check if Ollama server is running."""
    try:
        async with httpx.AsyncClient() as client:
            response = await client.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=5.0)
            if response.status_code == 200:
                return True, response.json()
    except Exception as e:
        return False, str(e)
    return False, "Unknown error"


async def list_models():
    """List available Ollama models."""
    async with httpx.AsyncClient() as client:
        response = await client.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=10.0)
        if response.status_code == 200:
            data = response.json()
            return [m['name'] for m in data.get('models', [])]
    return []


async def test_generation(model: str = "qwen3:32b", prompt: str = "Hello, respond briefly."):
    """Test model generation."""
    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_BASE_URL}/v1/chat/completions",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
            },
            timeout=120.0
        )

        if response.status_code == 200:
            result = response.json()
            return True, result['choices'][0]['message']['content']
        else:
            return False, f"Error {response.status_code}: {response.text}"


async def test_thinking_mode(model: str = "qwen3:32b"):
    """Test Qwen3 thinking mode with /think prefix."""
    prompt = "/think\nWhat is 15 * 17?"

    async with httpx.AsyncClient() as client:
        response = await client.post(
            f"{OLLAMA_BASE_URL}/v1/chat/completions",
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "stream": False,
            },
            timeout=300.0  # Longer timeout for thinking mode
        )

        if response.status_code == 200:
            result = response.json()
            content = result['choices'][0]['message']['content']
            # Check if thinking tags are present
            has_thinking = '<think>' in content or 'think' in content.lower()
            return True, content, has_thinking
        else:
            return False, f"Error {response.status_code}: {response.text}", False


async def main():
    print("=" * 60)
    print("Ollama + Qwen3-32B Integration Test")
    print("=" * 60)

    # 1. Check Ollama server
    print("\n[1] Checking Ollama server...")
    running, info = await check_ollama_running()
    if running:
        print(f"    ✓ Ollama is running at {OLLAMA_BASE_URL}")
    else:
        print(f"    ✗ Ollama not reachable: {info}")
        print("\n    Start Ollama with: ollama serve")
        sys.exit(1)

    # 2. List models
    print("\n[2] Available models:")
    models = await list_models()
    if models:
        for m in models:
            marker = "→" if "qwen3" in m.lower() else " "
            print(f"    {marker} {m}")
    else:
        print("    No models found. Pull qwen3:32b with:")
        print("    ollama pull qwen3:32b")
        sys.exit(1)

    # 3. Check if qwen3:32b is available
    qwen_models = [m for m in models if 'qwen3' in m.lower() and '32b' in m.lower()]
    if not qwen_models:
        print("\n    ⚠ qwen3:32b not found. Pull it with:")
        print("    ollama pull qwen3:32b")

        # Try with first available model
        if models:
            test_model = models[0]
            print(f"\n    Testing with available model: {test_model}")
        else:
            sys.exit(1)
    else:
        test_model = qwen_models[0]

    # 4. Test basic generation
    print(f"\n[3] Testing generation with {test_model}...")
    success, response = await test_generation(test_model)
    if success:
        print(f"    ✓ Response: {response[:100]}...")
    else:
        print(f"    ✗ Failed: {response}")
        sys.exit(1)

    # 5. Test thinking mode (Qwen3 specific)
    if 'qwen3' in test_model.lower():
        print(f"\n[4] Testing /think mode...")
        success, response, has_thinking = await test_thinking_mode(test_model)
        if success:
            print(f"    ✓ Thinking mode {'active' if has_thinking else 'may not be active'}")
            print(f"    Response preview: {response[:200]}...")
        else:
            print(f"    ✗ Failed: {response}")

    # 6. Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    print(f"  Ollama URL:     {OLLAMA_BASE_URL}")
    print(f"  Model:          {test_model}")
    print(f"  Status:         Ready ✓")
    print("\n  Your hybrid router can now use Ollama for local inference.")
    print("=" * 60)


if __name__ == "__main__":
    asyncio.run(main())
