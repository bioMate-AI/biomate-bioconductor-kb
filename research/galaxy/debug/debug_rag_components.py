#!/usr/bin/env python3
"""
RAG组件深度调试脚本
"""

import os
import sys
import json

sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def debug_crawler_data_loading():
    """调试爬虫数据加载"""
    print("🔍 Debugging Crawler Data Loading...")
    
    try:
        from galaxy.ai.rag_workflow_generator import CrawledWorkflowData
        
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        workflow_data = CrawledWorkflowData(crawler_data_path)
        
        # 在这里设置断点查看数据加载过程
        workflow_data.load_crawler_data()
        
        print(f"✅ Loaded {len(workflow_data.workflows)} workflows")
        print(f"   Categories: {list(workflow_data.category_index.keys())[:5]}...")
        
        # 查看第一个工作流的结构
        if workflow_data.workflows:
            first_workflow = workflow_data.workflows[0]
            print(f"   Sample workflow: {first_workflow.get('name', 'N/A')}")
            print(f"   Sample tools: {first_workflow.get('tools', [])[:3]}...")
        
        return workflow_data
        
    except Exception as e:
        print(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def debug_workflow_similarity():
    """调试工作流相似度计算"""
    print("🔍 Debugging Workflow Similarity...")
    
    try:
        from galaxy.ai.rag_workflow_recommender import RAGWorkflowRecommender
        
        crawler_data_path = "lib/galaxy/ai/data/workflows"
        recommender = RAGWorkflowRecommender(crawler_data_path)
        
        # 测试查询
        test_queries = [
            "RNA-seq differential expression",
            "variant calling genome analysis",
            "protein structure prediction"
        ]
        
        for query in test_queries:
            print(f"\n   Testing query: '{query}'")
            
            # 在这里设置断点查看相似度计算过程
            results = recommender.get_workflow_recommendations(query, max_recommendations=3)
            
            for i, rec in enumerate(results.get('recommendations', [])[:3]):
                score = rec.get('similarity_score', 0)
                name = rec.get('name', 'N/A')
                print(f"     {i+1}. {name} (score: {score:.3f})")
        
        return recommender
        
    except Exception as e:
        print(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def debug_llm_integration():
    """调试LLM集成"""
    print("🔍 Debugging LLM Integration...")
    
    try:
        from galaxy.ai.llm_client import LLMClient
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        llm_client = LLMClient(DEFAULT_AI_CONFIG)
        
        # 测试简单的LLM调用
        test_prompt = """
        Based on this workflow information, create a brief description:
        - Name: RNA-seq Analysis
        - Tools: FastQC, STAR, HTSeq, DESeq2
        - Purpose: Differential gene expression analysis
        """
        
        print("   Sending test prompt to LLM...")
        
        # 在这里设置断点调试LLM调用
        response = llm_client.generate_text(test_prompt, max_tokens=150)
        
        print(f"✅ LLM Response: {response[:100]}...")
        
        return llm_client
        
    except Exception as e:
        print(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return None

def debug_workflow_export():
    """调试工作流导出功能"""
    print("🔍 Debugging Workflow Export...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowTemplate, WorkflowStep
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        
        # 创建测试工作流
        test_workflow = WorkflowTemplate(
            name="Debug Test Workflow",
            description="Test workflow for debugging export functionality",
            steps=[
                WorkflowStep(
                    step_id=1,
                    tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                    tool_version="0.72+galaxy1",
                    input_connections={},
                    parameters={},
                    annotation="Quality control",
                    position={'left': 100, 'top': 100}
                )
            ],
            inputs=[
                {
                    'label': 'Input reads',
                    'name': 'input_0',
                    'type': 'data',
                    'format': 'fastqsanger',
                    'optional': False,
                    'description': 'Raw sequencing reads'
                }
            ],
            outputs=[],
            tags=['debug', 'test']
        )
        
        # 在这里设置断点调试导出过程
        galaxy_format = generator.export_to_galaxy_format(test_workflow)
        
        print(f"✅ Exported workflow with {len(galaxy_format['steps'])} steps")
        print(f"   Workflow name: {galaxy_format.get('name', 'N/A')}")
        
        # 检查是否有workflow_input_标记残留
        workflow_input_markers = []
        for step_id, step_data in galaxy_format['steps'].items():
            connections = step_data.get('input_connections', {})
            for input_name, connection in connections.items():
                if isinstance(connection, dict) and isinstance(connection.get('id'), str):
                    if connection['id'].startswith('workflow_input_'):
                        workflow_input_markers.append(f"Step {step_id}.{input_name}")
        
        if workflow_input_markers:
            print(f"⚠️  Found workflow_input_ markers: {workflow_input_markers}")
        else:
            print("✅ No workflow_input_ markers found")
        
        return galaxy_format
        
    except Exception as e:
        print(f"❌ Failed: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    print("🚀 Starting RAG Components Deep Debug Session...")
    
    # 调试1: 爬虫数据加载
    crawler_data = debug_crawler_data_loading()
    
    # 调试2: 工作流相似度
    similarity_engine = debug_workflow_similarity()
    
    # 调试3: LLM集成
    llm_client = debug_llm_integration()
    
    # 调试4: 工作流导出
    exported_workflow = debug_workflow_export()
    
    print("\n📊 RAG Components Debug Complete!")
    print("\n💡 调试提示:")
    print("   1. 在各个函数中设置断点来深入调试")
    print("   2. 检查变量值和数据流")
    print("   3. 使用VSCode的调试控制台执行额外代码")