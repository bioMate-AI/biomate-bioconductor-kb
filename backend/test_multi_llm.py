#!/usr/bin/env python3
"""
多LLM提供商测试脚本

测试不同AI模型提供商的集成是否正常
"""

import sys
import os

def test_all_providers():
    """测试所有支持的AI提供商"""
    try:
        # 添加Galaxy lib到路径
        galaxy_lib_path = os.path.join(os.path.dirname(__file__), 'lib')
        sys.path.insert(0, galaxy_lib_path)
        
        from galaxy.ai.config import AIConfig
        from galaxy.ai.llm_client import LLMClient, get_all_providers, get_recommended_model
        
        print("✅ AI模块导入成功")
        print("=" * 60)
        
        # 获取所有提供商信息
        providers = get_all_providers()
        
        print("📋 支持的AI提供商:")
        print("-" * 60)
        
        for provider_id, provider_info in providers.items():
            print(f"\n🤖 {provider_info['name']}")
            print(f"   ID: {provider_id}")
            print(f"   推荐模型: {provider_info['recommended']}")
            print(f"   需要API密钥: {'是' if provider_info['api_key_required'] else '否'}")
            print(f"   描述: {provider_info['description']}")
            print(f"   可用模型: {', '.join(provider_info['models'][:3])}...")
        
        print("\n" + "=" * 60)
        print("🧪 测试模型配置创建:")
        print("-" * 60)
        
        # 测试不同提供商的配置创建
        test_providers = ['qwen', 'zhipu', 'moonshot', 'openai', 'anthropic']
        
        for provider in test_providers:
            try:
                recommended_model = get_recommended_model(provider)
                
                test_config = AIConfig({
                    'llm_provider': provider,
                    'llm_model': recommended_model,
                    'llm_api_key': 'test-key-placeholder',
                })
                
                print(f"✅ {provider.upper()}: {recommended_model}")
                
            except Exception as e:
                print(f"❌ {provider.upper()}: 配置创建失败 - {e}")
        
        print("\n" + "=" * 60)
        print("💡 快速使用指南:")
        print("-" * 60)
        
        print("""
🚀 推荐配置 (通义千问):
----------------------------------------
galaxy:
  enable_ai_assistant: true
  ai_llm_provider: "qwen"
  ai_llm_model: "qwen-max"
  ai_llm_api_key: "sk-your-qwen-api-key"

📝 获取API密钥:
- 通义千问: https://dashscope.console.aliyun.com/
- 智谱AI: https://open.bigmodel.cn/
- 月之暗面: https://platform.moonshot.cn/
- DeepSeek: https://platform.deepseek.com/
- 百川智能: https://platform.baichuan-ai.com/

🔧 配置模板:
- 通义千问: cp config/galaxy_qwen_example.yml config/galaxy.yml
- Claude: cp config/galaxy_claude_example.yml config/galaxy.yml

🧪 测试连接:
- .venv/bin/python test_multi_llm.py
- .venv/bin/python test_api_connection.py [provider]
        """)
        
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_specific_provider(provider_name, api_key):
    """测试特定提供商的API连接"""
    try:
        # 添加Galaxy lib到路径
        galaxy_lib_path = os.path.join(os.path.dirname(__file__), 'lib')
        sys.path.insert(0, galaxy_lib_path)
        
        from galaxy.ai.config import AIConfig
        from galaxy.ai.llm_client import LLMClient, get_recommended_model
        
        recommended_model = get_recommended_model(provider_name)
        
        config = AIConfig({
            'llm_provider': provider_name,
            'llm_model': recommended_model,
            'llm_api_key': api_key,
        })
        
        print(f"🔍 测试 {provider_name.upper()} 连接...")
        print(f"   模型: {recommended_model}")
        
        client = LLMClient(config)
        result = client.test_connection()
        
        if result['success']:
            print(f"✅ 连接成功!")
            print(f"📝 响应: {result['response'][:100]}...")
        else:
            print(f"❌ 连接失败: {result['error']}")
        
        return result['success']
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        return False

if __name__ == "__main__":
    print("🧪 Galaxy多模型AI助手测试")
    print("=" * 60)
    
    if len(sys.argv) == 3:
        # 测试特定提供商
        provider = sys.argv[1].lower()
        api_key = sys.argv[2]
        
        print(f"测试特定提供商: {provider}")
        success = test_specific_provider(provider, api_key)
    else:
        # 测试所有提供商信息
        success = test_all_providers()
    
    if success:
        print("\n✅ 测试完成!")
        print("\n📌 使用方法:")
        print("   1. 选择一个AI提供商并获取API密钥")
        print("   2. 在 config/galaxy.yml 中配置提供商和密钥")
        print("   3. 运行: sh start_galaxy_with_ai.sh")
        print("   4. 在Galaxy界面右下角寻找AI助手按钮 🤖")
    else:
        print("\n❌ 测试失败，请检查配置!")