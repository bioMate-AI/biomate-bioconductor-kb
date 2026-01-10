#!/usr/bin/env python3
"""
调试实际API接口响应
"""

import requests
import json
import time

def test_actual_api():
    """测试实际运行的API"""
    
    base_url = "http://localhost:8080"
    
    print("🔍 测试实际API接口响应")
    print("=" * 50)
    
    # 测试原始接口
    print("\n1️⃣ 测试原始接口 /api/ai_assistant/enhanced_workflow_recommendations?level=quick")
    try:
        original_response = requests.post(
            f"{base_url}/api/ai_assistant/enhanced_workflow_recommendations?level=quick",
            json={
                "request_text": "I want to perform differential gene expression analysis on RNA-seq data",
                "context": {}
            },
            timeout=10
        )
        
        print(f"状态码: {original_response.status_code}")
        if original_response.status_code == 200:
            data = original_response.json()
            print(f"响应数据:")
            print(json.dumps(data, indent=2))
        else:
            print(f"错误: {original_response.text}")
            
    except Exception as e:
        print(f"原始接口测试失败: {e}")
    
    time.sleep(1)
    
    # 测试新的两段展示接口
    print(f"\n2️⃣ 测试新接口 /api/ai_assistant/two_stage_workflow?stage=similar")
    try:
        new_response = requests.post(
            f"{base_url}/api/ai_assistant/two_stage_workflow?stage=similar",
            json={
                "request_text": "I want to perform differential gene expression analysis on RNA-seq data",
                "context": {}
            },
            timeout=10
        )
        
        print(f"状态码: {new_response.status_code}")
        if new_response.status_code == 200:
            data = new_response.json()
            print(f"响应数据:")
            print(json.dumps(data, indent=2))
            
            # 检查关键字段
            if 'recommendations' in data:
                print(f"\n✅ 找到推荐字段")
                print(f"推荐数量: {len(data['recommendations'])}")
                
                if data['recommendations']:
                    first_rec = data['recommendations'][0]
                    print(f"第一个推荐的字段:")
                    for key, value in first_rec.items():
                        print(f"  {key}: {value}")
                else:
                    print("❌ 推荐列表为空")
            else:
                print("❌ 没有找到推荐字段")
                
        else:
            print(f"错误: {new_response.text}")
            
    except Exception as e:
        print(f"新接口测试失败: {e}")
    
    # 测试API状态
    print(f"\n3️⃣ 测试API状态")
    try:
        status_response = requests.get(f"{base_url}/api/ai_assistant/status", timeout=5)
        print(f"状态码: {status_response.status_code}")
        if status_response.status_code == 200:
            data = status_response.json()
            print("AI助手状态:")
            print(json.dumps(data, indent=2))
    except Exception as e:
        print(f"状态检查失败: {e}")

def check_frontend_call():
    """检查前端实际调用的接口"""
    
    print(f"\n🎯 检查前端调用的接口")
    print("=" * 30)
    
    # 检查前端代码中的接口调用
    frontend_file = "/Users/renyuankai/work/biometa/galaxy/client/src/components/AI/AIAssistantPanel.vue"
    
    try:
        with open(frontend_file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # 查找API调用
        import re
        api_calls = re.findall(r'axios\.post\(\s*[`"\'](.*?)[`"\']', content)
        
        print("前端中的API调用:")
        for i, call in enumerate(api_calls):
            print(f"{i+1}. {call}")
        
        # 检查具体的两段展示调用
        if 'two_stage_workflow' in content:
            print("✅ 前端包含 two_stage_workflow 调用")
        else:
            print("❌ 前端不包含 two_stage_workflow 调用")
            
    except Exception as e:
        print(f"无法读取前端文件: {e}")

def main():
    """主函数"""
    
    print("🐛 调试实际API接口问题")
    print("=" * 40)
    
    test_actual_api()
    check_frontend_call()
    
    print(f"\n📋 调试建议:")
    print("1. 检查Galaxy是否正常运行")
    print("2. 检查AI助手是否正确初始化")
    print("3. 检查前端调用的接口路径")
    print("4. 检查网络请求和响应")

if __name__ == "__main__":
    main()