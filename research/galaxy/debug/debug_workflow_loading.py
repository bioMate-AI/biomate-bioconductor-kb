#!/usr/bin/env python3
"""
调试工作流加载问题
"""

import os
import sys
import json
import logging
from pathlib import Path

# Add the lib path
current_dir = Path(__file__).parent
lib_path = current_dir / 'lib'
sys.path.insert(0, str(lib_path))

# 设置日志
logging.basicConfig(level=logging.DEBUG)

def test_workflow_loading():
    """测试工作流数据加载"""
    
    from galaxy.ai.rag_workflow_loader import SimpleRAGEngine, RAGWorkflowRecommender
    
    data_path = "lib/galaxy/ai/data/workflows"
    
    print(f"🔍 测试工作流加载...")
    print(f"📁 数据路径: {data_path}")
    
    # 检查数据目录
    if not os.path.exists(data_path):
        print(f"❌ 数据目录不存在: {data_path}")
        return False
    
    # 统计文件数量
    workflow_files = list(Path(data_path).glob("workflow_*.json"))
    print(f"📊 找到 {len(workflow_files)} 个工作流文件")
    
    if len(workflow_files) == 0:
        print("❌ 没有找到工作流文件")
        return False
    
    # 测试单个文件解析
    print("\n🔧 测试单个文件解析:")
    test_file = workflow_files[0]
    print(f"📄 测试文件: {test_file.name}")
    
    try:
        with open(test_file, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        print(f"✅ JSON解析成功")
        print(f"   - workflow_id: {data.get('workflow_id', 'N/A')}")
        print(f"   - name: {data.get('metadata', {}).get('name', 'N/A')}")
        print(f"   - steps: {data.get('metadata', {}).get('number_of_steps', 'N/A')}")
        
    except Exception as e:
        print(f"❌ JSON解析失败: {e}")
        return False
    
    # 测试 SimpleRAGEngine
    print(f"\n🚀 测试 SimpleRAGEngine...")
    try:
        engine = SimpleRAGEngine(data_path)
        print(f"✅ SimpleRAGEngine 初始化成功")
        print(f"📊 加载的工作流数量: {len(engine.workflows)}")
        
        if len(engine.workflows) == 0:
            print("⚠️  没有加载任何工作流数据")
            return False
        
        # 显示前几个工作流
        print(f"\n📋 前5个工作流:")
        for i, (wf_id, wf_data) in enumerate(list(engine.workflows.items())[:5]):
            print(f"   {i+1}. {wf_data.name} ({wf_data.number_of_steps} steps)")
        
    except Exception as e:
        print(f"❌ SimpleRAGEngine 初始化失败: {e}")
        import traceback
        traceback.print_exc()
        return False
    
    # 测试 RAGWorkflowRecommender
    print(f"\n🎯 测试 RAGWorkflowRecommender...")
    try:
        recommender = RAGWorkflowRecommender(data_path)
        print(f"✅ RAGWorkflowRecommender 初始化成功")
        
        # 测试推荐功能
        test_query = "RNA-seq differential expression analysis"
        print(f"\n🔍 测试查询: '{test_query}'")
        
        results = recommender.get_workflow_recommendations(test_query, max_recommendations=3)
        print(f"📊 推荐结果状态: {results.get('status')}")
        print(f"📊 找到推荐数量: {len(results.get('recommendations', []))}")
        
        if results.get('recommendations'):
            print(f"📋 推荐结果:")
            for i, rec in enumerate(results['recommendations'][:3]):
                print(f"   {i+1}. {rec.get('name', 'N/A')} (相似度: {rec.get('similarity_score', 0):.2f})")
        
        return True
        
    except Exception as e:
        print(f"❌ RAGWorkflowRecommender 测试失败: {e}")
        import traceback
        traceback.print_exc()
        return False

def main():
    """主函数"""
    
    print("🧪 工作流加载调试测试")
    print("=" * 40)
    
    success = test_workflow_loading()
    
    if success:
        print(f"\n🎉 所有测试通过!")
        print("工作流加载功能正常")
    else:
        print(f"\n❌ 测试失败!")
        print("请检查错误信息并修复问题")

if __name__ == "__main__":
    main()