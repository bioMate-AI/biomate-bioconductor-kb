#!/usr/bin/env python3
"""
Claude API 测试脚本

验证Claude API Key是否正确配置并能正常工作
"""

import os
import sys
import httpx
import json
import asyncio
from pathlib import Path

# Add the lib path
current_dir = Path(__file__).parent
lib_path = current_dir / 'lib'
sys.path.insert(0, str(lib_path))

def load_config():
    """加载Galaxy配置文件中的AI设置"""
    config_path = current_dir / 'config' / 'galaxy.yml'
    
    if not config_path.exists():
        print("❌ 配置文件 config/galaxy.yml 不存在")
        return None
    
    try:
        import yaml
        with open(config_path, 'r', encoding='utf-8') as f:
            config = yaml.safe_load(f)
        
        galaxy_config = config.get('galaxy', {})
        
        return {
            'provider': galaxy_config.get('ai_llm_provider'),
            'model': galaxy_config.get('ai_llm_model'),
            'api_key': galaxy_config.get('ai_llm_api_key'),
            'base_url': galaxy_config.get('ai_llm_base_url')
        }
    except Exception as e:
        print(f"❌ 配置文件解析错误: {e}")
        return None

async def test_claude_api(config):
    """测试Claude API连接"""
    
    if config['provider'] != 'anthropic':
        print(f"⚠️  当前配置的提供商是: {config['provider']}，不是 anthropic")
        print("请修改 config/galaxy.yml 中的 ai_llm_provider 为 'anthropic'")
        return False
    
    api_key = config['api_key']
    model = config['model']
    
    if not api_key or api_key == 'sk-ant-your-claude-api-key-here':
        print("❌ 请在 config/galaxy.yml 中设置您的真实 Claude API Key")
        print("API Key 应该以 'sk-ant-' 开头")
        return False
    
    print(f"🔑 API Key: {api_key[:15]}...{api_key[-8:] if len(api_key) > 23 else api_key}")
    print(f"🤖 模型: {model}")
    
    # 测试API连接
    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/json",
        "anthropic-version": "2023-06-01"
    }
    
    # 简单的测试消息
    test_message = {
        "model": model,
        "max_tokens": 100,
        "messages": [
            {
                "role": "user",
                "content": "Hello! Please respond with 'Claude API is working correctly' if you can read this message."
            }
        ]
    }
    
    try:
        print("\n🚀 正在测试Claude API连接...")
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                "https://api.anthropic.com/v1/messages",
                headers=headers,
                json=test_message,
                timeout=30.0
            )
        
        if response.status_code == 200:
            result = response.json()
            content = result.get('content', [])
            if content and len(content) > 0:
                response_text = content[0].get('text', '')
                print("✅ Claude API 连接成功!")
                print(f"📝 Claude 回应: {response_text}")
                return True
            else:
                print("❌ Claude API 响应格式异常")
                print(f"原始响应: {result}")
                return False
        
        elif response.status_code == 401:
            print("❌ API Key 无效或已过期")
            print("请检查您的 Claude API Key 是否正确")
            return False
            
        elif response.status_code == 429:
            print("❌ API 请求频率超限")
            print("请稍后再试")
            return False
            
        else:
            print(f"❌ API 请求失败: HTTP {response.status_code}")
            try:
                error_data = response.json()
                print(f"错误详情: {error_data}")
            except:
                print(f"错误内容: {response.text}")
            return False
            
    except httpx.TimeoutException:
        print("❌ 请求超时")
        print("请检查网络连接")
        return False
        
    except Exception as e:
        print(f"❌ 测试过程中出现错误: {e}")
        return False

async def test_ai_assistant_integration():
    """测试AI助手集成"""
    
    try:
        from galaxy.ai.ai_assistant import AIAssistant
        from galaxy.ai.config import AIConfig
        
        print("\n🔧 测试AI助手集成...")
        
        # 创建测试配置
        ai_config_dict = {
            'llm_provider': 'anthropic',
            'llm_model': 'claude-3-5-sonnet-20241022',
            'llm_api_key': 'test-key-will-be-replaced',
        }
        
        ai_config = AIConfig(ai_config_dict)
        print("✅ AI配置模块加载成功")
        
        print("✅ AI助手集成测试通过")
        return True
        
    except ImportError as e:
        print(f"❌ AI模块导入失败: {e}")
        return False
    except Exception as e:
        print(f"❌ AI助手集成测试失败: {e}")
        return False

def print_next_steps():
    """打印后续步骤"""
    
    print("\n" + "="*50)
    print("🎉 Claude API 配置完成!")
    print("="*50)
    
    print("\n📋 后续步骤:")
    print("1. 重启 Galaxy 服务:")
    print("   ./run.sh stop")
    print("   ./run.sh start")
    print()
    print("2. 打开 Galaxy 界面，查看右下角的AI助手按钮 🤖")
    print()
    print("3. 测试AI助手功能:")
    print("   - 输入: 'RNA-seq differential expression analysis'")
    print("   - 查看是否有相似工作流推荐")
    print("   - 尝试生成定制工作流")
    print()
    print("4. 如果遇到问题，检查:")
    print("   - 浏览器控制台是否有错误")
    print("   - Galaxy日志中是否有AI相关错误")
    print("   - 网络是否能访问 https://api.anthropic.com")

async def main():
    """主函数"""
    
    print("🔍 Claude API 配置测试")
    print("="*30)
    
    # 加载配置
    config = load_config()
    if not config:
        return
    
    print(f"📋 当前配置:")
    print(f"   提供商: {config['provider']}")
    print(f"   模型: {config['model']}")
    print(f"   API Key: {'已设置' if config['api_key'] else '未设置'}")
    
    # 测试Claude API
    api_success = await test_claude_api(config)
    
    # 测试AI助手集成
    integration_success = await test_ai_assistant_integration()
    
    # 总结
    if api_success and integration_success:
        print("\n🎉 所有测试通过!")
        print_next_steps()
    else:
        print("\n❌ 部分测试失败，请检查配置")

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\n用户中断测试")
    except Exception as e:
        print(f"\n测试过程中发生意外错误: {e}")