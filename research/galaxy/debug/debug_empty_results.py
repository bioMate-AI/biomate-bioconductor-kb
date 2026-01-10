#!/usr/bin/env python3
"""
调试workflow检索为空的问题
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

def debug_rag_search():
    """调试RAG搜索问题"""
    
    from galaxy.ai.rag_workflow_loader import SimpleRAGEngine, RAGWorkflowRecommender
    
    data_path = "lib/galaxy/ai/data/workflows"
    
    print(f"🔍 调试RAG检索为空的问题...")
    print(f"=" * 50)
    
    # 初始化引擎
    print(f"📁 数据路径: {data_path}")
    engine = SimpleRAGEngine(data_path)
    print(f"✅ 加载了 {len(engine.workflows)} 个工作流")
    
    if len(engine.workflows) == 0:
        print("❌ 没有加载任何工作流，检查数据路径")
        return
    
    # 显示前几个工作流的基本信息
    print(f"\n📋 前5个工作流概览:")
    for i, (wf_id, wf_data) in enumerate(list(engine.workflows.items())[:5]):
        print(f"  {i+1}. ID: {wf_id}")
        print(f"     Name: {wf_data.name}")
        print(f"     Tags: {wf_data.tags}")
        print(f"     Tools: {wf_data.tools[:3]}...")  # 只显示前3个工具
        print(f"     Description: {wf_data.description[:100]}...")
        print()
    
    # 测试具体的搜索查询
    test_queries = [
        "RNA-seq differential expression analysis",
        "single cell RNA sequencing",
        "variant calling",
        "ChIP-seq peak calling",
        "RNA",
        "differential",
        "expression"
    ]
    
    print(f"🔍 测试不同的搜索查询:")
    print("-" * 40)
    
    for query in test_queries:
        print(f"\n🎯 查询: '{query}'")
        
        # 使用SimpleRAGEngine直接搜索
        similar_workflows = engine.find_similar_workflows(query, top_k=5)
        print(f"   📊 找到相似工作流: {len(similar_workflows)}")
        
        if similar_workflows:
            for i, workflow in enumerate(similar_workflows[:3]):
                print(f"   {i+1}. {workflow.name} (相似度: {workflow.similarity_score:.2f})")
        
        # 计算一些具体的相似度
        if len(engine.workflows) > 0:
            sample_workflow = list(engine.workflows.values())[0]
            sample_score = engine.compute_similarity(query, sample_workflow)
            print(f"   🧮 示例相似度计算 (第1个工作流): {sample_score:.2f}")
    
    # 测试RAGWorkflowRecommender
    print(f"\n🎯 测试RAGWorkflowRecommender:")
    print("-" * 40)
    
    recommender = RAGWorkflowRecommender(data_path)
    test_query = "RNA-seq differential expression analysis"
    result = recommender.get_workflow_recommendations(test_query, max_recommendations=5)
    
    print(f"查询: '{test_query}'")
    print(f"结果状态: {result.get('status')}")
    print(f"推荐数量: {len(result.get('recommendations', []))}")
    
    if result.get('recommendations'):
        print(f"推荐详情:")
        for i, rec in enumerate(result['recommendations'][:3]):
            print(f"  {i+1}. {rec.get('name', 'N/A')}")
            print(f"     相似度: {rec.get('similarity_score', 0):.2f}")
            print(f"     工具: {rec.get('tools', [])[:3]}")
    else:
        print(f"⚠️ 没有找到推荐")
        print(f"搜索的总工作流数: {result.get('total_searched', 0)}")

def debug_similarity_calculation():
    """调试相似度计算逻辑"""
    
    from galaxy.ai.rag_workflow_loader import SimpleRAGEngine
    
    data_path = "lib/galaxy/ai/data/workflows"
    engine = SimpleRAGEngine(data_path)
    
    print(f"\n🧮 调试相似度计算:")
    print("-" * 30)
    
    # 获取一个包含RNA-seq的工作流
    rna_workflow = None
    for workflow in engine.workflows.values():
        if 'rna' in workflow.name.lower() or 'rna' in workflow.description.lower():
            rna_workflow = workflow
            break
    
    if not rna_workflow:
        print("❌ 没有找到包含RNA的工作流")
        return
    
    print(f"🧬 测试工作流: {rna_workflow.name}")
    print(f"   描述: {rna_workflow.description[:100]}...")
    print(f"   标签: {rna_workflow.tags}")
    print(f"   工具: {rna_workflow.tools}")
    
    # 测试相似度计算的各个组件
    query = "RNA-seq differential expression analysis"
    query_lower = query.lower()
    
    print(f"\n🔍 查询: '{query}'")
    
    # 检查关键词匹配
    keyword_matches = []
    for keyword, weight in engine.keyword_weights.items():
        workflow_text = f"{rna_workflow.name} {rna_workflow.description} {' '.join(rna_workflow.annotations)}".lower()
        if keyword in query_lower and keyword in workflow_text:
            keyword_matches.append((keyword, weight))
    
    print(f"   🔑 关键词匹配: {len(keyword_matches)} 个")
    for keyword, weight in keyword_matches[:5]:
        print(f"      - '{keyword}': {weight}")
    
    # 检查工具匹配
    tool_matches = []
    for tool in rna_workflow.tools:
        if tool.lower() in query_lower:
            tool_matches.append(tool)
    
    print(f"   🛠️ 工具匹配: {len(tool_matches)} 个")
    for tool in tool_matches:
        print(f"      - {tool}")
    
    # 计算总相似度
    total_score = engine.compute_similarity(query, rna_workflow)
    print(f"   📊 总相似度: {total_score:.2f}")

def main():
    """主函数"""
    
    print("🐛 工作流检索为空问题调试")
    print("=" * 40)
    
    debug_rag_search()
    debug_similarity_calculation()
    
    print(f"\n📋 调试完成")
    print("如果发现问题，请检查:")
    print("1. 数据是否正确加载")
    print("2. 相似度计算是否有效")
    print("3. 关键词权重是否合理")

if __name__ == "__main__":
    main()