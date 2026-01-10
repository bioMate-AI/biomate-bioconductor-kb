#!/usr/bin/env python3
"""
分析真实Galaxy Workflow的复杂度

目标：
1. 解析真实的Galaxy workflow JSON
2. 分析步骤依赖关系
3. 构建DAG
4. 识别复杂模式（并行、顺序、菱形等）
5. 验证是否能正确处理

这个测试不实际运行workflow，只验证解析和DAG构建逻辑
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Set, Tuple
from collections import defaultdict

# 真实workflow路径
WORKFLOW_FILE = Path("/Users/renyuankai/work/biometa/galaxy/lib/galaxy/ai/data/workflows/workflow_00a4dbc9329c638b.json")


class WorkflowAnalyzer:
    """Workflow复杂度分析器"""

    def __init__(self, workflow_json: Dict):
        self.workflow = workflow_json
        self.steps = workflow_json['workflow_json']['steps']
        self.connections = defaultdict(list)  # step_id -> [(to_step_id, output_name, input_name)]
        self.reverse_connections = defaultdict(list)  # step_id -> [(from_step_id, ...)]

        self._build_connection_graph()

    def _build_connection_graph(self):
        """构建连接图"""
        for step_id, step_data in self.steps.items():
            input_connections = step_data.get('input_connections', {})

            for input_name, connection_info in input_connections.items():
                if isinstance(connection_info, dict):
                    from_step = str(connection_info['id'])
                    output_name = connection_info.get('output_name', 'output')

                    self.connections[from_step].append((step_id, output_name, input_name))
                    self.reverse_connections[step_id].append((from_step, output_name, input_name))
                elif isinstance(connection_info, list):
                    # 多个输入连接
                    for conn in connection_info:
                        from_step = str(conn['id'])
                        output_name = conn.get('output_name', 'output')

                        self.connections[from_step].append((step_id, output_name, input_name))
                        self.reverse_connections[step_id].append((from_step, output_name, input_name))

    def analyze_basic_info(self):
        """分析基本信息"""
        print("="*80)
        print("Workflow 基本信息")
        print("="*80)

        metadata = self.workflow.get('metadata', {})
        workflow_json = self.workflow['workflow_json']

        print(f"名称: {metadata.get('name', 'N/A')}")
        print(f"ID: {metadata.get('id', 'N/A')}")
        print(f"总步骤数: {metadata.get('number_of_steps', len(self.steps))}")
        print(f"创建时间: {metadata.get('create_time', 'N/A')}")
        print(f"作者: {workflow_json.get('creator', [{}])[0].get('name', 'N/A')}")
        print()

    def analyze_step_types(self):
        """分析步骤类型"""
        print("="*80)
        print("步骤类型统计")
        print("="*80)

        type_counts = defaultdict(int)
        tool_steps = []

        for step_id, step_data in self.steps.items():
            step_type = step_data.get('type', 'unknown')
            type_counts[step_type] += 1

            if step_type == 'tool':
                tool_id = step_data.get('tool_id', 'unknown')
                tool_name = step_data.get('name', 'unnamed')
                tool_steps.append((step_id, tool_name, tool_id))

        for step_type, count in sorted(type_counts.items()):
            print(f"  {step_type}: {count}")

        print(f"\n工具步骤详情:")
        for step_id, tool_name, tool_id in sorted(tool_steps):
            print(f"  Step {step_id}: {tool_name}")
            if tool_id and tool_id != 'unknown':
                print(f"           {tool_id[:80]}...")
        print()

    def analyze_dependencies(self):
        """分析依赖关系"""
        print("="*80)
        print("依赖关系分析")
        print("="*80)

        # 统计每个步骤的前驱和后继
        step_deps = {}
        for step_id in self.steps.keys():
            predecessors = [from_step for from_step, _, _ in self.reverse_connections[step_id]]
            successors = [to_step for to_step, _, _ in self.connections[step_id]]
            step_deps[step_id] = {
                'predecessors': predecessors,
                'successors': successors,
                'in_degree': len(predecessors),
                'out_degree': len(successors)
            }

        # 找出输入步骤（无前驱）
        input_steps = [sid for sid, deps in step_deps.items() if deps['in_degree'] == 0]
        print(f"输入步骤 (无前驱): {len(input_steps)}")
        for sid in input_steps:
            step_name = self.steps[sid].get('label', self.steps[sid].get('name', f'Step {sid}'))
            print(f"  Step {sid}: {step_name}")

        # 找出输出步骤（无后继）
        output_steps = [sid for sid, deps in step_deps.items() if deps['out_degree'] == 0]
        print(f"\n输出步骤 (无后继): {len(output_steps)}")
        for sid in output_steps:
            step_name = self.steps[sid].get('label', self.steps[sid].get('name', f'Step {sid}'))
            print(f"  Step {sid}: {step_name}")

        # 找出扇出步骤（多个后继）
        fanout_steps = [sid for sid, deps in step_deps.items() if deps['out_degree'] > 1]
        print(f"\n扇出步骤 (多个后继): {len(fanout_steps)}")
        for sid in fanout_steps:
            step_name = self.steps[sid].get('label', self.steps[sid].get('name', f'Step {sid}'))
            out_degree = step_deps[sid]['out_degree']
            successors = step_deps[sid]['successors']
            print(f"  Step {sid}: {step_name} → {out_degree} 个后继 {successors}")

        # 找出扇入步骤（多个前驱）
        fanin_steps = [sid for sid, deps in step_deps.items() if deps['in_degree'] > 1]
        print(f"\n扇入步骤 (多个前驱): {len(fanin_steps)}")
        for sid in fanin_steps:
            step_name = self.steps[sid].get('label', self.steps[sid].get('name', f'Step {sid}'))
            in_degree = step_deps[sid]['in_degree']
            predecessors = step_deps[sid]['predecessors']
            print(f"  Step {sid}: {step_name} ← {in_degree} 个前驱 {predecessors}")

        print()
        return step_deps

    def detect_parallel_patterns(self, step_deps: Dict):
        """检测并行模式"""
        print("="*80)
        print("并行模式检测")
        print("="*80)

        # 检测扇出-扇入模式
        patterns = []

        for fanout_step in [sid for sid, deps in step_deps.items() if deps['out_degree'] > 1]:
            successors = step_deps[fanout_step]['successors']

            # 检查这些后继是否有共同的汇聚点
            successor_successors = defaultdict(list)
            for succ in successors:
                for next_step in step_deps[succ]['successors']:
                    successor_successors[next_step].append(succ)

            # 找到被多个后继连接的步骤（潜在的扇入点）
            for fanin_step, sources in successor_successors.items():
                if len(sources) > 1:
                    patterns.append({
                        'type': 'fan-out-fan-in',
                        'fanout_step': fanout_step,
                        'parallel_steps': sources,
                        'fanin_step': fanin_step
                    })

        if patterns:
            print(f"发现 {len(patterns)} 个扇出-扇入模式:")
            for i, pattern in enumerate(patterns, 1):
                fanout_name = self.steps[pattern['fanout_step']].get('name', f"Step {pattern['fanout_step']}")
                fanin_name = self.steps[pattern['fanin_step']].get('name', f"Step {pattern['fanin_step']}")
                parallel_count = len(pattern['parallel_steps'])

                print(f"\n  模式 {i}:")
                print(f"    扇出: Step {pattern['fanout_step']} ({fanout_name})")
                print(f"    并行: {parallel_count} 个步骤 {pattern['parallel_steps']}")
                print(f"    扇入: Step {pattern['fanin_step']} ({fanin_name})")
        else:
            print("未发现明显的扇出-扇入模式")

        print()

    def compute_execution_layers(self, step_deps: Dict) -> List[Set[str]]:
        """计算执行层次（拓扑排序的层次化版本）"""
        print("="*80)
        print("执行层次分析（拓扑排序）")
        print("="*80)

        # 使用Kahn算法计算拓扑排序和层次
        in_degree = {sid: deps['in_degree'] for sid, deps in step_deps.items()}
        layers = []
        current_layer = [sid for sid, degree in in_degree.items() if degree == 0]

        processed = set()

        while current_layer:
            layers.append(set(current_layer))
            processed.update(current_layer)

            next_layer = []
            for step_id in current_layer:
                for successor in step_deps[step_id]['successors']:
                    in_degree[successor] -= 1
                    if in_degree[successor] == 0 and successor not in processed:
                        next_layer.append(successor)

            current_layer = next_layer

        # 检查是否有环
        if len(processed) != len(self.steps):
            unprocessed = set(self.steps.keys()) - processed
            print(f"⚠️  警告: 检测到循环依赖！未处理的步骤: {unprocessed}\n")
        else:
            print(f"✅ 无循环依赖，可以执行\n")

        print(f"总层数: {len(layers)}")
        print(f"最大并行度: {max(len(layer) for layer in layers)}")
        print(f"\n层次详情:")

        for i, layer in enumerate(layers):
            print(f"\n  Layer {i} ({len(layer)} 个步骤，可并行执行):")
            for sid in sorted(layer, key=lambda x: int(x)):
                step_name = self.steps[sid].get('label', self.steps[sid].get('name', f'Step {sid}'))
                step_type = self.steps[sid].get('type', 'unknown')
                print(f"    Step {sid}: {step_name} ({step_type})")

        print()
        return layers

    def estimate_complexity(self, layers: List[Set[str]]):
        """估算复杂度"""
        print("="*80)
        print("复杂度估算")
        print("="*80)

        total_steps = len(self.steps)
        num_layers = len(layers)
        max_parallelism = max(len(layer) for layer in layers)
        avg_parallelism = sum(len(layer) for layer in layers) / num_layers if num_layers > 0 else 0

        # 统计工具类型步骤
        tool_steps = sum(1 for step in self.steps.values() if step.get('type') == 'tool')

        print(f"总步骤数: {total_steps}")
        print(f"工具步骤: {tool_steps}")
        print(f"执行层数: {num_layers}")
        print(f"最大并行度: {max_parallelism}")
        print(f"平均并行度: {avg_parallelism:.2f}")

        # 复杂度评分
        complexity_score = 0

        if total_steps > 10:
            complexity_score += 2
            print(f"\n复杂度因素:")
            print(f"  ✓ 步骤数较多 (>{10}): +2")

        if max_parallelism > 2:
            complexity_score += 2
            print(f"  ✓ 并行度较高 (>{2}): +2")

        if num_layers > 5:
            complexity_score += 1
            print(f"  ✓ 执行层次较深 (>{5}): +1")

        # 检查是否有扇出-扇入
        fanout_count = sum(1 for deps in [{'out_degree': len(self.connections[sid])}
                                          for sid in self.steps.keys()]
                          if deps['out_degree'] > 1)
        if fanout_count > 0:
            complexity_score += 1
            print(f"  ✓ 存在扇出模式: +1")

        print(f"\n总复杂度评分: {complexity_score}/6")

        if complexity_score >= 5:
            level = "非常复杂"
        elif complexity_score >= 3:
            level = "复杂"
        elif complexity_score >= 1:
            level = "中等"
        else:
            level = "简单"

        print(f"复杂度等级: {level}")
        print()

    def generate_aws_batch_mapping(self, layers: List[Set[str]]):
        """生成AWS Batch执行计划"""
        print("="*80)
        print("AWS Batch 执行计划")
        print("="*80)

        print("如果在AWS Batch上执行这个workflow，需要:")
        print()

        total_jobs = len(self.steps)
        print(f"1. 创建 {total_jobs} 个 AWS Batch Job Definitions")
        print(f"   - 每个Galaxy tool对应一个Docker容器")
        print(f"   - 需要为每个tool准备对应的容器镜像")
        print()

        print(f"2. 提交 {len(layers)} 批次的作业")
        for i, layer in enumerate(layers):
            print(f"   Layer {i}: {len(layer)} 个作业可以并行提交")
        print()

        max_parallel = max(len(layer) for layer in layers)
        print(f"3. 计算资源需求")
        print(f"   - 峰值并行作业数: {max_parallel}")
        print(f"   - 建议 Compute Environment maxvCpus >= {max_parallel * 2}")
        print(f"   - 如果 minvCpus=0，首次执行可能需要 {max_parallel} 次冷启动")
        print()

        # 依赖关系复杂度
        total_dependencies = sum(len(self.reverse_connections[sid])
                                for sid in self.steps.keys())
        print(f"4. 依赖关系管理")
        print(f"   - 总依赖边数: {total_dependencies}")
        print(f"   - 需要使用AWS Batch的依赖类型: SEQUENTIAL 和 N_TO_N")
        print()

        print(f"5. 数据传输")
        print(f"   - S3中间数据传输次数: 约 {total_dependencies} 次")
        print(f"   - 需要确保每个容器都有S3访问权限 (BatchJobRole)")
        print()

    def run_full_analysis(self):
        """运行完整分析"""
        self.analyze_basic_info()
        self.analyze_step_types()
        step_deps = self.analyze_dependencies()
        self.detect_parallel_patterns(step_deps)
        layers = self.compute_execution_layers(step_deps)
        self.estimate_complexity(layers)
        self.generate_aws_batch_mapping(layers)


def main():
    """主函数"""
    print("\n" + "="*80)
    print("真实 Galaxy Workflow 复杂度分析")
    print("="*80)
    print()

    if not WORKFLOW_FILE.exists():
        print(f"❌ Workflow文件不存在: {WORKFLOW_FILE}")
        return 1

    print(f"正在分析: {WORKFLOW_FILE.name}\n")

    # 加载workflow
    with open(WORKFLOW_FILE, 'r') as f:
        workflow_data = json.load(f)

    # 分析
    analyzer = WorkflowAnalyzer(workflow_data)
    analyzer.run_full_analysis()

    print("="*80)
    print("分析完成")
    print("="*80)
    print()
    print("下一步:")
    print("  1. 如果要在AWS Batch上测试这个workflow，需要:")
    print("     - 为每个tool准备Docker镜像")
    print("     - 准备测试输入数据")
    print("     - 配置工具参数映射")
    print()
    print("  2. 建议先用简化版本测试DAG执行逻辑:")
    print("     - 用简单的bash命令替代真实工具")
    print("     - 保持相同的依赖关系结构")
    print("     - 验证并行执行和依赖管理")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
