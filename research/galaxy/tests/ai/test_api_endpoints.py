#!/usr/bin/env python3

"""
Test script to verify AI Assistant API endpoints
"""

import requests
import json
import time

def test_api_endpoints():
    """Test AI Assistant API endpoints"""
    
    # Assume Galaxy is running on localhost:8080 (adjust if different)
    base_url = "http://localhost:8080"
    
    print("🔍 Testing AI Assistant API endpoints...")
    print(f"Base URL: {base_url}")
    
    # Test 1: AI Assistant status
    print("\n1️⃣ Testing AI Assistant status...")
    try:
        response = requests.get(f"{base_url}/api/ai_assistant/status", timeout=10)
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ AI Assistant status response:")
            print(json.dumps(data, indent=2))
        else:
            print(f"❌ Error: {response.status_code} - {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Connection error: {e}")
        print("💡 Make sure Galaxy is running on the expected port")
        return False
    
    # Test 2: Enhanced workflow recommendations (quick)
    print("\n2️⃣ Testing enhanced workflow recommendations (quick)...")
    try:
        payload = {
            "request_text": "RNA-seq differential expression analysis",
            "context": {}
        }
        
        response = requests.post(
            f"{base_url}/api/ai_assistant/enhanced_workflow_recommendations?level=quick",
            json=payload,
            timeout=30
        )
        
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ Quick recommendations response:")
            recommendations = data.get('recommendations', [])
            print(f"Found {len(recommendations)} recommendations")
            
            for i, rec in enumerate(recommendations[:3]):
                print(f"  {i+1}. {rec.get('name', 'N/A')} (confidence: {rec.get('confidence', 0):.3f})")
                
        else:
            print(f"❌ Error: {response.status_code} - {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Connection error: {e}")
    
    # Test 3: Enhanced workflow recommendations (enhanced)
    print("\n3️⃣ Testing enhanced workflow recommendations (enhanced)...")
    try:
        response = requests.post(
            f"{base_url}/api/ai_assistant/enhanced_workflow_recommendations?level=enhanced",
            json=payload,
            timeout=30
        )
        
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ Enhanced generation response:")
            print(f"Status: {data.get('status', 'N/A')}")
            
            if data.get('status') == 'success':
                workflow = data.get('workflow', {})
                print(f"Generated workflow: {workflow.get('name', 'N/A')}")
                print(f"Confidence: {data.get('confidence', 0):.3f}")
                print(f"Similar workflows used: {data.get('similar_workflows_count', 0)}")
            else:
                print(f"Error: {data.get('error', 'Unknown error')}")
                
        else:
            print(f"❌ Error: {response.status_code} - {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Connection error: {e}")
    
    # Test 4: Process request (full AI assistant)
    print("\n4️⃣ Testing full AI assistant process request...")
    try:
        response = requests.post(
            f"{base_url}/api/ai_assistant/process_request",
            json=payload,
            timeout=30
        )
        
        print(f"Status code: {response.status_code}")
        
        if response.status_code == 200:
            data = response.json()
            print("✅ Full AI assistant response:")
            print(f"Parsed intent: {data.get('parsed_intent', 'N/A')}")
            print(f"Decomposed tasks: {len(data.get('decomposed_tasks', []))}")
            print(f"Tool recommendations: {len(data.get('tool_recommendations', []))}")
            print(f"Workflow template: {'Yes' if data.get('workflow_template') else 'No'}")
            print(f"Workflow recommendations: {len(data.get('workflow_recommendations', []))}")
            print(f"Confidence: {data.get('confidence', 0):.3f}")
            
        else:
            print(f"❌ Error: {response.status_code} - {response.text}")
            
    except requests.exceptions.RequestException as e:
        print(f"❌ Connection error: {e}")
    
    return True

def check_galaxy_running():
    """Check if Galaxy is running"""
    
    try:
        response = requests.get("http://localhost:8080/api/version", timeout=5)
        if response.status_code == 200:
            print("✅ Galaxy is running")
            return True
        else:
            print(f"❌ Galaxy responded with status {response.status_code}")
            return False
    except requests.exceptions.RequestException:
        print("❌ Galaxy is not running on localhost:8080")
        return False

if __name__ == "__main__":
    print("🚀 Starting API endpoint tests...")
    
    if check_galaxy_running():
        test_api_endpoints()
    else:
        print("\n💡 Please make sure Galaxy is running with:")
        print("   sh run.sh")
        print("   # or")
        print("   python scripts/galaxy-main.py")
    
    print("\n✅ API tests completed!")