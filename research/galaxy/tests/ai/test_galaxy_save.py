#!/usr/bin/env python3

import requests
import json
import sys

def test_galaxy_workflow_save():
    """
    Test the actual Galaxy workflow save to see what's happening
    """
    
    print("🧪 Testing Galaxy workflow save through AI assistant...")
    
    # Test the actual API that's failing
    base_url = "http://localhost:8080"
    
    test_request = {
        "request_text": "I want to perform quality control analysis on my RNA-seq data using FastQC",
        "context": {}
    }
    
    try:
        print(f"\n1️⃣ Calling AI assistant create_workflow API...")
        response = requests.post(
            f"{base_url}/api/ai_assistant/create_workflow",
            json=test_request,
            timeout=30
        )
        
        print(f"Status Code: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            print(f"✅ Success: {result.get('message', 'No message')}")
            print(f"Workflow ID: {result.get('workflow_id', 'N/A')}")
            print(f"Status: {result.get('status', 'N/A')}")
        else:
            result = response.json()
            print(f"❌ Error Response:")
            print(json.dumps(result, indent=2))
            
            # Look for the specific error details
            if 'error' in result:
                error_msg = result['error']
                if 'workflow_input_' in error_msg:
                    print(f"\n🔴 Found workflow_input_ error: {error_msg}")
                    
                    # Extract the step ID
                    import re
                    match = re.search(r'workflow_input_(\d+)', error_msg)
                    if match:
                        problematic_step = match.group(1)
                        print(f"🔴 Problematic step ID: {problematic_step}")
            
            if 'error_details' in result:
                print(f"Error details: {result['error_details']}")
        
        print(f"\n2️⃣ Testing simple workflow API as alternative...")
        simple_response = requests.post(
            f"{base_url}/api/ai_assistant/simple_workflow",
            json=test_request,
            timeout=30
        )
        
        print(f"Simple API Status Code: {simple_response.status_code}")
        
        if simple_response.status_code == 200:
            simple_result = simple_response.json()
            print(f"✅ Simple API Success: {simple_result.get('message', 'No message')}")
            print(f"Method: {simple_result.get('method', 'N/A')}")
        else:
            simple_result = simple_response.json()
            print(f"❌ Simple API Error: {simple_result}")
        
        return response.status_code == 200
        
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to Galaxy server")
        print("Please make sure Galaxy is running: ./run.sh start")
        return False
    except requests.exceptions.Timeout:
        print("❌ Request timed out")
        return False
    except Exception as e:
        print(f"❌ Unexpected error: {e}")
        return False

if __name__ == "__main__":
    print("🌟 Testing Galaxy AI Assistant Workflow Save")
    print("="*50)
    
    success = test_galaxy_workflow_save()
    
    if success:
        print(f"\n🎉 TEST PASSED - Workflow creation working!")
    else:
        print(f"\n💥 TEST FAILED - Issue still exists")
    
    sys.exit(0 if success else 1)