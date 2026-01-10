#!/usr/bin/env python3
"""
调试前端逻辑问题
"""

import requests
import json

def simulate_frontend_logic():
    """模拟前端逻辑"""
    
    print("🎭 模拟前端逻辑流程")
    print("=" * 40)
    
    base_url = "http://localhost:8080"
    request_text = "I want to perform differential gene expression analysis on RNA-seq data"
    
    print(f"📝 用户输入: {request_text}")
    print(f"🔗 调用API: /api/ai_assistant/two_stage_workflow?stage=similar")
    
    try:
        # 模拟前端的API调用
        rag_response = requests.post(
            f"{base_url}/api/ai_assistant/two_stage_workflow?stage=similar",
            json={
                "request_text": request_text,
                "context": {}
            },
            timeout=10
        )
        
        print(f"📊 API响应状态码: {rag_response.status_code}")
        
        if rag_response.status_code == 200:
            data = rag_response.json()
            
            # 模拟前端的判断逻辑
            print(f"\n🔍 前端判断逻辑:")
            print(f"  data.status: {data.get('status')}")
            print(f"  data.recommendations 存在: {data.get('recommendations') is not None}")
            print(f"  data.recommendations 长度: {len(data.get('recommendations', []))}")
            
            # 前端的具体判断条件
            condition1 = data.get('status') == 'success'
            condition2 = data.get('recommendations') is not None
            condition3 = len(data.get('recommendations', [])) > 0
            
            print(f"\n✅ 判断结果:")
            print(f"  status === 'success': {condition1}")
            print(f"  recommendations 不为空: {condition2}")
            print(f"  recommendations.length > 0: {condition3}")
            print(f"  总体条件满足: {condition1 and condition2 and condition3}")
            
            if condition1 and condition2 and condition3:
                print(f"\n🎉 应该显示推荐结果!")
                print(f"调用: showTwoStageWorkflowResults(recommendations, requestText)")
                
                # 显示推荐数据
                recommendations = data['recommendations']
                print(f"\n📋 推荐数据概览:")
                for i, rec in enumerate(recommendations):
                    confidence_percent = round(rec.get('confidence', 0) * 100, 1)
                    print(f"  {i+1}. {rec.get('name', 'N/A')}")
                    print(f"     置信度: {confidence_percent}%")
                    print(f"     步骤: {rec.get('steps', 0)}")
                    print(f"     工具数: {len(rec.get('tools', []))}")
                    print()
                
                return True
                
            else:
                print(f"\n❌ 条件不满足，会执行 fallback")
                print(f"调用: fallbackToOriginalFlow(requestText)")
                return False
                
        else:
            print(f"❌ API调用失败: {rag_response.status_code}")
            print(f"错误: {rag_response.text}")
            return False
            
    except Exception as e:
        print(f"❌ 模拟过程出错: {e}")
        return False

def check_browser_console():
    """建议检查浏览器控制台"""
    
    print(f"\n🌐 浏览器调试建议:")
    print("=" * 30)
    print("1. 打开浏览器开发者工具 (F12)")
    print("2. 切换到 Network 标签")
    print("3. 清空网络日志")
    print("4. 在AI助手中输入查询")
    print("5. 查看实际的API调用和响应")
    print()
    print("6. 切换到 Console 标签")
    print("7. 查看是否有JavaScript错误")
    print("8. 查看是否有 'Enhanced workflow search failed' 错误")
    print()
    print("📋 关键检查点:")
    print("• API调用是否到达正确的端点")
    print("• 响应数据格式是否正确")
    print("• 前端条件判断是否通过")
    print("• 是否有异步处理问题")

def debug_cache_issue():
    """调试缓存问题"""
    
    print(f"\n🔄 可能的缓存问题:")
    print("=" * 25)
    print("1. 浏览器缓存了旧的JavaScript代码")
    print("   解决: Ctrl+F5 强制刷新")
    print()
    print("2. Galaxy服务器缓存了旧的Vue组件")
    print("   解决: 重启Galaxy服务器")
    print()
    print("3. 前端构建缓存问题")
    print("   解决: 删除构建缓存重新构建")

def main():
    """主函数"""
    
    print("🐛 前端逻辑调试")
    print("=" * 20)
    
    success = simulate_frontend_logic()
    
    if success:
        print(f"\n🤔 API数据正常，但前端显示为空...")
        print("可能的原因:")
        print("1. 浏览器缓存了旧代码")
        print("2. JavaScript执行出现异常")
        print("3. 异步处理时机问题")
        print("4. DOM更新问题")
    else:
        print(f"\n❌ API数据有问题")
    
    check_browser_console()
    debug_cache_issue()

if __name__ == "__main__":
    main()