"""
Context Gatherer - Progressive LLM-guided context collection for parameter inference.

This module implements systematic context gathering through:
1. Initial query parsing to extract implicit context
2. Identification of missing user-providable context
3. Progressive question generation (max 3 questions at a time)
4. Context validation and completion checking
"""

import json
import logging
from typing import Dict, List, Optional, Any
from pathlib import Path

logger = logging.getLogger(__name__)


class ContextGatherer:
    """
    Systematically gathers required context from user through progressive dialogue.

    Uses the parameter context requirements database to know what information
    is needed for each tool's parameters, then guides the user through providing
    that information with minimal question burden.
    """

    # Priority order for asking questions (ask most important first)
    PRIORITY_FIELDS = [
        'organism',
        'tissue_type',
        'antibody_target',
        'histone_mark_type',
        'experimental_goal',
        'application_type',
        'sample_type',
        'docking_purpose',
        'registration_scenario',
        'downstream_analysis'
    ]

    def __init__(self, tool_id: str, requirements_db_path: Optional[str] = None):
        """
        Initialize context gatherer for a specific tool.

        Args:
            tool_id: Tool identifier (e.g., 'biomni/genomics/perform_chipseq_peak_calling_with_macs2')
            requirements_db_path: Path to parameter context requirements JSON
        """
        self.tool_id = tool_id

        # Load context requirements
        if requirements_db_path is None:
            requirements_db_path = Path(__file__).parent.parent / 'knowledge' / 'parameter_context_requirements.json'

        with open(requirements_db_path) as f:
            db = json.load(f)
            self.requirements = db['tools'].get(tool_id, {})

        if not self.requirements:
            logger.warning(f"No context requirements found for tool: {tool_id}")
            self.requirements = {'parameters': {}}

        # Track gathered context and questions asked
        self.gathered_context = {}
        self.questions_asked = []
        self.conversation_history = []

    def gather_context(
        self,
        initial_query: str,
        user_answers: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Main entry point: extract what we can from query, then ask for missing info.

        Args:
            initial_query: User's natural language query
            user_answers: Optional dict of {field: value} from previous questions

        Returns:
            {
                'status': 'need_more_context' | 'context_complete',
                'questions': [...] if need_more_context,
                'context': {...} if context_complete,
                'gathered_so_far': {...} always included
            }
        """
        # Step 1: Extract what we can from initial query
        if not self.gathered_context:  # First time
            extracted = self._extract_from_query(initial_query)
            self.gathered_context.update(extracted)
            logger.info(f"Extracted from query: {extracted}")

        # Step 2: Incorporate user answers if provided
        if user_answers:
            self.gathered_context.update(user_answers)
            self.questions_asked.extend(user_answers.keys())
            logger.info(f"Updated with user answers: {user_answers}")

        # Step 3: Check what's still missing
        missing = self._identify_missing_user_context()

        if missing:
            # Generate progressive questions (max 3 at a time)
            questions = self._generate_context_questions(missing)
            return {
                'status': 'need_more_context',
                'questions': questions,
                'gathered_so_far': self.gathered_context.copy(),
                'progress': {
                    'collected': len(self.gathered_context),
                    'remaining': len(missing),
                    'total': len(self.gathered_context) + len(missing)
                }
            }
        else:
            return {
                'status': 'context_complete',
                'context': self.gathered_context.copy(),
                'summary': self._generate_context_summary()
            }

    def _extract_from_query(self, query: str) -> Dict[str, Any]:
        """
        Use LLM to extract context from user's natural language query.

        This uses a structured prompt to identify context fields mentioned
        in the user's query. For example, "H3K27me3 ChIP-seq in mouse brain"
        would extract: {organism: 'mouse', antibody_target: 'H3K27me3',
        tissue_type: 'brain', histone_mark_type: 'broad'}

        Args:
            query: User's natural language description

        Returns:
            dict of extracted context fields
        """
        # Get all user-providable fields for this tool
        user_fields = self._get_user_providable_fields()

        if not user_fields:
            return {}

        # Build extraction prompt
        prompt = self._build_extraction_prompt(query, user_fields)

        # Call LLM for structured extraction
        # TODO: Replace with actual Claude API call when integrated
        extracted = self._mock_extract_context(query, user_fields)

        # Filter out None values
        return {k: v for k, v in extracted.items() if v is not None}

    def _build_extraction_prompt(self, query: str, fields: List[Dict]) -> str:
        """
        Build prompt for LLM context extraction.

        Args:
            query: User query
            fields: List of field definitions with examples

        Returns:
            Formatted prompt string
        """
        examples_text = []
        for field_info in fields:
            if 'examples' in field_info:
                examples = field_info['examples']
                if isinstance(examples, dict):
                    example_str = ", ".join([f'"{k}" → {v if isinstance(v, str) else v.get("value", v)}'
                                            for k, v in list(examples.items())[:3]])
                    examples_text.append(f"  - {field_info['field']}: {example_str}")

        return f"""Extract experimental context from this user query:

Query: "{query}"

Extract values for these fields (use null if not mentioned):
{chr(10).join(examples_text)}

Required context fields and their meanings:
{json.dumps([{'field': f['field'], 'purpose': f.get('help_text', '')} for f in fields], indent=2)}

Return JSON with extracted values. Be generous in inference:
- "H3K27me3" → antibody_target="H3K27me3", histone_mark_type="broad"
- "mouse" → organism="mouse" or "mus musculus"
- "brain tissue" → tissue_type="brain"

Only include fields where you have high confidence. Use null for uncertain fields.
"""

    def _mock_extract_context(self, query: str, fields: List[Dict]) -> Dict[str, Any]:
        """
        Mock context extraction (replace with real LLM call).

        This is a simple pattern matching fallback for when LLM is not available.
        In production, this would call Claude API with structured output.
        """
        extracted = {}
        query_lower = query.lower()

        # Pattern matching for common fields
        organism_patterns = {
            'human': ['human', 'homo sapiens', 'hg38', 'hg19', 'grch38'],
            'mouse': ['mouse', 'mus musculus', 'mm10', 'mm39'],
            'drosophila': ['drosophila', 'fly', 'dm6'],
            'rat': ['rat', 'rattus'],
            'c. elegans': ['worm', 'c. elegans', 'caenorhabditis']
        }

        for organism, patterns in organism_patterns.items():
            if any(p in query_lower for p in patterns):
                extracted['organism'] = organism
                break

        # Histone marks and TFs
        histone_marks = {
            'H3K27me3': 'broad',
            'H3K9me3': 'broad',
            'H3K36me3': 'broad',
            'H3K4me3': 'narrow',
            'H3K27ac': 'narrow',
            'H3K4me1': 'narrow',
            'CTCF': 'narrow',
            'p300': 'narrow'
        }

        for mark, mark_type in histone_marks.items():
            if mark.lower() in query_lower:
                extracted['antibody_target'] = mark
                extracted['histone_mark_type'] = mark_type
                break

        # Tissue types
        tissues = ['brain', 'liver', 'lung', 'heart', 'kidney', 'pbmc', 'blood', 'pancreas']
        for tissue in tissues:
            if tissue in query_lower:
                extracted['tissue_type'] = tissue
                break

        # Experimental goals
        if 'screen' in query_lower or 'high-throughput' in query_lower:
            extracted['experimental_goal'] = 'screening'
        elif 'optimization' in query_lower or 'optimize' in query_lower:
            extracted['experimental_goal'] = 'optimization'
        elif 'publication' in query_lower or 'manuscript' in query_lower:
            extracted['experimental_goal'] = 'publication'

        return extracted

    def _get_user_providable_fields(self) -> List[Dict]:
        """
        Get list of all user-providable context fields for this tool.

        Returns:
            List of field definitions with examples and help text
        """
        fields = []

        for param_name, param_req in self.requirements.get('parameters', {}).items():
            if param_req.get('context_type') != 'user_providable':
                continue

            for field in param_req.get('required_context', []):
                # Avoid duplicates
                if field in [f['field'] for f in fields]:
                    continue

                fields.append({
                    'field': field,
                    'parameter': param_name,
                    'question_template': param_req.get('question_template', f'What is the {field}?'),
                    'examples': param_req.get('examples', param_req.get('mapping', {})),
                    'help_text': param_req.get('help_text', '')
                })

        return fields

    def _identify_missing_user_context(self) -> List[Dict]:
        """
        Find which user-providable context fields are still None.

        Returns:
            List of missing field definitions
        """
        all_fields = self._get_user_providable_fields()
        missing = []

        for field_info in all_fields:
            field_name = field_info['field']

            # Skip if already gathered
            if field_name in self.gathered_context and self.gathered_context[field_name] is not None:
                continue

            # Skip if already asked but user skipped
            if field_name in self.questions_asked:
                continue

            missing.append(field_info)

        return missing

    def _generate_context_questions(self, missing_fields: List[Dict]) -> List[Dict]:
        """
        Generate user-friendly questions to fill missing context.

        Uses progressive disclosure: max 3 questions at a time.
        Prioritizes important fields (organism > experiment type > technical details).

        Args:
            missing_fields: List of missing field definitions

        Returns:
            List of formatted questions for UI
        """
        # Sort by priority
        sorted_fields = sorted(
            missing_fields,
            key=lambda x: (
                self.PRIORITY_FIELDS.index(x['field'])
                if x['field'] in self.PRIORITY_FIELDS
                else 999
            )
        )

        # Take max 3 questions (progressive disclosure)
        fields_to_ask = sorted_fields[:3]

        questions = []
        for field_info in fields_to_ask:
            question = {
                'field': field_info['field'],
                'question': field_info['question_template'],
                'parameter': field_info['parameter'],
                'help_text': field_info['help_text']
            }

            # Determine question type and options
            examples = field_info.get('examples', {})

            if isinstance(examples, dict) and len(examples) > 0:
                # Multiple choice question
                question['type'] = 'select'
                question['options'] = []

                for key, value in examples.items():
                    if isinstance(value, dict):
                        # Rich example with description
                        question['options'].append({
                            'value': key,
                            'label': key,
                            'description': value.get('description', ''),
                            'recommended_value': value.get('value')
                        })
                    else:
                        # Simple value
                        question['options'].append({
                            'value': key,
                            'label': key,
                            'recommended_value': value
                        })

                # Add "Other" option for free text
                question['allow_custom'] = True
            else:
                # Free text question
                question['type'] = 'text'
                question['placeholder'] = f'Enter {field_info["field"]}'

            questions.append(question)

        return questions

    def _generate_context_summary(self) -> str:
        """
        Generate human-readable summary of gathered context.

        Returns:
            Formatted summary string
        """
        summary_lines = [f"Context for {self.requirements.get('tool_name', self.tool_id)}:"]

        for field, value in self.gathered_context.items():
            summary_lines.append(f"  • {field}: {value}")

        return "\n".join(summary_lines)

    def get_parameter_value(self, param_name: str) -> Optional[Any]:
        """
        Get inferred parameter value from gathered context.

        Uses the parameter's mapping/decision tree to derive value from context.

        Args:
            param_name: Parameter name to infer

        Returns:
            Inferred value or None if can't be determined
        """
        param_req = self.requirements.get('parameters', {}).get(param_name)
        if not param_req:
            return None

        # Direct mapping case
        if 'mapping' in param_req:
            mapping = param_req['mapping']

            # Check if we have the required context
            for context_field in param_req.get('required_context', []):
                if context_field in self.gathered_context:
                    context_value = self.gathered_context[context_field]

                    # Look up in mapping
                    if context_value in mapping:
                        return mapping[context_value]

        # Decision tree case (handled elsewhere - this is simplified)
        # Full decision tree evaluation would need more sophisticated logic

        # Fallback to default
        return param_req.get('default')

    def validate_context(self) -> Dict[str, Any]:
        """
        Validate that gathered context is sufficient and consistent.

        Returns:
            {
                'valid': bool,
                'errors': List[str],
                'warnings': List[str]
            }
        """
        errors = []
        warnings = []

        # Check required context is present
        required_fields = set()
        for param_req in self.requirements.get('parameters', {}).values():
            if param_req.get('context_type') == 'user_providable':
                required_fields.update(param_req.get('required_context', []))

        for field in required_fields:
            if field not in self.gathered_context:
                errors.append(f"Required context field '{field}' is missing")

        # Check for conflicting values
        # (e.g., antibody_target='H3K4me3' but histone_mark_type='broad' would be wrong)
        # This would need domain-specific validation logic

        return {
            'valid': len(errors) == 0,
            'errors': errors,
            'warnings': warnings
        }


# Example usage
if __name__ == '__main__':
    # Example: ChIP-seq peak calling
    gatherer = ContextGatherer('biomni/genomics/perform_chipseq_peak_calling_with_macs2')

    # Round 1: Initial query
    result = gatherer.gather_context("Call peaks from H3K27me3 ChIP-seq in mouse brain")
    print("Round 1:", json.dumps(result, indent=2))

    if result['status'] == 'need_more_context':
        # User answers questions
        user_answers = {}
        for q in result['questions']:
            print(f"\nQ: {q['question']}")
            if q['type'] == 'select':
                print("Options:", [opt['label'] for opt in q['options']])

        # Simulate user selecting first option for each
        for q in result['questions']:
            if q['type'] == 'select' and q['options']:
                user_answers[q['field']] = q['options'][0]['value']

        # Round 2: With answers
        result = gatherer.gather_context("", user_answers)
        print("\nRound 2:", json.dumps(result, indent=2))

    if result['status'] == 'context_complete':
        print("\n✓ Context gathering complete!")
        print("Gathered context:", result['context'])

        # Get parameter values
        peak_type = gatherer.get_parameter_value('peak_type')
        print(f"Inferred peak_type: {peak_type}")
