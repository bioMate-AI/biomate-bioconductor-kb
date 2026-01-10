#!/usr/bin/env python3
"""
测试两段展示API接口
"""

import requests
import json

def test_two_stage_api():
    """测试两段API"""
    
    base_url = "http://localhost:8080"  # Galaxy默认端口
    
    # 测试Stage 1
    print("🔍 测试 Stage 1: Similar workflows")
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
        print(f"Stage 1 Response:")
        print(f"  - Status: {data.get('status')}")
        print(f"  - Recommendations: {len(data.get('recommendations', []))}")
        
        for i, rec in enumerate(data.get('recommendations', [])[:3]):
            print(f"    {i+1}. {rec.get('name', 'N/A')} (confidence: {rec.get('confidence', 0):.2f})")
    else:
        print(f"Error: {stage1_response.text}")
    
    print("\n" + "="*50)
    
    # 测试Stage 2
    print("⚡ 测试 Stage 2: Enhanced workflows")
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
        print(f"Stage 2 Response:")
        print(f"  - Status: {data.get('status')}")
        print(f"  - Stage: {data.get('stage')}")
        if 'workflow' in data:
            workflow = data['workflow']
            print(f"  - Workflow: {workflow.get('name', 'N/A')}")
            print(f"  - Steps: {workflow.get('step_count', 0)}")
    else:
        print(f"Error: {stage2_response.text}")

if __name__ == "__main__":
    print("🧪 两段展示API测试")
    print("="*50)
    
    try:
        test_two_stage_api()
    except requests.exceptions.ConnectionError:
        print("❌ 无法连接到Galaxy服务器")
        print("请确保Galaxy正在运行：./run.sh start")
    except Exception as e:
        print(f"❌ 测试失败: {e}")