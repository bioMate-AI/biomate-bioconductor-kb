#!/usr/bin/env python3

import requests
import json
import sys
import time

def test_authenticated_workflow_creation():
    """
    Test workflow creation with authentication to reproduce the actual error
    """
    
    print("🔐 Testing authenticated workflow creation...")
    
    base_url = "http://localhost:8080"
    
    # First, try to get/create an API key for testing
    print("\n1️⃣ Attempting workflow creation with different scenarios...")
    
    # Test different request patterns that might trigger the error
    test_cases = [
        {
            "name": "Simple RNA-seq request",
            "request": {
                "request_text": "I want to analyze RNA-seq data for differential expression",
                "context": {}
            }
        },
        {
            "name": "Complex multi-input request", 
            "request": {
                "request_text": "I need a workflow that takes raw FASTQ files and a reference genome to perform quality control, trimming, alignment, and quantification",
                "context": {
                    "available_datasets": [
                        {"name": "raw_reads.fastq", "format": "fastqsanger"},
                        {"name": "genome.fasta", "format": "fasta"}
                    ]
                }
            }
        },
        {
            "name": "Workflow with specific tools",
            "request": {
                "request_text": "Create a workflow using FastQC, Trim Galore, HISAT2, and featureCounts",
                "context": {
                    "preferred_tools": ["fastqc", "trim_galore", "hisat2", "featurecounts"]
                }
            }
        }
    ]
    
    for i, test_case in enumerate(test_cases, 1):
        print(f"\n{i}️⃣ Testing: {test_case['name']}")
        
        try:
            response = requests.post(
                f"{base_url}/api/ai_assistant/create_workflow",
                json=test_case['request'],
                timeout=60  # Longer timeout for complex requests
            )
            
            print(f"   Status: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                status = result.get('status', 'unknown')
                print(f"   ✅ Success - Status: {status}")
                
                if 'workflow_id' in result:
                    print(f"   Workflow ID: {result['workflow_id']}")
                if 'message' in result:
                    print(f"   Message: {result['message']}")
                    
            else:
                result = response.json()
                print(f"   ❌ Error - Status: {response.status_code}")
                
                # Look for workflow_input_ errors
                error_msg = result.get('error', result.get('detail', ''))
                if 'workflow_input_' in error_msg:
                    print(f"   🔴 Found workflow_input_ error: {error_msg}")
                    
                    # Extract problematic connections
                    import re
                    markers = re.findall(r'workflow_input_(\d+)', error_msg)
                    if markers:
                        print(f"   🔴 Problematic markers: {markers}")
                
                # Print full error details if available
                if 'error_details' in result:
                    print(f"   Error details: {result['error_details']}")
                    
        except requests.exceptions.Timeout:
            print(f"   ⏰ Request timed out after 60 seconds")
        except requests.exceptions.ConnectionError:
            print(f"   🔌 Connection error - Galaxy server may not be running")
            return False
        except Exception as e:
            print(f"   💥 Unexpected error: {e}")
    
    # Test the two-stage API as well
    print(f"\n🔄 Testing two-stage API...")
    
    try:
        # Stage 1: Similar workflows
        stage1_response = requests.post(
            f"{base_url}/api/ai_assistant/two_stage_workflow?stage=similar",
            json={
                "request_text": "RNA-seq differential expression analysis",
                "context": {}
            },
            timeout=30
        )
        
        print(f"   Stage 1 Status: {stage1_response.status_code}")
        
        if stage1_response.status_code == 200:
            stage1_data = stage1_response.json()
            print(f"   ✅ Stage 1 Success - Found {len(stage1_data.get('recommendations', []))} recommendations")
        else:
            print(f"   ❌ Stage 1 Error: {stage1_response.text}")
        
        # Stage 2: Enhanced workflow
        stage2_response = requests.post(
            f"{base_url}/api/ai_assistant/two_stage_workflow?stage=enhanced",
            json={
                "request_text": "RNA-seq differential expression analysis",
                "context": {}
            },
            timeout=60
        )
        
        print(f"   Stage 2 Status: {stage2_response.status_code}")
        
        if stage2_response.status_code == 200:
            stage2_data = stage2_response.json()
            print(f"   ✅ Stage 2 Success - Status: {stage2_data.get('status')}")
        else:
            stage2_result = stage2_response.json()
            print(f"   ❌ Stage 2 Error: {stage2_result}")
            
            # Check for workflow_input_ errors in stage 2
            error_msg = stage2_result.get('error', stage2_result.get('detail', ''))
            if 'workflow_input_' in error_msg:
                print(f"   🔴 Stage 2 workflow_input_ error: {error_msg}")
        
    except Exception as e:
        print(f"   💥 Two-stage API error: {e}")
    
    print(f"\n🏁 Test completed")
    return True

def main():
    print("🌟 Comprehensive Galaxy AI Assistant Test")
    print("="*60)
    
    success = test_authenticated_workflow_creation()
    
    if success:
        print(f"\n🎯 Tests completed - Check output above for any workflow_input_ errors")
    else:
        print(f"\n💥 Tests failed to run properly")
    
    return 0

if __name__ == "__main__":
    sys.exit(main())