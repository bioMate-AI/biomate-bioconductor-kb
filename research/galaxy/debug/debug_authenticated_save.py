#!/usr/bin/env python3

import requests
import json
import sys

def create_test_user_and_test_workflow():
    """
    Create a test user and attempt workflow creation to reproduce the exact error
    """
    
    print("🔐 Testing authenticated workflow creation...")
    
    base_url = "http://localhost:8080"
    
    # Step 1: Create a test user (this might require admin API key)
    print("\n1️⃣ Attempting to create/login test user...")
    
    # First, let's try to get user info
    try:
        user_response = requests.get(f"{base_url}/api/users/current")
        print(f"Current user status: {user_response.status_code}")
        
        if user_response.status_code == 200:
            user_info = user_response.json()
            print(f"Logged in as: {user_info.get('username', 'Unknown')}")
        else:
            print("Not logged in - workflow creation will be preview only")
        
    except Exception as e:
        print(f"Could not check user status: {e}")
    
    # Step 2: Try to create workflow with various scenarios that might cause the error
    print("\n2️⃣ Testing specific workflow scenarios...")
    
    # Test case that might reproduce the workflow_input_0 error
    problematic_request = {
        "request_text": "I need a workflow that processes paired-end RNA-seq data with quality control and alignment", 
        "context": {
            "available_datasets": [
                {"name": "sample_R1.fastq", "format": "fastqsanger"},
                {"name": "sample_R2.fastq", "format": "fastqsanger"}, 
                {"name": "reference.fasta", "format": "fasta"}
            ],
            "constraints": {
                "max_runtime": "4 hours"
            }
        }
    }
    
    print("Testing problematic workflow creation scenario...")
    
    try:
        # Try the create_workflow endpoint that saves workflows (not just preview)
        create_response = requests.post(
            f"{base_url}/api/ai_assistant/create_workflow",
            json=problematic_request,
            headers={"Content-Type": "application/json"},
            timeout=120  # Longer timeout
        )
        
        print(f"Create workflow status: {create_response.status_code}")
        
        if create_response.status_code == 200:
            result = create_response.json()
            print(f"✅ Success: {result.get('message', 'No message')}")
            print(f"Status: {result.get('status', 'N/A')}")
            print(f"Workflow ID: {result.get('workflow_id', 'N/A')}")
            
            # If it's a preview, try to see if we can trigger the save error
            if result.get('status') == 'preview_success':
                print("Got preview - this might be the issue. Real save would happen with authentication.")
                
        else:
            result = create_response.json()
            print(f"❌ Error: {result}")
            
            # Check for the specific workflow_input_ error
            error_msg = str(result.get('error', result.get('detail', '')))
            if 'workflow_input_' in error_msg:
                print(f"🔴 FOUND THE ERROR: {error_msg}")
                
                # Extract the specific step ID
                import re
                markers = re.findall(r'workflow_input_(\d+)', error_msg)
                if markers:
                    print(f"🔴 Problematic markers found: {markers}")
                
                # Look for the full error details
                if 'error_details' in result:
                    print(f"🔴 Full error details: {result['error_details']}")
                
                return False
        
    except requests.exceptions.Timeout:
        print("❌ Request timed out - this might indicate a processing error")
        return False
    except Exception as e:
        print(f"❌ Request failed: {e}")
        return False
    
    # Step 3: Test with different API endpoints
    print("\n3️⃣ Testing two-stage enhanced workflow (more likely to cause the error)...")
    
    try:
        enhanced_response = requests.post(
            f"{base_url}/api/ai_assistant/two_stage_workflow?stage=enhanced",
            json=problematic_request,
            timeout=120
        )
        
        print(f"Enhanced workflow status: {enhanced_response.status_code}")
        
        if enhanced_response.status_code == 200:
            enhanced_result = enhanced_response.json()
            print(f"✅ Enhanced success: {enhanced_result.get('status')}")
        else:
            enhanced_result = enhanced_response.json()
            print(f"❌ Enhanced error: {enhanced_result}")
            
            error_msg = str(enhanced_result.get('error', ''))
            if 'workflow_input_' in error_msg:
                print(f"🔴 FOUND ENHANCED ERROR: {error_msg}")
                return False
        
    except Exception as e:
        print(f"Enhanced workflow test failed: {e}")
    
    # Step 4: Try with a simple workflow that might have step 0 as input
    print("\n4️⃣ Testing simple workflow that might have step 0 issue...")
    
    simple_request = {
        "request_text": "Run FastQC on my sequencing data",
        "context": {
            "available_datasets": [{"name": "reads.fastq", "format": "fastqsanger"}]
        }
    }
    
    try:
        simple_response = requests.post(
            f"{base_url}/api/ai_assistant/create_workflow",
            json=simple_request,
            timeout=60
        )
        
        print(f"Simple workflow status: {simple_response.status_code}")
        
        if simple_response.status_code != 200:
            simple_result = simple_response.json()
            error_msg = str(simple_result.get('error', ''))
            if 'workflow_input_' in error_msg:
                print(f"🔴 FOUND SIMPLE WORKFLOW ERROR: {error_msg}")
                return False
        
    except Exception as e:
        print(f"Simple workflow test failed: {e}")
    
    print("\n✅ No workflow_input_ errors found in current tests")
    print("🤔 The error might occur under specific conditions:")
    print("   - Specific user authentication state")
    print("   - Specific RAG workflow structures")
    print("   - Specific timing or caching issues")
    
    return True

if __name__ == "__main__":
    print("🧪 Debug Authenticated Workflow Save")
    print("="*50)
    
    success = create_test_user_and_test_workflow()
    
    if not success:
        print(f"\n🎯 REPRODUCED THE ERROR - workflow_input_ issue found!")
        sys.exit(1)
    else:
        print(f"\n🤷 Could not reproduce the error in current test")
        print(f"    The issue might require specific conditions to trigger")
        sys.exit(0)