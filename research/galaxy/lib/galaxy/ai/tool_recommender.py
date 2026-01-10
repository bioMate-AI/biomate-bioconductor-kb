"""
Intelligent Tool Recommendation System for Galaxy Workflows

⚠️ **NEW FILE** - This is a completely new file that provides intelligent tool
recommendations for workflow generation. It does not modify any existing files.

Safe to add - does not modify existing functionality.
"""

import logging
from typing import List, Dict, Any

log = logging.getLogger(__name__)

class ToolRecommender:
    """Recommends tools based on user requirements and context"""
    
    def __init__(self, toolbox):
        self.toolbox = toolbox
        self.tool_categories = self._build_tool_categories()
    
    def recommend_tools(self, requirements: Dict[str, Any]) -> List[Dict]:
        """Recommend tools based on user requirements"""
        
        recommendations = []
        analysis_type = requirements.get('analysis_type', '').lower()
        
        # Get tools by analysis type
        primary_tools = self._get_tools_by_analysis_type(analysis_type)
        
        for tool_name in primary_tools[:5]:  # Top 5 recommendations
            tool_ids = self._find_tools_by_name(tool_name)
            for tool_id in tool_ids:
                tool = self.toolbox.get_tool(tool_id)
                if tool:
                    recommendations.append({
                        'tool_id': tool_id,
                        'name': tool.name,
                        'description': tool.description or '',
                        'confidence': 0.8
                    })
                    break  # Take first match
        
        return recommendations
    
    def _build_tool_categories(self) -> Dict[str, List[str]]:
        """Build tool categories mapping"""
        return {
            'sequencing': ['fastqc', 'trimmomatic', 'cutadapt'],
            'alignment': ['bwa', 'bowtie2', 'hisat2'],
            'variant_calling': ['gatk', 'freebayes', 'bcftools'],
            'assembly': ['spades', 'velvet', 'canu']
        }
    
    def _get_tools_by_analysis_type(self, analysis_type: str) -> List[str]:
        """Get tools suitable for specific analysis type"""
        
        analysis_map = {
            'rna-seq': ['hisat2', 'stringtie', 'deseq2'],
            'variant_calling': ['bwa', 'gatk', 'freebayes'],
            'assembly': ['spades', 'velvet', 'canu'],
            'quality_control': ['fastqc', 'trimmomatic']
        }
        
        return analysis_map.get(analysis_type, [])
    
    def _find_tools_by_name(self, tool_name: str) -> List[str]:
        """Find tools matching the given name"""
        matching_tools = []
        
        for tool_id in self.toolbox.get_tool_ids():
            tool = self.toolbox.get_tool(tool_id)
            if tool and tool_name.lower() in tool.name.lower():
                matching_tools.append(tool_id)
        
        return matching_tools