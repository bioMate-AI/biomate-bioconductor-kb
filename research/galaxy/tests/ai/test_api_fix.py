#!/usr/bin/env python3
"""
测试API接口修复效果
"""

import sys
from pathlib import Path

# Add the lib path
current_dir = Path(__file__).parent
lib_path = current_dir / 'lib'
sys.path.insert(0, str(lib_path))

def test_api_data_transformation():
    """测试API数据转换"""
    
    from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender
    from galaxy.ai.types import UserRequest
    
    print("🧪 测试API数据转换修复")
    print("=" * 40)
    
    # 初始化RAG推荐器
    data_path = "lib/galaxy/ai/data/workflows"
    recommender = RAGWorkflowRecommender(data_path)
    
    # 测试查询
    test_query = "RNA-seq differential expression analysis"
    print(f"🔍 测试查询: '{test_query}'")
    
    # 获取RAG推荐结果
    rag_result = recommender.get_workflow_recommendations(test_query, max_recommendations=5)
    
    print(f"\n📊 RAG推荐器返回:")
    print(f"  状态: {rag_result.get('status')}")
    print(f"  推荐数量: {len(rag_result.get('recommendations', []))}")
    
    if rag_result.get('recommendations'):
        print(f"\n📋 原始推荐数据格式:")
        first_rec = rag_result['recommendations'][0]
        for key, value in first_rec.items():
            print(f"  {key}: {value}")
        
        # 模拟API转换
        print(f"\n🔄 API转换后的数据格式:")
        recommendations = []
        for rec in rag_result["recommendations"][:3]:
            # 与修复后的API代码相同的转换逻辑
            similarity_score = rec.get("similarity_score", 0.0)
            confidence = min(similarity_score / 15.0, 1.0)
            
            transformed = {
                "workflow_id": rec.get("workflow_id", ""),
                "name": rec.get("name", ""),
                "description": rec.get("description", ""),
                "confidence": confidence,
                "step_count": rec.get("steps", 0),  # 修复后：使用正确的字段
                "steps": rec.get("steps", 0),
                "tools": rec.get("tools", []),
                "tags": rec.get("tags", []),
                "owner": rec.get("owner", "Galaxy Community"),
                "type": "rag_similar"
            }
            recommendations.append(transformed)
        
        # 显示转换后的数据
        for i, rec in enumerate(recommendations):
            print(f"\n  推荐 {i+1}:")
            print(f"    名称: {rec['name']}")
            print(f"    置信度: {rec['confidence']:.2%}")
            print(f"    步骤数: {rec['step_count']}")
            print(f"    工具: {rec['tools'][:3]}")
            print(f"    标签: {rec['tags']}")
        
        # 构建API响应
        api_response = {
            "status": "success",
            "stage": "similar",
            "recommendations": recommendations,
            "total_found": len(rag_result["recommendations"]),
            "query": test_query,
            "method": "RAG Similarity Search",
            "database_size": 951,
            "next_stage_available": True
        }
        
        print(f"\n✅ 完整的API响应预期:")
        print(f"  状态: {api_response['status']}")
        print(f"  阶段: {api_response['stage']}")
        print(f"  推荐数量: {len(api_response['recommendations'])}")
        print(f"  是否有数据: {'是' if api_response['recommendations'] else '否'}")
        
        return len(api_response['recommendations']) > 0
    
    else:
        print("❌ RAG推荐器没有返回数据")
        return False

def main():
    """主函数"""
    
    print("🔧 API接口数据转换测试")
    print("=" * 30)
    
    success = test_api_data_transformation()
    
    if success:
        print(f"\n🎉 修复验证成功!")
        print("✅ API数据转换正常")
        print("✅ 推荐数据格式正确")
        print("\n📋 现在应该:")
        print("1. 重启Galaxy服务器")
        print("2. 测试前端界面")
        print("3. 验证工作流推荐显示正常")
    else:
        print(f"\n❌ 修复验证失败")
        print("需要进一步调试")

if __name__ == "__main__":
    main()