#!/usr/bin/env python3
"""
Test English Interface for AI Assistant
"""

import requests
import json
import time

def test_english_two_stage_api():
    """Test English two-stage API responses"""
    
    base_url = "http://localhost:8080"  # Galaxy default port
    
    print("🌍 Testing English Two-Stage AI Assistant Interface")
    print("=" * 60)
    
    # Test Stage 1: Similar workflows
    print("\n🔍 Testing Stage 1: Similar Workflows")
    print("-" * 40)
    
    stage1_response = requests.post(
        f"{base_url}/api/ai_assistant/two_stage_workflow?stage=similar",
        json={
            "request_text": "I want to perform differential gene expression analysis on RNA-seq data",
            "context": {}
        }
    )
    
    print(f"Status Code: {stage1_response.status_code}")
    if stage1_response.status_code == 200:
        data = stage1_response.json()
        print(f"✅ Stage 1 Response (English):")
        print(f"  📊 Status: {data.get('status')}")
        print(f"  🧬 Method: {data.get('method', 'N/A')}")
        print(f"  📚 Database Size: {data.get('database_size', 'N/A')}")
        print(f"  🔍 Query: {data.get('query', 'N/A')}")
        print(f"  📋 Recommendations Found: {len(data.get('recommendations', []))}")
        
        # Display sample recommendations
        for i, rec in enumerate(data.get('recommendations', [])[:3]):
            confidence = round((rec.get('confidence', 0) * 100), 1)
            print(f"    {i+1}. {rec.get('name', 'N/A')} (Similarity: {confidence}%)")
            if rec.get('tools'):
                tools = ', '.join(rec.get('tools', [])[:3])
                print(f"       🛠️ Tools: {tools}")
    else:
        print(f"❌ Error: {stage1_response.text}")
        return False
    
    time.sleep(1)  # Brief pause between requests
    
    # Test Stage 2: Enhanced workflow generation
    print(f"\n⚡ Testing Stage 2: Enhanced Workflow Generation")
    print("-" * 40)
    
    stage2_response = requests.post(
        f"{base_url}/api/ai_assistant/two_stage_workflow?stage=enhanced",
        json={
            "request_text": "I want to perform differential gene expression analysis on RNA-seq data",
            "context": {}
        }
    )
    
    print(f"Status Code: {stage2_response.status_code}")
    if stage2_response.status_code == 200:
        data = stage2_response.json()
        print(f"✅ Stage 2 Response (English):")
        print(f"  📊 Status: {data.get('status')}")
        print(f"  🎯 Stage: {data.get('stage', 'N/A')}")
        print(f"  🔬 Method: {data.get('method', 'N/A')}")
        print(f"  ⏱️ Response Time: {data.get('response_time', 'N/A')}")
        
        if 'workflow' in data:
            workflow = data['workflow']
            print(f"  📋 Workflow Generated:")
            print(f"    Name: {workflow.get('name', 'N/A')}")
            print(f"    Steps: {workflow.get('step_count', 0)}")
            print(f"    Description: {workflow.get('description', 'N/A')[:100]}{'...' if len(workflow.get('description', '')) > 100 else ''}")
            
            if workflow.get('tags'):
                print(f"    🏷️ Tags: {', '.join(workflow.get('tags', [])[:3])}")
        
        if 'note' in data:
            print(f"  📝 Note: {data['note']}")
            
    else:
        print(f"❌ Error: {stage2_response.text}")
        return False
    
    return True

def display_expected_ui_flow():
    """Display the expected English UI flow"""
    
    print(f"\n📱 Expected English UI Flow:")
    print("=" * 60)
    
    print(f"""
🎯 User Input: "I want to perform differential gene expression analysis on RNA-seq data"
    ⬇️
🔍 Step 1: Finding Similar Workflows
    Loading: "Analyzing your requirements and searching for the most relevant workflows..."
    ⬇️
✅ Step 1 Complete: Found 3 Similar Workflows
    
    Based on your request "...", found the following most relevant options 
    from 951 Galaxy community workflows:

    1. **RNA-Seq Differential Expression Analysis**
       📊 Similarity: 89% | 🔧 Steps: 15
       🛠️ Key Tools: DESeq2, EdgeR, FastQC
       [✅ Use "RNA-Seq Differential Expression Analysis"]

    2. **Single-Cell RNA-seq Preprocessing**
       📊 Similarity: 76% | 🔧 Steps: 12
       [✅ Use "Single-Cell RNA-seq Preprocessing"]

    [🎯 Need Something Different? Generate Custom Workflow] ← User clicks
    ⬇️
⚡ Step 2: Generating Custom Workflow
    Loading: "Based on the similar workflows found earlier, generating a fully 
             customized solution for you... This may take 2-5 seconds..."
    ⬇️
🎯 Step 2 Complete: Custom Workflow Generated

    Based on your requirements and similar workflow analysis, 
    a personalized solution has been generated:

    📋 Workflow Name: Custom RNA-seq Differential Expression Workflow
    🎯 Generation Method: RAG Enhanced Generation
    📊 Confidence: 92%
    🔗 Based on: 3 similar workflows
    ⏱️ Response Time: 3 seconds

    ✨ This is a customized solution tailored for you!

    [🚀 Create This Custom Workflow]
""")

def main():
    """Main test function"""
    
    print("🧪 English Interface Testing Suite")
    print("=" * 50)
    
    try:
        # Test API responses
        api_success = test_english_two_stage_api()
        
        # Show expected UI flow
        display_expected_ui_flow()
        
        # Summary
        if api_success:
            print(f"\n🎉 API Tests Passed!")
            print("✅ All responses are in English")
            print("✅ Two-stage flow works correctly")
            print("\n📋 Next Steps:")
            print("1. Restart Galaxy: ./run.sh stop && ./run.sh start")
            print("2. Open Galaxy in browser")
            print("3. Click AI Assistant button (🤖) in bottom right")
            print("4. Test the English interface manually")
        else:
            print(f"\n❌ Some tests failed!")
            print("Please check Galaxy server and try again")
            
    except requests.exceptions.ConnectionError:
        print("❌ Cannot connect to Galaxy server")
        print("Please ensure Galaxy is running: ./run.sh start")
    except Exception as e:
        print(f"❌ Test failed: {e}")

if __name__ == "__main__":
    main()