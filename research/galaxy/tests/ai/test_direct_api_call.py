#!/usr/bin/env python3
"""
直接测试API调用，看看数据是否真的正确
"""

import requests
import json

def test_api_directly():
    """直接测试API"""
    
    url = "http://localhost:8080/api/ai_assistant/two_stage_workflow?stage=similar"
    payload = {
        "request_text": "I want to perform differential gene expression analysis on RNA-seq data",
        "context": {}
    }
    
    print("🔍 直接API调用测试")
    print(f"URL: {url}")
    print(f"Payload: {json.dumps(payload, indent=2)}")
    
    try:
        response = requests.post(url, json=payload, timeout=10)
        
        print(f"\n📊 响应:")
        print(f"状态码: {response.status_code}")
        print(f"响应头: {dict(response.headers)}")
        
        if response.status_code == 200:
            data = response.json()
            print(f"\n📋 响应数据:")
            print(json.dumps(data, indent=2))
            
            # 检查关键字段
            print(f"\n✅ 关键检查:")
            print(f"status: {data.get('status')}")
            print(f"recommendations存在: {data.get('recommendations') is not None}")
            print(f"recommendations数量: {len(data.get('recommendations', []))}")
            
            if data.get('recommendations'):
                first_rec = data['recommendations'][0]
                print(f"\n📝 第一个推荐:")
                for key, value in first_rec.items():
                    if isinstance(value, list) and len(value) > 3:
                        print(f"  {key}: {value[:3]}... ({len(value)} items)")
                    else:
                        print(f"  {key}: {value}")
            
            return True
        else:
            print(f"❌ API调用失败")
            print(f"错误内容: {response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 请求失败: {e}")
        return False

if __name__ == "__main__":
    success = test_api_directly()
    
    if success:
        print(f"\n🎯 API工作正常!")
        print("问题可能在前端JavaScript执行")
        print("\n建议:")
        print("1. 检查浏览器Console (F12 → Console)")
        print("2. 检查是否有JavaScript错误")
        print("3. 检查Network标签是否有API调用")
    else:
        print(f"\n❌ API有问题")