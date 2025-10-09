#!/usr/bin/env python3
"""
Simple test script to verify AI Assistant integration
"""

import requests
import json
import sys

def test_ai_status():
    """Test AI Assistant status endpoint"""
    try:
        response = requests.get("http://localhost:8080/api/ai_assistant/status")
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("AI Assistant Status:")
            print(json.dumps(data, indent=2))
            return True
        elif response.status_code == 404:
            print("❌ AI Assistant API not found - routes may not be registered")
            return False
        elif response.status_code == 503:
            print("⚠️  AI Assistant service unavailable - check configuration")
            print(response.text)
            return False
        else:
            print(f"❌ Unexpected status code: {response.status_code}")
            print(response.text)
            return False
            
    except requests.exceptions.ConnectionError:
        print("❌ Could not connect to Galaxy server at http://localhost:8080")
        print("Make sure Galaxy is running!")
        return False
    except Exception as e:
        print(f"❌ Error testing AI status: {e}")
        return False

def test_ai_process_request():
    """Test AI Assistant request processing"""
    try:
        request_data = {
            "request_text": "I want to analyze RNA-seq data for differential expression",
            "context": {},
            "available_datasets": [],
            "preferred_tools": None,
            "constraints": {}
        }
        
        response = requests.post(
            "http://localhost:8080/api/ai_assistant/process_request",
            json=request_data,
            headers={"Content-Type": "application/json"}
        )
        
        print(f"Process Request Status Code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("AI Response:")
            print(json.dumps(data, indent=2))
            return True
        else:
            print(f"❌ Failed to process request: {response.status_code}")
            print(response.text)
            return False
            
    except Exception as e:
        print(f"❌ Error testing AI request processing: {e}")
        return False

def test_frontend_config():
    """Test if AI config is available to frontend"""
    try:
        # Check if configuration endpoint includes AI settings
        response = requests.get("http://localhost:8080/api/configuration")
        
        if response.status_code == 200:
            config = response.json()
            ai_enabled = config.get("enable_ai_assistant", False)
            ai_available = config.get("ai_assistant_available", False)
            
            print(f"Frontend Config - AI Enabled: {ai_enabled}")
            print(f"Frontend Config - AI Available: {ai_available}")
            
            if ai_enabled:
                print("✅ AI Assistant is enabled in configuration")
                return True
            else:
                print("⚠️  AI Assistant not enabled in configuration")
                print("Add 'enable_ai_assistant: true' to your galaxy.yml")
                return False
        else:
            print(f"❌ Could not get configuration: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Error checking frontend config: {e}")
        return False

def main():
    """Run all tests"""
    print("🧪 Testing Galaxy AI Assistant Integration")
    print("=" * 50)
    
    tests = [
        ("AI Status Endpoint", test_ai_status),
        ("Frontend Configuration", test_frontend_config),
        ("AI Request Processing", test_ai_process_request),
    ]
    
    results = []
    for test_name, test_func in tests:
        print(f"\n📋 Testing: {test_name}")
        print("-" * 30)
        result = test_func()
        results.append((test_name, result))
        print()
    
    print("📊 Test Results Summary:")
    print("=" * 50)
    
    all_passed = True
    for test_name, passed in results:
        status = "✅ PASS" if passed else "❌ FAIL"
        print(f"{status} - {test_name}")
        if not passed:
            all_passed = False
    
    print()
    if all_passed:
        print("🎉 All tests passed! AI Assistant integration is working.")
    else:
        print("⚠️  Some tests failed. Check configuration and API endpoints.")
        print("\nTroubleshooting:")
        print("1. Make sure Galaxy is running on http://localhost:8080")
        print("2. Add these to your galaxy.yml:")
        print("   enable_ai_assistant: true")
        print("   ai_api_key: 'your-openai-api-key'")
        print("3. Restart Galaxy after configuration changes")
    
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())