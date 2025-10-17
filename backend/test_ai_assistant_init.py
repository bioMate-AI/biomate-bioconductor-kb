#!/usr/bin/env python3
"""Test AIAssistant initialization to find which component causes OOM"""

import sys
sys.path.insert(0, 'lib')

import logging
logging.basicConfig(level=logging.INFO)

print("=" * 80)
print("Testing AIAssistant Initialization")
print("=" * 80)

try:
    print("\n1. Loading AIConfig...")
    from galaxy.ai.config import AIConfig
    from galaxy.config.ai_config import configure_ai_assistant

    # Load config
    print("\n2. Configuring AI Assistant...")
    config_dict = {
        'enable_ai_assistant': True,
        'ai_llm_provider': 'openai',
        'ai_llm_model': 'gpt-5-2025-08-07',
        'ai_llm_api_key': 'sk-proj-test'
    }
    ai_config = configure_ai_assistant(config_dict, 'config')
    print(f"   Config loaded: {ai_config}")

    print("\n3. Creating AIAssistant instance (without galaxy_app)...")
    from galaxy.ai.ai_assistant import AIAssistant

    print("   Starting initialization...")
    assistant = AIAssistant(ai_config, galaxy_app=None)
    print("   ✅ AIAssistant initialized successfully!")

    print(f"\n4. Checking components:")
    print(f"   - workflow_search: {assistant.workflow_search}")
    print(f"   - constrained_generator: {assistant.constrained_generator}")
    print(f"   - dataset_selector: {assistant.dataset_selector}")
    print(f"   - dataset_rag: {assistant.dataset_rag}")

    print("\n✅ ALL TESTS PASSED! AIAssistant can be initialized without OOM.")

except Exception as e:
    print(f"\n❌ ERROR during initialization: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)
