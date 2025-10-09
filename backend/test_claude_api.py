#!/usr/bin/env python3
"""
Claude API 测试脚本

测试Claude API集成是否正常工作
"""

import sys
import os

def test_claude_api():
    """测试Claude API连接"""
    try:
        # 添加Galaxy lib到路径
        galaxy_lib_path = os.path.join(os.path.dirname(__file__), 'lib')
        sys.path.insert(0, galaxy_lib_path)
        
        from galaxy.ai.config import AIConfig
        from galaxy.ai.llm_client import LLMClient
        
        print("✅ AI模块导入成功")
        
        # 测试配置（请替换为您的真实API密钥）
        test_config = AIConfig({
            'llm_provider': 'anthropic',
            'llm_model': 'claude-3-5-sonnet-20241022',
            'llm_api_key': 'sk-ant-your-api-key-here',  # 替换为您的Claude API密钥
        })
        
        print(f"✅ AI配置创建成功: {test_config.llm_provider} - {test_config.llm_model}")
        
        # 创建LLM客户端
        llm_client = LLMClient(test_config)
        print("✅ LLM客户端创建成功")
        
        # 测试连接（只有在有有效API密钥时才运行）
        api_key = test_config.llm_api_key
        if api_key and api_key != 'sk-ant-your-api-key-here':
            print("\n🔍 测试Claude API连接...")
            result = llm_client.test_connection()
            
            if result['success']:
                print(f"✅ Claude API连接成功!")
                print(f"📝 响应: {result['response']}")
            else:
                print(f"❌ Claude API连接失败: {result['error']}")
        else:
            print("\n⚠️  跳过API测试 - 请在配置中设置您的Claude API密钥")
            print("   在config/galaxy.yml中设置:")
            print("   ai_llm_api_key: 'sk-ant-your-real-api-key'")
        
        return True
        
    except Exception as e:
        print(f"❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("🧪 测试Claude API集成")
    print("=" * 50)
    
    success = test_claude_api()
    
    if success:
        print("\n✅ Claude API集成测试完成!")
    else:
        print("\n❌ Claude API集成测试失败!")