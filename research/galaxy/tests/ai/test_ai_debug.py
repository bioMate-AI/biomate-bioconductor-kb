#!/usr/bin/env python3
"""
VSCode调试脚本 - AI助手功能
"""

import os
import sys

# 添加lib目录到Python路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def test_rag_workflow_generation():
    """测试RAG工作流生成功能"""
    print("🔧 Testing RAG Workflow Generation...")
    
    try:
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.rag_workflow_generator import RAGWorkflowGenerator
        from galaxy.ai.types import UserRequest
        
        # 初始化RAG生成器
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        rag_generator = RAGWorkflowGenerator(DEFAULT_AI_CONFIG, crawler_data_path)
        
        # 创建测试请求
        user_request = UserRequest(
            user_id="test_user",
            request_text="Create a RNA-seq differential expression analysis workflow",
            context={}
        )
        
        # 在这里设置断点进行调试
        result = rag_generator.generate_workflow(user_request)
        
        print(f"✅ Generation result: {result.get('success', False)}")
        if result.get('success'):
            workflow = result.get('workflow', {})
            print(f"   Workflow name: {workflow.get('name', 'N/A')}")
            print(f"   Steps: {len(workflow.get('steps', []))}")
        
        return result
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_workflow_similarity_search():
    """测试工作流相似度搜索"""
    print("🔧 Testing Workflow Similarity Search...")
    
    try:
        from galaxy.ai.rag_workflow_recommender import RAGWorkflowRecommender
        
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        recommender = RAGWorkflowRecommender(crawler_data_path)
        
        # 测试搜索
        query = "RNA-seq analysis"
        results = recommender.get_workflow_recommendations(query, max_recommendations=3)
        
        print(f"✅ Found {len(results.get('recommendations', []))} similar workflows")
        for i, rec in enumerate(results.get('recommendations', [])[:3]):
            print(f"   {i+1}. {rec.get('name', 'N/A')} (score: {rec.get('similarity_score', 0):.3f})")
        
        return results
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_ai_assistant_initialization():
    """测试AI助手初始化"""
    print("🔧 Testing AI Assistant Initialization...")
    
    try:
        from galaxy.ai.ai_assistant import AIAssistant
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        
        # 在这里设置断点
        assistant = AIAssistant(
            config=DEFAULT_AI_CONFIG,
            galaxy_app=None,  # 调试时可以为None
            crawler_data_path=crawler_data_path
        )
        
        print(f"✅ AI Assistant initialized")
        print(f"   Has RAG generator: {assistant.rag_workflow_generator is not None}")
        
        return assistant
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    print("🚀 Starting AI Assistant Debug Session...")
    
    # 测试1: AI助手初始化
    assistant = test_ai_assistant_initialization()
    
    # 测试2: 相似度搜索
    similarity_results = test_workflow_similarity_search()
    
    # 测试3: RAG工作流生成
    rag_results = test_rag_workflow_generation()
    
    print("\n📊 Debug Session Complete!")