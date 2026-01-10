#!/usr/bin/env python3
"""
RAG Workflow数据加载器

专门用于加载和管理951个workflow数据，提供简单的RAG功能支持
"""

import json
import os
import re
import logging
from typing import Dict, List, Tuple, Any, Optional
from dataclasses import dataclass, field
from pathlib import Path
import uuid

log = logging.getLogger(__name__)

@dataclass
class WorkflowData:
    """Workflow数据结构"""
    workflow_id: str
    name: str
    description: str
    tags: List[str]
    annotations: List[str]
    number_of_steps: int
    tools: List[str]
    create_time: str
    owner: str
    similarity_score: float = 0.0
    _raw_data: Optional[Dict[str, Any]] = field(default=None)

class SimpleRAGEngine:
    """简化的RAG引擎，专门处理workflow相似度匹配"""
    
    def __init__(self, data_path: str):
        # 如果路径已经指向workflows目录，则直接使用
        if data_path.endswith('workflows'):
            self.data_path = Path(data_path)
        else:
            self.data_path = Path(data_path) / "workflows"
        self.workflows: Dict[str, WorkflowData] = {}
        self.keyword_weights = self._init_keyword_weights()
        self.load_all_workflows()
    
    def _init_keyword_weights(self) -> Dict[str, float]:
        """初始化关键词权重"""
        return {
            # RNA-seq相关
            'rna-seq': 3.0, 'rna_seq': 3.0, 'rnaseq': 3.0, 'rna': 2.5,
            'expression': 2.0, 'differential': 2.0, 'deseq2': 2.5,
            'hisat2': 2.0, 'star': 2.0, 'featurecounts': 2.0,
            
            # 基因组组装
            'assembly': 3.0, 'genome': 2.5, 'contig': 2.0, 'scaffold': 2.0,
            'spades': 2.5, 'velvet': 2.0, 'abyss': 2.0, 'canu': 2.0,
            'hifiasm': 2.5, 'flye': 2.0, 'miniasm': 1.8,
            
            # 变异检测
            'variant': 3.0, 'snp': 2.5, 'indel': 2.0, 'mutation': 2.0,
            'gatk': 2.5, 'haplotypecaller': 2.5, 'freebayes': 2.0,
            'samtools': 1.8, 'bcftools': 1.8, 'varscan': 1.8,
            
            # 质量控制
            'quality': 2.0, 'qc': 2.0, 'fastqc': 2.5, 'trimmomatic': 2.0,
            'cutadapt': 1.8, 'multiqc': 1.8, 'trim': 1.5,
            
            # 比对
            'alignment': 2.0, 'mapping': 2.0, 'bwa': 2.0, 'bowtie': 1.8,
            'minimap2': 2.0, 'blast': 1.8,
            
            # 其他
            'phylogenetic': 1.8, 'annotation': 1.5, 'metagenomics': 2.0,
            'chip-seq': 2.0, 'chipseq': 2.0, 'peak': 1.5, 'bacterial': 1.8
        }
    
    def extract_tools_from_workflow(self, workflow_json: Dict) -> List[str]:
        """从workflow JSON中提取工具列表"""
        tools = set()
        
        try:
            # 从steps中提取tool_id
            if 'steps' in workflow_json:
                for step_id, step in workflow_json['steps'].items():
                    if isinstance(step, dict) and 'tool_id' in step and step['tool_id']:
                        tool_name = step['tool_id'].split('/')[-1].lower()
                        tools.add(tool_name)
            
            # 从名称和描述中提取工具名
            text = f"{workflow_json.get('name', '')} {workflow_json.get('annotation', '')}".lower()
            
            common_tools = [
                'fastqc', 'trimmomatic', 'cutadapt', 'hisat2', 'star', 'bwa', 'bowtie2',
                'samtools', 'gatk', 'freebayes', 'deseq2', 'featurecounts', 'htseq',
                'spades', 'velvet', 'canu', 'flye', 'blast', 'diamond', 'multiqc',
                'picard', 'bcftools', 'haplotypecaller', 'varscan', 'snpeff'
            ]
            
            for tool in common_tools:
                if tool in text:
                    tools.add(tool)
        
        except Exception as e:
            log.warning(f"Error extracting tools: {e}")
        
        return list(tools)
    
    def load_all_workflows(self):
        """加载所有workflow数据"""
        if not self.data_path.exists():
            log.error(f"Workflows directory not found: {self.data_path}")
            return
        
        log.info(f"Loading workflows from {self.data_path}")
        
        loaded_count = 0
        for workflow_file in self.data_path.glob("workflow_*.json"):
            try:
                with open(workflow_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                metadata = data.get('metadata', {})
                workflow_json = data.get('workflow_json', {})
                
                # 提取工具列表
                tools = self.extract_tools_from_workflow(workflow_json)
                
                workflow_data = WorkflowData(
                    workflow_id=data.get('workflow_id', ''),
                    name=metadata.get('name', ''),
                    description=workflow_json.get('annotation', ''),
                    tags=[tag for tag in metadata.get('tags', []) if tag],
                    annotations=metadata.get('annotations', []),
                    number_of_steps=metadata.get('number_of_steps', 0),
                    tools=tools,
                    create_time=metadata.get('create_time', ''),
                    owner=metadata.get('owner', ''),
                    _raw_data=data  # 保存原始数据包括workflow_json
                )
                
                self.workflows[workflow_data.workflow_id] = workflow_data
                loaded_count += 1
                
            except Exception as e:
                log.warning(f"Error loading workflow {workflow_file}: {e}")
        
        log.info(f"Successfully loaded {loaded_count} workflows")
    
    def compute_similarity(self, user_request: str, workflow: WorkflowData) -> float:
        """计算用户请求和workflow的相似度"""
        similarity_score = 0.0
        user_text = user_request.lower()
        
        # 构建workflow的文本表示
        workflow_text_parts = [
            workflow.name,
            workflow.description,
            ' '.join(workflow.annotations),
            ' '.join(workflow.tags)
        ]
        workflow_text = ' '.join(filter(None, workflow_text_parts)).lower()
        
        # 1. 关键词匹配
        for keyword, weight in self.keyword_weights.items():
            if keyword in user_text and keyword in workflow_text:
                similarity_score += weight
        
        # 2. 工具匹配
        for tool in workflow.tools:
            if tool.lower() in user_text:
                similarity_score += 2.0
        
        # 3. 标签匹配
        for tag in workflow.tags:
            tag_lower = tag.lower()
            if tag_lower in user_text:
                similarity_score += 1.5
        
        # 4. 直接文本匹配
        user_words = set(user_text.split())
        workflow_words = set(workflow_text.split())
        common_words = user_words.intersection(workflow_words)
        
        # 给重要的词更高权重
        important_words = {'rna', 'seq', 'variant', 'assembly', 'quality', 'genome', 'analysis'}
        for word in common_words:
            if word in important_words:
                similarity_score += 1.0
            elif len(word) > 3:  # 忽略太短的词
                similarity_score += 0.3
        
        # 5. 名称相似度奖励
        if any(word in workflow.name.lower() for word in user_text.split() if len(word) > 3):
            similarity_score += 2.0
        
        # 6. 步骤数量调整（避免过于复杂的workflow）
        if workflow.number_of_steps > 50:
            similarity_score *= 0.9
        elif workflow.number_of_steps > 100:
            similarity_score *= 0.7
        
        return similarity_score
    
    def find_similar_workflows(self, user_request: str, top_k: int = 5) -> List[WorkflowData]:
        """找到与用户请求最相似的workflows"""
        if not self.workflows:
            log.warning("No workflows loaded")
            return []
        
        # 计算所有workflow的相似度
        scored_workflows = []
        for workflow in self.workflows.values():
            score = self.compute_similarity(user_request, workflow)
            if score > 0:  # 只保留有相关性的结果
                workflow_copy = workflow
                workflow_copy.similarity_score = score
                scored_workflows.append(workflow_copy)
        
        # 按相似度排序并返回top_k
        scored_workflows.sort(key=lambda x: x.similarity_score, reverse=True)
        return scored_workflows[:top_k]
    
    def get_stats(self) -> Dict[str, Any]:
        """获取统计信息"""
        if not self.workflows:
            return {"total_workflows": 0}
        
        # 统计标签
        all_tags = []
        for workflow in self.workflows.values():
            all_tags.extend(workflow.tags)
        
        tag_counts = {}
        for tag in all_tags:
            tag_counts[tag] = tag_counts.get(tag, 0) + 1
        
        # 统计工具
        all_tools = []
        for workflow in self.workflows.values():
            all_tools.extend(workflow.tools)
        
        tool_counts = {}
        for tool in all_tools:
            tool_counts[tool] = tool_counts.get(tool, 0) + 1
        
        return {
            "total_workflows": len(self.workflows),
            "avg_steps": sum(w.number_of_steps for w in self.workflows.values()) / len(self.workflows),
            "top_tags": sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)[:10],
            "top_tools": sorted(tool_counts.items(), key=lambda x: x[1], reverse=True)[:10],
        }

