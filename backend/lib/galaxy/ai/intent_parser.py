"""
Intent Parser for Galaxy AI Assistant

Parses user requests to understand research intentions and extract structured information.
"""

import re
import json
from typing import Dict, List, Any, Optional, Tuple
from .types import IntentType, TaskType, UserRequest, DataType
from .config import AIConfig
from .llm_client import LLMClient


class IntentParser:
    """Parses user research intentions from natural language requests."""
    
    def __init__(self, config: AIConfig):
        self.config = config
        self.llm_client = LLMClient(config)
        
        # Intent patterns for quick classification
        self.intent_patterns = {
            IntentType.ANALYZE: [
                r'\b(analyz|examine|investigat|study)\w*\b',
                r'\bsequence analysis\b',
                r'\bstatistical analysis\b'
            ],
            IntentType.COMPARE: [
                r'\b(compar|contrast|differ)\w*\b',
                r'\bdifferential\b',
                r'\bvs\.|versus\b'
            ],
            IntentType.VISUALIZE: [
                r'\b(plot|chart|graph|visualiz|display)\w*\b',
                r'\bheatmap\b',
                r'\bscatter plot\b'
            ],
            IntentType.PROCESS: [
                r'\b(process|preprocess|clean|filter|transform)\w*\b',
                r'\bquality control\b'
            ],
            IntentType.CONVERT: [
                r'\b(convert|transform|format)\w*\b',
                r'\bfrom .* to\b'
            ],
            IntentType.FILTER: [
                r'\b(filter|select|subset|extract)\w*\b',
                r'\bremove\b'
            ],
            IntentType.ANNOTATE: [
                r'\b(annotat|label|identif)\w*\b',
                r'\bfunctional annotation\b'
            ],
            IntentType.ASSEMBLE: [
                r'\b(assembl|construct|build)\w*\b',
                r'\bgenome assembly\b'
            ],
            IntentType.ALIGN: [
                r'\b(align|map|match)\w*\b',
                r'\bsequence alignment\b'
            ]
        }
        
        # Task type patterns
        self.task_patterns = {
            TaskType.SEQUENCE_ANALYSIS: [
                r'\bsequence\b',
                r'\bDNA\b',
                r'\bRNA\b',
                r'\bprotein\b'
            ],
            TaskType.GENOMICS: [
                r'\bgenome\b',
                r'\bgenomic\b',
                r'\bWGS\b',
                r'\bwhole genome\b'
            ],
            TaskType.TRANSCRIPTOMICS: [
                r'\btranscriptom\w*\b',
                r'\bRNA-seq\b',
                r'\bexpression\b',
                r'\bmRNA\b'
            ],
            TaskType.PROTEOMICS: [
                r'\bproteom\w*\b',
                r'\bmass spec\w*\b',
                r'\bMS/MS\b'
            ],
            TaskType.QUALITY_CONTROL: [
                r'\bquality control\b',
                r'\bQC\b',
                r'\bFastQC\b'
            ],
            TaskType.ASSEMBLY: [
                r'\bassembl\w*\b',
                r'\bde novo\b',
                r'\bcontig\b'
            ]
        }
        
        # Data type patterns
        self.data_type_patterns = {
            'fastq': [r'\bfastq\b', r'\.fastq\b', r'\.fq\b'],
            'fasta': [r'\bfasta\b', r'\.fasta\b', r'\.fa\b'],
            'bam': [r'\bbam\b', r'\.bam\b'],
            'sam': [r'\bsam\b', r'\.sam\b'],
            'vcf': [r'\bvcf\b', r'\.vcf\b'],
            'gff': [r'\bgff\b', r'\.gff\b'],
            'bed': [r'\bbed\b', r'\.bed\b'],
            'csv': [r'\bcsv\b', r'\.csv\b'],
            'tabular': [r'\btabular\b', r'\.tab\b', r'\.tsv\b']
        }
    
    def parse_intent(self, request: UserRequest) -> Tuple[IntentType, float]:
        """Parse the main intent from user request."""
        text = request.request_text.lower()
        intent_scores = {}
        
        # Pattern-based quick classification
        for intent_type, patterns in self.intent_patterns.items():
            score = 0
            for pattern in patterns:
                matches = len(re.findall(pattern, text, re.IGNORECASE))
                score += matches * 0.3
            intent_scores[intent_type] = min(score, 1.0)
        
        # If no clear pattern match, use LLM
        if max(intent_scores.values()) < 0.5:
            llm_intent, llm_confidence = self._llm_parse_intent(request)
            if llm_confidence > self.config.intent_confidence_threshold:
                return llm_intent, llm_confidence
        
        # Return highest scoring intent
        best_intent = max(intent_scores.items(), key=lambda x: x[1])
        return best_intent[0], best_intent[1]
    
    def parse_task_type(self, request: UserRequest) -> Tuple[TaskType, float]:
        """Determine the research task type."""
        text = request.request_text.lower()
        task_scores = {}
        
        for task_type, patterns in self.task_patterns.items():
            score = 0
            for pattern in patterns:
                matches = len(re.findall(pattern, text, re.IGNORECASE))
                score += matches * 0.4
            task_scores[task_type] = min(score, 1.0)
        
        if max(task_scores.values()) < 0.5:
            return TaskType.UNKNOWN, 0.0
        
        best_task = max(task_scores.items(), key=lambda x: x[1])
        return best_task[0], best_task[1]
    
    def extract_data_types(self, request: UserRequest) -> List[DataType]:
        """Extract mentioned data types from request."""
        text = request.request_text.lower()
        found_types = []
        
        for data_type, patterns in self.data_type_patterns.items():
            for pattern in patterns:
                if re.search(pattern, text, re.IGNORECASE):
                    found_types.append(DataType(
                        name=data_type,
                        extension=f".{data_type}",
                        description=f"Auto-detected {data_type} format"
                    ))
                    break
        
        # Also check available datasets
        if request.available_datasets:
            for dataset in request.available_datasets:
                if 'extension' in dataset:
                    ext = dataset['extension'].lower()
                    if ext not in [dt.name for dt in found_types]:
                        found_types.append(DataType(
                            name=ext,
                            extension=f".{ext}",
                            description=f"Available dataset format: {ext}"
                        ))
        
        return found_types
    
    def extract_constraints(self, request: UserRequest) -> Dict[str, Any]:
        """Extract constraints and preferences from request."""
        text = request.request_text.lower()
        constraints = {}
        
        # Time constraints
        time_patterns = [
            (r'(\d+)\s*hours?', lambda m: int(m.group(1)) * 60),
            (r'(\d+)\s*minutes?', lambda m: int(m.group(1))),
            (r'quickly?|fast|rapid', lambda m: 30),
            (r'slowly?|careful|thorough', lambda m: 180)
        ]
        
        for pattern, converter in time_patterns:
            match = re.search(pattern, text)
            if match:
                constraints['max_runtime_minutes'] = converter(match)
                break
        
        # Resource constraints
        if re.search(r'high.?memory|large.?dataset', text):
            constraints['memory_intensive'] = True
        
        if re.search(r'parallel|multi.?core|distributed', text):
            constraints['parallelizable'] = True
        
        # Quality constraints
        if re.search(r'high.?quality|accurate|precise', text):
            constraints['quality_priority'] = 'high'
        elif re.search(r'quick|rough|approximate', text):
            constraints['quality_priority'] = 'speed'
        
        return constraints
    
    def _llm_parse_intent(self, request: UserRequest) -> Tuple[IntentType, float]:
        """Use LLM to parse intent when patterns are insufficient."""
        prompt = f"""
        Analyze this bioinformatics research request and classify the primary intent:
        
        Request: "{request.request_text}"
        
        Available intent types:
        - ANALYZE: Perform analysis on data
        - COMPARE: Compare different datasets or conditions
        - VISUALIZE: Create plots, charts, or visual representations
        - PROCESS: Clean, filter, or preprocess data
        - CONVERT: Transform data from one format to another
        - FILTER: Select or subset data based on criteria
        - ANNOTATE: Add functional or structural annotations
        - ASSEMBLE: Construct sequences or genomes
        - ALIGN: Map or align sequences
        - UNKNOWN: Cannot determine intent
        
        Respond with JSON: {{"intent": "INTENT_TYPE", "confidence": 0.95, "reasoning": "explanation"}}
        """
        
        try:
            response = self.llm_client.generate(prompt)
            result = json.loads(response)
            
            intent_str = result.get('intent', 'UNKNOWN')
            confidence = float(result.get('confidence', 0.0))
            
            intent = getattr(IntentType, intent_str, IntentType.UNKNOWN)
            return intent, confidence
            
        except Exception as e:
            print(f"LLM intent parsing failed: {e}")
            return IntentType.UNKNOWN, 0.0
    
    def parse_request(self, request: UserRequest) -> Dict[str, Any]:
        """Parse a complete user request and extract all structured information."""
        intent, intent_confidence = self.parse_intent(request)
        task_type, task_confidence = self.parse_task_type(request)
        data_types = self.extract_data_types(request)
        constraints = self.extract_constraints(request)
        
        return {
            'intent': intent,
            'intent_confidence': intent_confidence,
            'task_type': task_type,
            'task_confidence': task_confidence,
            'data_types': data_types,
            'constraints': constraints,
            'original_request': request.request_text
        }