"""
Enhanced Workflow Generator with RAG and Template-based Approach

Combines human-verified templates with RAG-based tool discovery for
high-quality workflow generation.
"""

import json
import logging
import uuid
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime

from .workflow_templates import WorkflowTemplateLibrary
from .galaxy_tool_rag import GalaxyToolRAG
from .tool_auto_installer import ToolAutoInstaller
from .types import WorkflowTemplate, UserRequest
from .config import AIConfig
from .llm_client import LLMClient

log = logging.getLogger(__name__)


class EnhancedWorkflowGenerator:
    """Enhanced workflow generator using templates and RAG."""
    
    def __init__(self, config: AIConfig, galaxy_app=None, galaxy_root=None):
        self.config = config
        self.llm_client = LLMClient(config)
        self.template_library = WorkflowTemplateLibrary()
        self.tool_rag = GalaxyToolRAG(galaxy_app)

        # Auto-installer for missing tools
        self.tool_installer = None
        if galaxy_root:
            try:
                self.tool_installer = ToolAutoInstaller(galaxy_root)
                log.info("Tool auto-installer initialized")
            except Exception as e:
                log.warning(f"Could not initialize tool auto-installer: {e}")

        # Generation strategies
        self.strategies = {
            "template_based": self._generate_from_template,
            "rag_assisted": self._generate_with_rag,
            "hybrid": self._generate_hybrid
        }
    
    def generate_workflow(self, user_request: UserRequest, auto_install_tools: bool = True) -> Dict[str, Any]:
        """Generate workflow using the best available strategy."""

        # Step 1: Try to find matching templates
        template_matches = self.template_library.search_templates(
            user_request.request_text,
            user_request.request_text
        )

        # Step 2: Determine generation strategy
        if template_matches and template_matches[0]["relevance_score"] >= 15:
            # High confidence template match
            strategy = "template_based"
            log.info(f"Using template-based strategy for: {user_request.request_text}")
        elif template_matches and template_matches[0]["relevance_score"] >= 8:
            # Medium confidence - use hybrid approach
            strategy = "hybrid"
            log.info(f"Using hybrid strategy for: {user_request.request_text}")
        else:
            # Low confidence - use RAG-assisted generation
            strategy = "rag_assisted"
            log.info(f"Using RAG-assisted strategy for: {user_request.request_text}")

        # Step 3: Generate workflow
        generation_method = self.strategies[strategy]
        workflow_result = generation_method(user_request, template_matches)

        # Step 4: Auto-install missing tools (if enabled and installer available)
        if auto_install_tools and self.tool_installer and "workflow" in workflow_result:
            try:
                success, msg, failed = self.tool_installer.auto_install_workflow_tools(
                    workflow_result["workflow"]
                )
                workflow_result["tool_installation"] = {
                    "success": success,
                    "message": msg,
                    "failed_tools": failed
                }
                if success:
                    log.info(f"Auto-installed tools for workflow: {msg}")
                else:
                    log.warning(f"Tool installation had issues: {msg}")
            except Exception as e:
                log.error(f"Tool auto-installation failed: {e}")
                workflow_result["tool_installation"] = {
                    "success": False,
                    "message": f"Installation error: {str(e)}",
                    "failed_tools": []
                }

        # Step 5: Add metadata
        workflow_result["generation_strategy"] = strategy
        workflow_result["generation_timestamp"] = datetime.now().isoformat()
        workflow_result["template_matches"] = len(template_matches)

        return workflow_result
    
    def _generate_from_template(self, user_request: UserRequest, 
                               template_matches: List[Dict]) -> Dict[str, Any]:
        """Generate workflow directly from a template."""
        
        if not template_matches:
            return self._generate_with_rag(user_request, template_matches)
        
        best_template = template_matches[0]
        
        # Customize template based on user request
        customized_workflow = self._customize_template(best_template, user_request)
        
        return {
            "workflow": customized_workflow,
            "confidence": min(0.95, best_template["relevance_score"] / 20.0),
            "source": "template",
            "template_id": best_template.get("template_id"),
            "template_name": best_template.get("name"),
            "quality_level": "high",
            "validation_status": "template_verified"
        }
    
    def _generate_with_rag(self, user_request: UserRequest, 
                          template_matches: List[Dict]) -> Dict[str, Any]:
        """Generate workflow using RAG-based tool discovery."""
        
        # Extract data types and analysis goals from user request
        analysis_context = self._analyze_user_request(user_request)
        
        # Find relevant tools using RAG
        relevant_tools = self.tool_rag.search_tools(
            query=user_request.request_text,
            data_types=analysis_context.get("data_types", []),
            category=analysis_context.get("category"),
            limit=15
        )
        
        # Generate workflow structure using LLM with RAG context
        workflow_structure = self._llm_generate_workflow_structure(
            user_request, relevant_tools, analysis_context
        )
        
        # Validate and refine the workflow
        validated_workflow = self._validate_workflow_structure(workflow_structure, relevant_tools)
        
        return {
            "workflow": validated_workflow,
            "confidence": 0.7,  # Lower confidence for RAG-generated
            "source": "rag_generated",
            "available_tools": len(relevant_tools),
            "quality_level": "medium",
            "validation_status": "rag_generated"
        }
    
    def _generate_hybrid(self, user_request: UserRequest, 
                        template_matches: List[Dict]) -> Dict[str, Any]:
        """Generate workflow using template as base + RAG for customization."""
        
        best_template = template_matches[0]
        
        # Start with template
        base_workflow = self._customize_template(best_template, user_request)
        
        # Enhance with RAG-discovered tools
        analysis_context = self._analyze_user_request(user_request)
        additional_tools = self.tool_rag.search_tools(
            query=user_request.request_text,
            data_types=analysis_context.get("data_types", []),
            limit=10
        )
        
        # Use LLM to intelligently merge template with additional tools
        enhanced_workflow = self._enhance_template_with_rag(
            base_workflow, additional_tools, user_request
        )
        
        return {
            "workflow": enhanced_workflow,
            "confidence": 0.85,  # High confidence for hybrid
            "source": "hybrid",
            "template_id": best_template.get("template_id"),
            "additional_tools": len(additional_tools),
            "quality_level": "high",
            "validation_status": "template_enhanced"
        }
    
    def _customize_template(self, template: Dict[str, Any], 
                           user_request: UserRequest) -> Dict[str, Any]:
        """Customize a template based on user-specific requirements."""
        
        workflow = {
            "name": template["name"],
            "description": f"Customized {template['name']} for: {user_request.request_text}",
            "steps": [],
            "inputs": [],
            "outputs": [],
            "tags": template.get("keywords", []) + ["ai-generated", "template-based"]
        }
        
        # Convert template steps to Galaxy workflow format
        for step_info in template["workflow_steps"]:
            workflow_step = {
                "id": step_info["step"],
                "type": "tool",
                "tool_id": step_info["tool_id"],
                "annotation": step_info["description"],
                "input_connections": {},
                "inputs": {},
                "position": {"left": 200 + (step_info["step"] - 1) * 300, "top": 200},
                "tool_state": json.dumps(step_info.get("parameters", {})),
                "post_job_actions": {}
            }
            workflow["steps"].append(workflow_step)
        
        # Set up input and output definitions
        workflow["inputs"] = template.get("input_requirements", [])
        workflow["outputs"] = template.get("expected_outputs", [])
        
        return workflow
    
    def _analyze_user_request(self, user_request: UserRequest) -> Dict[str, Any]:
        """Analyze user request to extract context for tool discovery."""
        
        request_text = user_request.request_text.lower()
        
        # Detect data types
        data_types = []
        if "fastq" in request_text or "sequencing" in request_text:
            data_types.append("fastq")
        if "bam" in request_text or "aligned" in request_text:
            data_types.append("bam")
        if "vcf" in request_text or "variant" in request_text:
            data_types.append("vcf")
        if "fasta" in request_text or "genome" in request_text:
            data_types.append("fasta")
        
        # Detect analysis category
        category = None
        if any(term in request_text for term in ["rna-seq", "rna seq", "transcriptome", "expression"]):
            category = "rna_seq"
        elif any(term in request_text for term in ["variant", "snp", "mutation", "genotyping"]):
            category = "variant_calling"
        elif any(term in request_text for term in ["assembly", "assembl", "de novo"]):
            category = "assembly"
        elif any(term in request_text for term in ["quality", "qc", "fastqc"]):
            category = "quality_control"
        elif any(term in request_text for term in ["align", "mapping", "map"]):
            category = "alignment"
        
        return {
            "data_types": data_types,
            "category": category,
            "analysis_type": self._detect_analysis_type(request_text)
        }
    
    def _detect_analysis_type(self, request_text: str) -> str:
        """Detect the type of analysis from request text."""
        if any(term in request_text for term in ["differential", "de analysis", "compare"]):
            return "differential_analysis"
        elif any(term in request_text for term in ["annotation", "annotate", "functional"]):
            return "annotation"
        elif any(term in request_text for term in ["phylogen", "tree", "evolution"]):
            return "phylogenetics"
        elif any(term in request_text for term in ["metagen", "microbiome", "16s"]):
            return "metagenomics"
        else:
            return "standard"
    
    def _llm_generate_workflow_structure(self, user_request: UserRequest,
                                       relevant_tools: List[Dict], 
                                       analysis_context: Dict) -> Dict[str, Any]:
        """Use LLM to generate workflow structure with RAG context."""
        
        tools_context = "\n".join([
            f"- {tool['name']} ({tool['id']}): {tool['description']}"
            for tool in relevant_tools[:10]
        ])
        
        schema = {
            "type": "object",
            "properties": {
                "workflow": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "description": {"type": "string"},
                        "steps": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "step_number": {"type": "integer"},
                                    "tool_id": {"type": "string"},
                                    "tool_name": {"type": "string"},
                                    "description": {"type": "string"},
                                    "rationale": {"type": "string"}
                                }
                            }
                        }
                    }
                }
            }
        }
        
        prompt = f"""
        Create a bioinformatics workflow for the following request:
        
        User Request: "{user_request.request_text}"
        
        Analysis Context:
        - Data types: {analysis_context.get('data_types', [])}
        - Category: {analysis_context.get('category', 'unknown')}
        - Analysis type: {analysis_context.get('analysis_type', 'standard')}
        
        Available Galaxy Tools:
        {tools_context}
        
        Create a logical workflow with 3-7 steps that:
        1. Uses only tools from the available list above
        2. Follows bioinformatics best practices
        3. Has clear step-by-step progression
        4. Includes rationale for each tool choice
        
        Focus on quality, accuracy, and scientific validity.
        """
        
        try:
            response = self.llm_client.generate_structured(prompt, schema)
            return response.get("workflow", {})
        except Exception as e:
            log.error(f"LLM workflow generation failed: {e}")
            return self._fallback_workflow_structure(user_request, relevant_tools)
    
    def _fallback_workflow_structure(self, user_request: UserRequest,
                                   relevant_tools: List[Dict]) -> Dict[str, Any]:
        """Fallback workflow generation when LLM fails."""
        
        return {
            "name": "Basic Analysis Workflow",
            "description": f"Basic workflow for: {user_request.request_text}",
            "steps": [
                {
                    "step_number": 1,
                    "tool_id": relevant_tools[0]["id"] if relevant_tools else "fastqc",
                    "tool_name": relevant_tools[0]["name"] if relevant_tools else "FastQC",
                    "description": "Quality assessment",
                    "rationale": "First step in any analysis pipeline"
                }
            ]
        }
    
    def _validate_workflow_structure(self, workflow_structure: Dict[str, Any],
                                   available_tools: List[Dict]) -> Dict[str, Any]:
        """Validate and refine workflow structure."""
        
        # Ensure all tools exist in available tools
        available_tool_ids = {tool["id"] for tool in available_tools}
        
        validated_steps = []
        for step in workflow_structure.get("steps", []):
            tool_id = step.get("tool_id")
            if tool_id in available_tool_ids:
                validated_steps.append(step)
            else:
                # Try to find a similar tool
                tool_name = step.get("tool_name", "")
                alternative = self._find_alternative_tool(tool_name, available_tools)
                if alternative:
                    step["tool_id"] = alternative["id"]
                    step["tool_name"] = alternative["name"]
                    validated_steps.append(step)
        
        workflow_structure["steps"] = validated_steps
        return workflow_structure
    
    def _find_alternative_tool(self, tool_name: str, 
                             available_tools: List[Dict]) -> Optional[Dict]:
        """Find alternative tool when requested tool is not available."""
        
        tool_name_lower = tool_name.lower()
        
        for tool in available_tools:
            if tool_name_lower in tool["name"].lower():
                return tool
            if tool_name_lower in tool["description"].lower():
                return tool
        
        return None
    
    def _enhance_template_with_rag(self, base_workflow: Dict[str, Any],
                                 additional_tools: List[Dict],
                                 user_request: UserRequest) -> Dict[str, Any]:
        """Enhance template workflow with additional RAG-discovered tools."""
        
        # This is a simplified implementation
        # In practice, you'd use more sophisticated logic to integrate tools
        
        enhanced_workflow = base_workflow.copy()
        
        # Add note about enhancement
        enhanced_workflow["description"] += f" Enhanced with additional tools for: {user_request.request_text}"
        
        # Add "enhanced" tag
        if "tags" not in enhanced_workflow:
            enhanced_workflow["tags"] = []
        enhanced_workflow["tags"].append("rag-enhanced")
        
        return enhanced_workflow
    
    def get_workflow_recommendations(self, user_request: UserRequest) -> List[Dict[str, Any]]:
        """Get multiple workflow recommendations with different approaches."""
        
        recommendations = []
        
        # Get template matches
        template_matches = self.template_library.search_templates(
            user_request.request_text
        )
        
        # Add template-based recommendations
        for i, template in enumerate(template_matches[:3]):
            recommendation = {
                "type": "template",
                "name": template["name"],
                "description": template["description"],
                "confidence": min(0.95, template["relevance_score"] / 20.0),
                "estimated_time": template.get("estimated_time", "Unknown"),
                "difficulty": template.get("difficulty", "Unknown"),
                "template_id": template.get("template_id"),
                "validation_status": "verified"
            }
            recommendations.append(recommendation)
        
        # Add RAG-based recommendation if no good templates
        if not template_matches or template_matches[0]["relevance_score"] < 10:
            rag_recommendation = {
                "type": "custom",
                "name": "Custom Workflow",
                "description": f"Custom-built workflow for: {user_request.request_text}",
                "confidence": 0.7,
                "estimated_time": "Variable",
                "difficulty": "Depends on complexity",
                "validation_status": "ai_generated"
            }
            recommendations.append(rag_recommendation)
        
        return recommendations
    
    def export_to_galaxy_format(self, workflow_template: WorkflowTemplate) -> Dict[str, Any]:
        """Export workflow template to Galaxy's native workflow format."""
        
        galaxy_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': workflow_template.description,
            'format-version': '0.1',
            'name': workflow_template.name,
            'steps': {},
            'tags': workflow_template.tags,
            'uuid': str(uuid.uuid4()),
            'version': 1
        }
        
        # Convert steps to Galaxy format
        for step in workflow_template.steps:
            # Separate workflow inputs from step-to-step connections
            valid_connections = {}
            workflow_inputs = {}
            
            for input_name, connection in step.input_connections.items():
                if connection.get('id') is None:
                    # This is a workflow input - add to workflow inputs instead of connections
                    workflow_inputs[input_name] = {
                        'description': f"Input {connection.get('output_name', input_name)} for {step.annotation}",
                        'optional': False
                    }
                else:
                    # This is a valid step-to-step connection
                    valid_connections[input_name] = connection
            
            galaxy_workflow['steps'][str(step.step_id)] = {
                'id': step.step_id,
                'type': 'tool',
                'tool_id': step.tool_id,
                'tool_version': step.tool_version,
                'annotation': step.annotation,
                'input_connections': valid_connections,
                'inputs': workflow_inputs,
                'position': step.position,
                'post_job_actions': {},
                'tool_state': json.dumps(step.parameters)
            }
        
        return galaxy_workflow