class RAGWorkflowRecommender:
    """RAG workflow推荐器，基于SimpleRAGEngine"""
    
    def __init__(self, data_path: str):
        self.rag_engine = SimpleRAGEngine(data_path)
        log.info(f"RAG Workflow Recommender initialized with {len(self.rag_engine.workflows)} workflows")
    
    def get_workflow_recommendations(self, user_request: str, max_recommendations: int = 5) -> Dict[str, Any]:
        """获取workflow推荐"""
        try:
            # 查找相似的workflows
            similar_workflows = self.rag_engine.find_similar_workflows(user_request, top_k=max_recommendations)
            
            if not similar_workflows:
                return {
                    "status": "no_matches",
                    "message": "No similar workflows found",
                    "recommendations": [],
                    "total_searched": len(self.rag_engine.workflows)
                }
            
            # 构建推荐结果
            recommendations = []
            for workflow in similar_workflows:
                rec_data = {
                    "workflow_id": workflow.workflow_id,
                    "name": workflow.name,
                    "description": workflow.description[:200] + "..." if len(workflow.description) > 200 else workflow.description,
                    "tags": workflow.tags,
                    "tools": workflow.tools[:5],  # 最多显示5个工具
                    "steps": workflow.number_of_steps,
                    "owner": workflow.owner,
                    "similarity_score": round(workflow.similarity_score, 2),
                    "create_time": workflow.create_time
                }
                
                # 如果有原始数据，包含workflow_json
                if hasattr(workflow, '_raw_data') and workflow._raw_data:
                    rec_data["workflow_json"] = workflow._raw_data.get("workflow_json", {})
                
                recommendations.append(rec_data)
            
            return {
                "status": "success",
                "message": f"Found {len(similar_workflows)} similar workflows",
                "recommendations": recommendations,
                "total_searched": len(self.rag_engine.workflows),
                "search_method": "RAG-based similarity matching"
            }
            
        except Exception as e:
            log.error(f"Error getting workflow recommendations: {e}")
            return {
                "status": "error",
                "message": f"Error: {str(e)}",
                "recommendations": [],
                "total_searched": 0
            }
    
    def generate_workflow_preview(self, user_request: str) -> Dict[str, Any]:
        """基于RAG生成workflow预览"""
        try:
            # 获取推荐
            recommendations = self.get_workflow_recommendations(user_request, max_recommendations=3)
            
            if recommendations["status"] != "success" or not recommendations["recommendations"]:
                return self._generate_fallback_preview(user_request)
            
            # 使用最佳匹配生成预览
            best_match = recommendations["recommendations"][0]
            
            # 生成预览workflow
            workflow_name = self._generate_workflow_name(user_request, best_match)
            workflow_steps = self._generate_workflow_steps(user_request, recommendations["recommendations"][:3])
            workflow_tags = self._generate_workflow_tags(user_request, recommendations["recommendations"][:3])
            
            workflow_id = str(uuid.uuid4())[:8]
            
            return {
                "workflow_id": workflow_id,
                "workflow_name": workflow_name,
                "message": f"✨ RAG-based workflow generated from {len(recommendations['recommendations'])} similar community workflows",
                "workflow_template": {
                    "name": workflow_name,
                    "description": f"Workflow generated for: {user_request}. Based on community workflow: {best_match['name']} (similarity: {best_match['similarity_score']})",
                    "steps": len(workflow_steps),
                    "step_details": workflow_steps,
                    "tags": workflow_tags,
                    "based_on": {
                        "template": best_match["name"],
                        "similarity": best_match["similarity_score"],
                        "owner": best_match["owner"]
                    }
                },
                "similar_workflows": recommendations["recommendations"][:3],
                "status": "rag_success",
                "method": "RAG-based Generation with 951 Community Workflows",
                "data_source": f"{recommendations['total_searched']} Galaxy community workflows"
            }
            
        except Exception as e:
            log.error(f"Error generating RAG workflow preview: {e}")
            return self._generate_fallback_preview(user_request)
    
    def _generate_workflow_name(self, user_request: str, best_match: Dict) -> str:
        """生成workflow名称，优先使用最佳匹配的workflow名称"""
        # 优先使用最佳匹配workflow的名称
        base_name = best_match["name"]
        
        # 如果名称太长，进行智能截断
        if len(base_name) > 60:
            # 尝试在合适的位置截断
            truncated = base_name[:57] + "..."
            return f"AI Generated: {truncated}"
        
        # 如果名称包含版本信息，可以考虑清理
        clean_name = base_name
        if "(release" in clean_name.lower():
            clean_name = clean_name.split("(release")[0].strip()
        
        return f"AI Generated: {clean_name}"
    
    def _generate_workflow_steps(self, user_request: str, top_matches: List[Dict]) -> List[Dict[str, str]]:
        """基于匹配的workflows生成步骤，更多使用真实workflow数据"""
        steps = []
        
        # 从最佳匹配的workflow中提取工具信息
        if top_matches:
            best_match = top_matches[0]
            tools_used = best_match.get("tools", [])
            
            # 使用真实workflow的工具来构建步骤
            for i, tool in enumerate(tools_used[:6]):  # 最多6个步骤
                step_num = i + 1
                # 清理工具名称，移除版本号
                clean_tool_name = tool.split('+')[0].split('/')[0]
                steps.append({
                    "name": clean_tool_name.title(),
                    "description": f"Step {step_num}: Analysis using {clean_tool_name}",
                    "tool_id": tool
                })
            
            # 如果步骤太少，添加一些通用步骤
            if len(steps) < 3:
                steps.extend([
                    {"name": "Data Processing", "description": "Process and prepare input data"},
                    {"name": "Analysis", "description": "Perform core analysis"},
                    {"name": "Results Generation", "description": "Generate output files and reports"}
                ])
        else:
            # 如果没有匹配的workflow，使用通用步骤
            steps = [
                {"name": "Data Input", "description": "Import and validate input data"},
                {"name": "Quality Control", "description": "Assess data quality"},
                {"name": "Analysis", "description": "Perform requested analysis"},
                {"name": "Results", "description": "Generate analysis results"}
            ]
            
            if len(steps) < 4:
                steps.append({"name": "Results Export", "description": "Export and format results"})
        
        return steps
    
    def _generate_workflow_tags(self, user_request: str, top_matches: List[Dict]) -> List[str]:
        """生成workflow标签"""
        tags = set()
        request_lower = user_request.lower()
        
        # 基于用户请求添加标签
        if 'rna' in request_lower:
            tags.update(['rna-seq', 'genomics', 'expression'])
        if 'variant' in request_lower or 'snp' in request_lower:
            tags.update(['variant-calling', 'genomics', 'snp'])
        if 'assembly' in request_lower:
            tags.update(['assembly', 'genomics', 'de-novo'])
        if 'quality' in request_lower:
            tags.update(['quality-control', 'preprocessing'])
        
        # 从匹配的workflows中提取标签
        for match in top_matches:
            match_tags = match.get("tags", [])
            for tag in match_tags[:2]:  # 每个match最多取2个标签
                if tag and len(tag) > 2:
                    tags.add(tag.lower())
        
        # 添加RAG标签
        tags.update(['rag-generated', 'community-based'])
        
        return list(tags)[:8]  # 最多8个标签
    
    def _generate_fallback_preview(self, user_request: str) -> Dict[str, Any]:
        """生成备用预览"""
        workflow_id = str(uuid.uuid4())[:8]
        
        return {
            "workflow_id": workflow_id,
            "workflow_name": "Custom Analysis Workflow",
            "message": f"✨ Generated custom workflow for: {user_request}",
            "workflow_template": {
                "name": "Custom Analysis Workflow",
                "description": f"Custom workflow generated for: {user_request}",
                "steps": 4,
                "step_details": [
                    {"name": "Data Input", "description": "Load and validate input data"},
                    {"name": "Quality Control", "description": "Assess data quality"},
                    {"name": "Main Analysis", "description": "Primary analysis step"},
                    {"name": "Results Export", "description": "Export results"}
                ],
                "tags": ["custom", "analysis", "rag-generated"]
            },
            "status": "fallback_success",
            "method": "Fallback Template (No Similar Workflows Found)",
            "data_source": f"{len(self.rag_engine.workflows)} workflows searched"
        }
    
    def load_workflow_by_id(self, workflow_id: str) -> Dict[str, Any]:
        """根据workflow_id加载特定的workflow数据"""
        try:
            # 在内存中查找workflow
            for workflow in self.rag_engine.workflows:
                if workflow.workflow_id == workflow_id:
                    return {
                        "workflow_id": workflow.workflow_id,
                        "name": workflow.name,
                        "description": workflow.description,
                        "tags": workflow.tags,
                        "tools": workflow.tools,
                        "steps": workflow.number_of_steps,
                        "owner": workflow.owner,
                        "similarity_score": 15.0,  # Perfect match since it's specifically requested
                        "workflow_json": getattr(workflow, '_raw_data', {}).get('workflow_json', {})
                    }
            
            # 如果内存中没有，尝试从文件加载
            workflow_file = self.rag_engine.data_path / f"workflow_{workflow_id}.json"
            if workflow_file.exists():
                with open(workflow_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                
                metadata = data.get('metadata', {})
                workflow_json = data.get('workflow_json', {})
                
                # 提取工具列表
                tools = self.rag_engine.extract_tools_from_workflow(workflow_json)
                
                return {
                    "workflow_id": workflow_id,
                    "name": metadata.get('name', 'Unknown Workflow'),
                    "description": metadata.get('annotations', [''])[0] if metadata.get('annotations') else '',
                    "tags": metadata.get('tags', []),
                    "tools": tools,
                    "steps": metadata.get('number_of_steps', 0),
                    "owner": metadata.get('owner', 'Unknown'),
                    "similarity_score": 15.0,  # Perfect match since it's specifically requested
                    "workflow_json": workflow_json
                }
            
            return None
            
        except Exception as e:
            log.error(f"Error loading workflow by ID {workflow_id}: {e}")
            return None
    
    def get_stats(self) -> Dict[str, Any]:
        """获取系统统计信息"""
        return self.rag_engine.get_stats()

# 导出模块
__all__ = ['RAGWorkflowRecommender', 'SimpleRAGEngine', 'WorkflowData']