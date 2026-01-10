"""
Task Decomposer for Galaxy AI Assistant

Breaks down complex research requests into manageable, executable tasks.
"""

import json
import re
import uuid
from typing import Dict, List, Any, Optional, Tuple
from .types import Task, TaskType, IntentType, UserRequest, DataType, TaskGraph
from .config import AIConfig
from .llm_client import LLMClient


class TaskDecomposer:
    """Decomposes complex research requests into structured tasks."""
    
    def __init__(self, config: AIConfig):
        self.config = config
        self.llm_client = LLMClient(config)
        
        # Predefined task templates for common workflows
        self.task_templates = {
            'rna_seq_analysis': [
                {
                    'name': 'Quality Control',
                    'task_type': TaskType.QUALITY_CONTROL,
                    'intent_type': IntentType.PROCESS,
                    'description': 'Assess quality of raw RNA-seq reads',
                    'input_types': ['fastq'],
                    'output_types': ['html', 'tabular']
                },
                {
                    'name': 'Read Trimming',
                    'task_type': TaskType.DATA_PROCESSING,
                    'intent_type': IntentType.FILTER,
                    'description': 'Trim low-quality bases and adapters',
                    'input_types': ['fastq'],
                    'output_types': ['fastq']
                },
                {
                    'name': 'Read Alignment',
                    'task_type': TaskType.GENOMICS,
                    'intent_type': IntentType.ALIGN,
                    'description': 'Align reads to reference genome',
                    'input_types': ['fastq', 'fasta'],
                    'output_types': ['bam']
                },
                {
                    'name': 'Count Features',
                    'task_type': TaskType.TRANSCRIPTOMICS,
                    'intent_type': IntentType.ANALYZE,
                    'description': 'Count reads mapping to genes',
                    'input_types': ['bam', 'gff'],
                    'output_types': ['tabular']
                },
                {
                    'name': 'Differential Expression',
                    'task_type': TaskType.TRANSCRIPTOMICS,
                    'intent_type': IntentType.COMPARE,
                    'description': 'Identify differentially expressed genes',
                    'input_types': ['tabular'],
                    'output_types': ['tabular']
                }
            ],
            'genome_assembly': [
                {
                    'name': 'Quality Control',
                    'task_type': TaskType.QUALITY_CONTROL,
                    'intent_type': IntentType.PROCESS,
                    'description': 'Assess quality of sequencing reads',
                    'input_types': ['fastq'],
                    'output_types': ['html']
                },
                {
                    'name': 'Read Preprocessing',
                    'task_type': TaskType.DATA_PROCESSING,
                    'intent_type': IntentType.FILTER,
                    'description': 'Clean and filter reads',
                    'input_types': ['fastq'],
                    'output_types': ['fastq']
                },
                {
                    'name': 'Genome Assembly',
                    'task_type': TaskType.ASSEMBLY,
                    'intent_type': IntentType.ASSEMBLE,
                    'description': 'Assemble genome from reads',
                    'input_types': ['fastq'],
                    'output_types': ['fasta']
                },
                {
                    'name': 'Assembly Assessment',
                    'task_type': TaskType.QUALITY_CONTROL,
                    'intent_type': IntentType.ANALYZE,
                    'description': 'Evaluate assembly quality',
                    'input_types': ['fasta'],
                    'output_types': ['tabular']
                }
            ],
            'variant_calling': [
                {
                    'name': 'Quality Control',
                    'task_type': TaskType.QUALITY_CONTROL,
                    'intent_type': IntentType.PROCESS,
                    'description': 'Check sequencing read quality',
                    'input_types': ['fastq'],
                    'output_types': ['html']
                },
                {
                    'name': 'Read Alignment',
                    'task_type': TaskType.GENOMICS,
                    'intent_type': IntentType.ALIGN,
                    'description': 'Align reads to reference',
                    'input_types': ['fastq', 'fasta'],
                    'output_types': ['bam']
                },
                {
                    'name': 'Variant Calling',
                    'task_type': TaskType.GENOMICS,
                    'intent_type': IntentType.ANALYZE,
                    'description': 'Call genetic variants',
                    'input_types': ['bam', 'fasta'],
                    'output_types': ['vcf']
                },
                {
                    'name': 'Variant Annotation',
                    'task_type': TaskType.ANNOTATION,
                    'intent_type': IntentType.ANNOTATE,
                    'description': 'Annotate variants with functional information',
                    'input_types': ['vcf'],
                    'output_types': ['tabular']
                }
            ]
        }
    
    def decompose_request(self, request: UserRequest, parsed_intent: Dict[str, Any]) -> List[Task]:
        """Decompose a user request into structured tasks."""
        
        # First try template-based decomposition
        template_tasks = self._try_template_decomposition(request, parsed_intent)
        if template_tasks:
            return template_tasks
        
        # Fall back to LLM-based decomposition
        return self._llm_decompose(request, parsed_intent)
    
    def _try_template_decomposition(self, request: UserRequest, parsed_intent: Dict[str, Any]) -> Optional[List[Task]]:
        """Try to use predefined templates for common workflows."""
        request_text = request.request_text.lower()
        
        # Check for RNA-seq workflow
        if any(term in request_text for term in ['rna-seq', 'rna seq', 'transcriptome', 'expression']):
            if any(term in request_text for term in ['differential', 'compare', 'expression analysis']):
                return self._create_tasks_from_template('rna_seq_analysis', parsed_intent)
        
        # Check for genome assembly workflow
        if any(term in request_text for term in ['assembly', 'assemble', 'de novo', 'genome assembly']):
            return self._create_tasks_from_template('genome_assembly', parsed_intent)
        
        # Check for variant calling workflow
        if any(term in request_text for term in ['variant', 'snp', 'mutation', 'variant calling']):
            return self._create_tasks_from_template('variant_calling', parsed_intent)
        
        return None
    
    def _create_tasks_from_template(self, template_name: str, parsed_intent: Dict[str, Any]) -> List[Task]:
        """Create tasks from a predefined template."""
        template = self.task_templates.get(template_name, [])
        tasks = []
        
        for i, task_template in enumerate(template):
            task_id = str(uuid.uuid4())
            
            # Create input and output data types
            input_data_types = [
                DataType(name=dt, extension=f".{dt}")
                for dt in task_template['input_types']
            ]
            output_data_types = [
                DataType(name=dt, extension=f".{dt}")
                for dt in task_template['output_types']
            ]
            
            # Determine dependencies
            dependencies = []
            if i > 0:
                dependencies.append(tasks[i-1].id)
            
            task = Task(
                id=task_id,
                name=task_template['name'],
                description=task_template['description'],
                task_type=task_template['task_type'],
                intent_type=task_template['intent_type'],
                input_data_types=input_data_types,
                output_data_types=output_data_types,
                estimated_duration=self._estimate_task_duration(task_template['task_type']),
                confidence=0.85,  # Template-based tasks have high confidence
                dependencies=dependencies
            )
            
            tasks.append(task)
        
        return tasks
    
    def _llm_decompose(self, request: UserRequest, parsed_intent: Dict[str, Any]) -> List[Task]:
        """Use LLM to decompose complex requests."""
        schema = {
            "type": "object",
            "properties": {
                "tasks": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "description": {"type": "string"},
                            "task_type": {"type": "string", "enum": [t.value for t in TaskType]},
                            "intent_type": {"type": "string", "enum": [i.value for i in IntentType]},
                            "input_types": {"type": "array", "items": {"type": "string"}},
                            "output_types": {"type": "array", "items": {"type": "string"}},
                            "estimated_minutes": {"type": "integer"},
                            "dependencies": {"type": "array", "items": {"type": "integer"}},
                            "parallel_with": {"type": "array", "items": {"type": "integer"}}
                        },
                        "required": ["name", "description", "task_type", "intent_type", "input_types", "output_types"]
                    }
                }
            },
            "required": ["tasks"]
        }
        
        prompt = f"""
        Decompose this bioinformatics research request into a sequence of executable tasks:
        
        Request: "{request.request_text}"
        
        Detected Intent: {parsed_intent['intent'].value}
        Detected Task Type: {parsed_intent['task_type'].value}
        Available Data Types: {[dt.name for dt in parsed_intent.get('data_types', [])]}
        Constraints: {parsed_intent.get('constraints', {})}
        
        Break this down into 3-8 specific, executable tasks that form a logical workflow.
        Each task should:
        1. Have a clear, specific objective
        2. Define input and output data types
        3. Be executable by bioinformatics tools
        4. Include estimated runtime in minutes
        5. Specify dependencies (which tasks must complete first)
        6. Identify tasks that can run in parallel
        
        Common bioinformatics data types: fastq, fasta, bam, sam, vcf, gff, bed, tabular, html
        
        Task types available: {[t.value for t in TaskType]}
        Intent types available: {[i.value for i in IntentType]}
        
        Consider standard bioinformatics workflows and best practices.
        """
        
        try:
            response_text = self.llm_client.generate_structured(prompt, schema)
            # Parse the JSON response
            response = self._parse_json_response(response_text)
            return self._parse_llm_tasks(response['tasks'])
        except Exception as e:
            print(f"LLM decomposition failed: {e}")
            # Fallback to simple single task
            return self._create_fallback_task(request, parsed_intent)

    def _parse_json_response(self, response_text: str) -> Dict[str, Any]:
        """Parse JSON response with error recovery."""

        # Check if response is empty or None
        if not response_text or not response_text.strip():
            raise ValueError("Empty or None response from LLM")

        # First try direct JSON parsing
        try:
            return json.loads(response_text.strip())
        except json.JSONDecodeError as original_error:
            print(f"Direct JSON parse failed: {original_error}")
            print(f"Response text (first 200 chars): {response_text[:200]}")

            # Try to extract JSON from markdown code blocks
            json_match = re.search(r'```(?:json)?\s*(\{.*?\})\s*```', response_text, re.DOTALL)
            if json_match:
                try:
                    return json.loads(json_match.group(1))
                except json.JSONDecodeError:
                    pass

            # Try to find JSON object in the text
            json_match = re.search(r'\{.*\}', response_text, re.DOTALL)
            if json_match:
                json_str = json_match.group()
                try:
                    return json.loads(json_str)
                except json.JSONDecodeError:
                    # Try to fix common JSON errors
                    fixed_json = self._fix_common_json_errors(json_str)
                    if fixed_json:
                        try:
                            return json.loads(fixed_json)
                        except json.JSONDecodeError:
                            pass

            raise ValueError(f"No valid JSON found in response. Original error: {original_error}")

    def _fix_common_json_errors(self, json_str: str) -> str:
        """Fix common JSON formatting errors."""
        # Remove trailing commas before closing brackets/braces
        json_str = re.sub(r',\s*([}\]])', r'\1', json_str)

        # Fix missing commas between array items (basic heuristic)
        json_str = re.sub(r'}\s*{', r'}, {', json_str)
        json_str = re.sub(r']\s*\[', r'], [', json_str)

        # Remove any trailing content after the main JSON object
        brace_count = 0
        for i, char in enumerate(json_str):
            if char == '{':
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0:
                    json_str = json_str[:i+1]
                    break

        return json_str

    def _parse_task_type(self, task_type_str: str) -> TaskType:
        """Parse task type string to TaskType enum with fallback handling."""
        task_type_str = task_type_str.lower().strip()

        # Direct mapping
        try:
            return TaskType(task_type_str)
        except ValueError:
            pass

        # Chinese to English mapping
        chinese_mapping = {
            '数据处理': TaskType.DATA_PROCESSING,
            '序列分析': TaskType.SEQUENCE_ANALYSIS,
            '基因组学': TaskType.GENOMICS,
            '蛋白质组学': TaskType.PROTEOMICS,
            '转录组学': TaskType.TRANSCRIPTOMICS,
            '质量控制': TaskType.QUALITY_CONTROL,
            '组装': TaskType.ASSEMBLY,
            '注释': TaskType.ANNOTATION,
            '比较分析': TaskType.COMPARATIVE_ANALYSIS,
            '可视化': TaskType.VISUALIZATION,
            '统计': TaskType.STATISTICS,
        }

        for chinese, enum_val in chinese_mapping.items():
            if chinese in task_type_str:
                return enum_val

        # English keyword mapping
        english_mapping = {
            'data': TaskType.DATA_PROCESSING,
            'sequence': TaskType.SEQUENCE_ANALYSIS,
            'genome': TaskType.GENOMICS,
            'protein': TaskType.PROTEOMICS,
            'transcriptome': TaskType.TRANSCRIPTOMICS,
            'quality': TaskType.QUALITY_CONTROL,
            'assembly': TaskType.ASSEMBLY,
            'annotation': TaskType.ANNOTATION,
            'comparative': TaskType.COMPARATIVE_ANALYSIS,
            'visualization': TaskType.VISUALIZATION,
            'statistics': TaskType.STATISTICS,
        }

        for keyword, enum_val in english_mapping.items():
            if keyword in task_type_str:
                return enum_val

        return TaskType.UNKNOWN

    def _parse_intent_type(self, intent_type_str: str) -> IntentType:
        """Parse intent type string to IntentType enum with fallback handling."""
        intent_type_str = intent_type_str.lower().strip()

        # Direct mapping
        try:
            return IntentType(intent_type_str)
        except ValueError:
            pass

        # Chinese to English mapping
        chinese_mapping = {
            '分析': IntentType.ANALYZE,
            '比较': IntentType.COMPARE,
            '可视化': IntentType.VISUALIZE,
            '处理': IntentType.PROCESS,
            '转换': IntentType.CONVERT,
            '过滤': IntentType.FILTER,
            '注释': IntentType.ANNOTATE,
            '组装': IntentType.ASSEMBLE,
            '对齐': IntentType.ALIGN,
        }

        for chinese, enum_val in chinese_mapping.items():
            if chinese in intent_type_str:
                return enum_val

        # English keyword mapping
        english_mapping = {
            'analyze': IntentType.ANALYZE,
            'compare': IntentType.COMPARE,
            'visualize': IntentType.VISUALIZE,
            'process': IntentType.PROCESS,
            'convert': IntentType.CONVERT,
            'filter': IntentType.FILTER,
            'annotate': IntentType.ANNOTATE,
            'assemble': IntentType.ASSEMBLE,
            'align': IntentType.ALIGN,
        }

        for keyword, enum_val in english_mapping.items():
            if keyword in intent_type_str:
                return enum_val

        return IntentType.UNKNOWN

    def _parse_llm_tasks(self, llm_tasks: List[Dict[str, Any]]) -> List[Task]:
        """Parse LLM response into Task objects."""
        tasks = []
        task_id_map = {}  # Map index to task ID for dependencies
        
        for i, task_data in enumerate(llm_tasks):
            task_id = str(uuid.uuid4())
            task_id_map[i] = task_id
            
            # Parse input and output data types
            input_data_types = [
                DataType(name=dt, extension=f".{dt}")
                for dt in task_data.get('input_types', [])
            ]
            output_data_types = [
                DataType(name=dt, extension=f".{dt}")
                for dt in task_data.get('output_types', [])
            ]
            
            # Convert string enums to proper types
            task_type = self._parse_task_type(task_data.get('task_type', 'unknown'))
            intent_type = self._parse_intent_type(task_data.get('intent_type', 'unknown'))
            
            task = Task(
                id=task_id,
                name=task_data['name'],
                description=task_data['description'],
                task_type=task_type,
                intent_type=intent_type,
                input_data_types=input_data_types,
                output_data_types=output_data_types,
                estimated_duration=task_data.get('estimated_minutes', 30),
                confidence=0.7,  # LLM-based tasks have moderate confidence
                dependencies=[]  # Will be filled in next step
            )
            
            tasks.append(task)
        
        # Set up dependencies
        for i, task_data in enumerate(llm_tasks):
            dependencies = task_data.get('dependencies', [])
            for dep_index in dependencies:
                if dep_index < len(tasks):
                    tasks[i].dependencies.append(task_id_map[dep_index])
        
        return tasks
    
    def _create_fallback_task(self, request: UserRequest, parsed_intent: Dict[str, Any]) -> List[Task]:
        """Create a simple fallback task when decomposition fails."""
        task_id = str(uuid.uuid4())
        
        data_types = parsed_intent.get('data_types', [])
        input_types = data_types if data_types else [DataType(name='unknown', extension='.unknown')]
        
        task = Task(
            id=task_id,
            name='Research Analysis',
            description=f"Execute requested analysis: {request.request_text}",
            task_type=parsed_intent.get('task_type', TaskType.UNKNOWN),
            intent_type=parsed_intent.get('intent', IntentType.UNKNOWN),
            input_data_types=input_types,
            output_data_types=[DataType(name='result', extension='.tabular')],
            estimated_duration=60,
            confidence=0.3
        )
        
        return [task]
    
    def _estimate_task_duration(self, task_type: TaskType) -> int:
        """Estimate task duration in minutes based on task type."""
        duration_map = {
            TaskType.QUALITY_CONTROL: 15,
            TaskType.DATA_PROCESSING: 30,
            TaskType.SEQUENCE_ANALYSIS: 60,
            TaskType.GENOMICS: 120,
            TaskType.TRANSCRIPTOMICS: 90,
            TaskType.PROTEOMICS: 180,
            TaskType.ASSEMBLY: 240,
            TaskType.ANNOTATION: 60,
            TaskType.COMPARATIVE_ANALYSIS: 90,
            TaskType.VISUALIZATION: 20,
            TaskType.STATISTICS: 45
        }
        
        return duration_map.get(task_type, 60)
    
    def create_task_graph(self, tasks: List[Task]) -> TaskGraph:
        """Create a dependency graph from tasks."""
        graph = TaskGraph()
        
        # Add all tasks to graph
        for task in tasks:
            graph.add_task(task)
        
        # Add dependencies
        for task in tasks:
            for dep_id in task.dependencies:
                graph.add_dependency(dep_id, task.id)
        
        return graph
    
    def optimize_task_sequence(self, tasks: List[Task]) -> List[Task]:
        """Optimize task sequence for parallel execution where possible."""
        graph = self.create_task_graph(tasks)
        execution_order = graph.get_execution_order()
        
        # Reorder tasks based on optimal execution sequence
        task_map = {task.id: task for task in tasks}
        optimized_tasks = [task_map[task_id] for task_id in execution_order]
        
        return optimized_tasks