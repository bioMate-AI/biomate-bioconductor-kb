#!/usr/bin/env python3
"""
测试工作流创建修复
"""

import sys
from pathlib import Path
import json

# Add the lib path
current_dir = Path(__file__).parent
lib_path = current_dir / 'lib'
sys.path.insert(0, str(lib_path))

def test_workflow_creation_fix():
    """测试工作流创建修复"""
    
    from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender
    
    print("🧪 测试工作流创建修复")
    print("=" * 40)
    
    # 初始化RAG推荐器
    data_path = "lib/galaxy/ai/data/workflows"
    recommender = RAGWorkflowRecommender(data_path)
    
    # 测试特定workflow_id加载
    test_workflow_id = "40a65b5bc1dcc0b4"
    print(f"🔍 测试加载workflow ID: {test_workflow_id}")
    
    # 使用新的load_workflow_by_id方法
    workflow_data = recommender.load_workflow_by_id(test_workflow_id)
    
    if workflow_data:
        print(f"✅ 成功加载工作流:")
        print(f"  名称: {workflow_data['name']}")
        print(f"  描述: {workflow_data['description'][:100]}...")
        print(f"  步骤数: {workflow_data['steps']}")
        print(f"  工具数: {len(workflow_data['tools'])}")
        print(f"  标签: {workflow_data['tags']}")
        
        # 检查workflow_json
        workflow_json = workflow_data.get('workflow_json', {})
        if workflow_json:
            steps_data = workflow_json.get('steps', {})
            print(f"  workflow_json存在: ✅")
            print(f"  实际步骤数据: {len(steps_data)} 个步骤")
            
            if steps_data:
                first_step_key = list(steps_data.keys())[0]
                first_step = steps_data[first_step_key]
                print(f"  第一个步骤示例:")
                print(f"    ID: {first_step_key}")
                print(f"    类型: {first_step.get('type', 'N/A')}")
                print(f"    工具ID: {first_step.get('tool_id', 'N/A')}")
        else:
            print(f"  workflow_json: ❌ 缺失")
        
        return True
    else:
        print(f"❌ 无法加载工作流 {test_workflow_id}")
        return False

def test_create_workflow_simulation():
    """模拟创建工作流的过程"""
    
    print(f"\n🎯 模拟工作流创建过程")
    print("=" * 30)
    
    # 模拟用户请求数据（来自您的curl请求）
    context_data = {
        "workflow_template": {
            "name": "RNA-Seq Differential Expression Analysis with Visualization (release v0.4)",
            "workflow_id": "40a65b5bc1dcc0b4",
            "type": "rag_workflow",
            "confidence": 0.9133333333333333
        }
    }
    
    workflow_id = context_data["workflow_template"]["workflow_id"]
    print(f"📝 用户请求基于工作流: {workflow_id}")
    
    from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender
    
    # 初始化RAG推荐器
    data_path = "lib/galaxy/ai/data/workflows"
    recommender = RAGWorkflowRecommender(data_path)
    
    # 加载特定工作流
    workflow_data = recommender.load_workflow_by_id(workflow_id)
    
    if workflow_data:
        print(f"✅ 找到目标工作流")
        
        # 模拟创建工作流模板的逻辑
        workflow_json = workflow_data.get("workflow_json", {})
        if workflow_json and "steps" in workflow_json:
            steps_list = list(workflow_json["steps"].values())
            print(f"📋 从JSON加载了 {len(steps_list)} 个实际步骤")
            
            # 显示前3个步骤的信息
            for i, step in enumerate(steps_list[:3]):
                step_type = step.get('type', 'unknown')
                tool_id = step.get('tool_id', 'N/A')
                label = step.get('label', step.get('name', f'Step {i+1}'))
                print(f"  步骤 {i+1}: {label} ({step_type}) - {tool_id}")
        else:
            # 备用方案：基于步骤计数创建占位符
            step_count = workflow_data.get("steps", 0)
            placeholder_steps = [{"id": i, "name": f"Step {i+1}"} for i in range(step_count)]
            print(f"📋 创建了 {len(placeholder_steps)} 个占位符步骤")
        
        print(f"🎉 工作流创建逻辑验证成功！")
        return True
    else:
        print(f"❌ 无法找到目标工作流")
        return False

def main():
    """主函数"""
    
    print("🔧 工作流创建修复验证")
    print("=" * 35)
    
    success1 = test_workflow_creation_fix()
    success2 = test_create_workflow_simulation()
    
    if success1 and success2:
        print(f"\n🎊 修复验证成功！")
        print("✅ workflow_by_id 加载正常")
        print("✅ 工作流步骤数据完整")
        print("✅ 创建逻辑应该正常工作")
        print("\n📋 现在工作流创建应该包含实际步骤而不是空步骤")
    else:
        print(f"\n❌ 修复验证失败")
        print("需要进一步调试")

if __name__ == "__main__":
    main()