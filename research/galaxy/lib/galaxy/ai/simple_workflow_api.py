
from fastapi import HTTPException
from pydantic import BaseModel
from typing import Dict, Any, Optional, List
import uuid
import json
import logging

log = logging.getLogger(__name__)

class SimpleAIRequestModel(BaseModel):
    request_text: str
    context: Optional[Dict[str, Any]] = None

def create_simple_workflow_preview(request: SimpleAIRequestModel) -> Dict[str, Any]:
    """创建简化的workflow预览"""
    
    try:
        # 根据请求类型生成不同的workflow模板
        request_lower = request.request_text.lower()
        
        if 'rna-seq' in request_lower or 'rna seq' in request_lower:
            template = {
                "name": "RNA-seq Analysis Workflow",
                "description": "Complete RNA-seq analysis pipeline including quality control, alignment, and differential expression analysis",
                "steps": [
                    {"name": "FastQC", "description": "Quality control of raw reads"},
                    {"name": "Trimmomatic", "description": "Adapter trimming and quality filtering"}, 
                    {"name": "HISAT2", "description": "Read alignment to reference genome"},
                    {"name": "featureCounts", "description": "Gene expression quantification"},
                    {"name": "DESeq2", "description": "Differential expression analysis"}
                ],
                "tags": ["rna-seq", "genomics", "differential-expression"]
            }
        elif 'variant' in request_lower or 'snp' in request_lower:
            template = {
                "name": "Variant Calling Workflow",
                "description": "Genomic variant calling pipeline for SNP and indel detection",
                "steps": [
                    {"name": "FastQC", "description": "Quality control"},
                    {"name": "BWA", "description": "Read alignment"},
                    {"name": "GATK HaplotypeCaller", "description": "Variant calling"},
                    {"name": "GATK VariantFiltration", "description": "Variant filtering"},
                    {"name": "SnpEff", "description": "Variant annotation"}
                ],
                "tags": ["variant-calling", "genomics", "snp"]
            }
        elif 'assembly' in request_lower:
            template = {
                "name": "Genome Assembly Workflow", 
                "description": "De novo genome assembly pipeline",
                "steps": [
                    {"name": "FastQC", "description": "Quality assessment"},
                    {"name": "SPAdes", "description": "Genome assembly"},
                    {"name": "QUAST", "description": "Assembly quality assessment"},
                    {"name": "BUSCO", "description": "Completeness assessment"}
                ],
                "tags": ["assembly", "genomics", "de-novo"]
            }
        elif 'quality' in request_lower or 'qc' in request_lower:
            template = {
                "name": "Quality Control Workflow",
                "description": "Comprehensive quality control and preprocessing pipeline",
                "steps": [
                    {"name": "FastQC", "description": "Initial quality assessment"},
                    {"name": "MultiQC", "description": "Aggregate QC reporting"},
                    {"name": "Trimmomatic", "description": "Quality and adapter trimming"}
                ],
                "tags": ["quality-control", "preprocessing"]
            }
        else:
            # 通用模板
            template = {
                "name": "Custom Analysis Workflow",
                "description": f"Custom workflow for: {request.request_text}",
                "steps": [
                    {"name": "Data Input", "description": "Load input data"},
                    {"name": "Quality Control", "description": "Data quality assessment"},
                    {"name": "Analysis", "description": "Main analysis step"},
                    {"name": "Results Export", "description": "Export results"}
                ],
                "tags": ["custom", "analysis"]
            }
        
        workflow_id = str(uuid.uuid4())[:8]
        
        return {
            "workflow_id": workflow_id,
            "workflow_name": template["name"],
            "message": f"✨ Generated workflow preview: '{template['name']}'",
            "workflow_template": {
                "name": template["name"],
                "description": template["description"],
                "steps": len(template["steps"]),
                "step_details": template["steps"],
                "tags": template["tags"]
            },
            "note": "🔑 This is a preview. To save workflows, please log in to Galaxy",
            "status": "preview_success",
            "number_of_steps": len(template["steps"]),
            "preview": True,
            "login_url": "/login",
            "method": "Simplified Template-based Generation"
        }
        
    except Exception as e:
        log.error(f"Error creating workflow preview: {e}")
        raise HTTPException(status_code=500, detail=f"Error creating preview: {str(e)}")

# 导出函数供其他模块使用
__all__ = ['create_simple_workflow_preview', 'SimpleAIRequestModel']
