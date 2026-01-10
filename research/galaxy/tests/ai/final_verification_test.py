#!/usr/bin/env python3

import requests
import json
import time
import sys

def test_final_fix_verification():
    """
    Final comprehensive test to verify the workflow_input_ fix is working
    """
    
    print("🏁 Final verification test for workflow_input_ fix...")
    
    base_url = "http://localhost:8080"
    
    # Test different scenarios that might trigger the error
    test_scenarios = [
        {
            "name": "Simple RNA-seq",
            "request": {
                "request_text": "Analyze RNA-seq data for differential expression",
                "context": {}
            }
        },
        {
            "name": "Complex multi-sample workflow", 
            "request": {
                "request_text": "Create a comprehensive RNA-seq pipeline that processes paired-end reads, performs quality control, trimming, alignment, and quantification for multiple samples",
                "context": {
                    "available_datasets": [
                        {"name": "sample1_R1.fastq", "format": "fastqsanger"},
                        {"name": "sample1_R2.fastq", "format": "fastqsanger"},
                        {"name": "sample2_R1.fastq", "format": "fastqsanger"},
                        {"name": "sample2_R2.fastq", "format": "fastqsanger"},
                        {"name": "reference.fasta", "format": "fasta"}
                    ],
                    "preferred_tools": ["fastqc", "trim_galore", "hisat2", "stringtie", "featurecounts"],
                    "constraints": {"max_runtime": "8 hours"}
                }
            }
        },
        {
            "name": "Enhanced workflow generation",
            "request": {
                "request_text": "I need a sophisticated bioinformatics workflow for processing genomic data with multiple analysis steps",
                "context": {
                    "analysis_type": "genomics",
                    "preferred_tools": ["bwa", "samtools", "bcftools", "snpeff"],
                    "available_datasets": [
                        {"name": "reads.fastq", "format": "fastqsanger"},
                        {"name": "reference.fasta", "format": "fasta"}
                    ]
                }
            }
        }
    ]
    
    success_count = 0
    error_count = 0
    workflow_input_errors = []
    
    for i, scenario in enumerate(test_scenarios, 1):
        print(f"\n{i}️⃣ Testing scenario: {scenario['name']}")
        
        try:
            # Test create_workflow endpoint
            response = requests.post(
                f"{base_url}/api/ai_assistant/create_workflow",
                json=scenario['request'],
                timeout=60
            )
            
            print(f"   Status: {response.status_code}")
            
            if response.status_code == 200:
                result = response.json()
                status = result.get('status', 'unknown')
                message = result.get('message', 'No message')
                print(f"   ✅ Success - {status}: {message}")
                success_count += 1
            else:
                result = response.json()
                error_msg = result.get('error', result.get('detail', 'Unknown error'))
                print(f"   ❌ Error: {error_msg}")
                error_count += 1
                
                # Check for workflow_input_ error
                if 'workflow_input_' in str(error_msg):
                    workflow_input_errors.append({
                        'scenario': scenario['name'],
                        'error': error_msg
                    })
                    print(f"   🔴 FOUND workflow_input_ error: {error_msg}")
            
            # Also test two-stage enhanced generation
            print(f"   Testing two-stage enhanced for {scenario['name']}...")
            
            enhanced_response = requests.post(
                f"{base_url}/api/ai_assistant/two_stage_workflow?stage=enhanced",
                json=scenario['request'],
                timeout=60
            )
            
            if enhanced_response.status_code == 200:
                enhanced_result = enhanced_response.json()
                print(f"   ✅ Enhanced: {enhanced_result.get('status', 'success')}")
            else:
                enhanced_result = enhanced_response.json()
                enhanced_error = enhanced_result.get('error', 'Unknown enhanced error')
                print(f"   ❌ Enhanced error: {enhanced_error}")
                
                if 'workflow_input_' in str(enhanced_error):
                    workflow_input_errors.append({
                        'scenario': f"{scenario['name']} (enhanced)",
                        'error': enhanced_error
                    })
                    print(f"   🔴 FOUND workflow_input_ error in enhanced: {enhanced_error}")
            
        except requests.exceptions.Timeout:
            print(f"   ⏰ Timeout for {scenario['name']}")
            error_count += 1
        except Exception as e:
            print(f"   💥 Exception for {scenario['name']}: {e}")
            error_count += 1
        
        # Brief pause between tests
        time.sleep(1)
    
    # Final summary
    print(f"\n" + "="*60)
    print(f"🏁 FINAL VERIFICATION RESULTS")
    print(f"="*60)
    print(f"✅ Successful tests: {success_count}")
    print(f"❌ Failed tests: {error_count}")
    print(f"🔴 workflow_input_ errors: {len(workflow_input_errors)}")
    
    if workflow_input_errors:
        print(f"\n❌ CRITICAL: workflow_input_ errors still found:")
        for error in workflow_input_errors:
            print(f"  - {error['scenario']}: {error['error']}")
        print(f"\n💥 THE FIX HAS NOT COMPLETELY RESOLVED THE ISSUE")
        return False
    else:
        print(f"\n🎉 SUCCESS: No workflow_input_ errors found!")
        print(f"✅ The comprehensive fix appears to be working correctly")
        return True

if __name__ == "__main__":
    success = test_final_fix_verification()
    
    if success:
        print(f"\n🎯 VERIFICATION PASSED - Fix is working!")
    else:
        print(f"\n💥 VERIFICATION FAILED - Issue still exists")
    
    sys.exit(0 if success else 1)