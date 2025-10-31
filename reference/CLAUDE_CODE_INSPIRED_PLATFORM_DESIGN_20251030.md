# Claude Code-Inspired Workflow Generation Platform Design

**Date:** 2025-10-30
**Goal:** Transform workflow generation platform to leverage Claude's collaborative, iterative, and intelligent capabilities

---

## Executive Summary

The platform should evolve from **"AI generates workflow → user accepts/rejects"** to **"Claude collaborates with user to build optimal workflow"**.

Key principle: **Claude is not just generating workflows, it's teaching and learning alongside the scientist.**

---

## 1. Memory & Context Management System

### 1.1 User Profile Context

**Storage Structure:**
```
user_profile/
├── domain_knowledge.json          # Scientific domain, expertise level
├── tool_preferences.json          # Learned tool preferences
├── workflow_history.json          # Past workflows with outcomes
├── correction_log.json            # Mistakes Claude made, user corrections
└── research_context.json          # Current projects, datasets, goals
```

**domain_knowledge.json:**
```json
{
  "user_id": "user_123",
  "expertise_level": "intermediate",  // beginner, intermediate, advanced
  "research_domain": {
    "primary": "proteomics",
    "subdomains": ["phosphoproteomics", "DIA", "label-free"],
    "organisms": ["mouse", "human"],
    "tissues": ["liver", "brain"],
    "diseases": ["cancer", "neurodegenerative"]
  },
  "preferred_methods": {
    "acquisition": "DIA",
    "quantification": "label-free",
    "statistics": "limma"
  },
  "knowledge_confidence": {
    "ms_data_types": 0.9,
    "search_engines": 0.7,
    "statistical_analysis": 0.5
  }
}
```

**tool_preferences.json:**
```json
{
  "learned_preferences": [
    {
      "task": "database_search",
      "preferred_tool": "dia_nn",
      "reason": "User explicitly chose DIA-NN over MaxQuant (2025-10-15)",
      "confidence": 1.0
    },
    {
      "task": "normalization",
      "preferred_tool": "median_normalization",
      "reason": "User used this in 3 previous workflows",
      "confidence": 0.8
    }
  ],
  "tool_feedback": [
    {
      "tool": "maxquant",
      "context": "DIA data",
      "feedback": "negative",
      "user_comment": "MaxQuant doesn't work well for DIA",
      "alternative_used": "dia_nn"
    }
  ]
}
```

**correction_log.json:**
```json
{
  "corrections": [
    {
      "timestamp": "2025-10-20T14:30:00Z",
      "workflow_id": "wf_789",
      "mistake": {
        "step": 2,
        "tool_suggested": "maxquant_search",
        "issue": "Used DDA tool for DIA data",
        "severity": "critical"
      },
      "user_correction": {
        "corrected_tool": "dia_nn",
        "explanation": "DIA data requires DIA-specific search engine"
      },
      "learned_rule": {
        "condition": "data_type == 'DIA'",
        "constraint": "search_engine IN ['dia_nn', 'spectronaut']",
        "avoid": "maxquant (DDA-only)"
      }
    }
  ]
}
```

### 1.2 Session Context Management

**Implement conversation memory:**

```python
class SessionContext:
    def __init__(self, user_id, session_id):
        self.user_id = user_id
        self.session_id = session_id
        self.conversation_history = []
        self.current_workflow = None
        self.decisions_made = []
        self.questions_asked = []

    def add_message(self, role, content, metadata=None):
        """Add message to conversation history"""
        self.conversation_history.append({
            "role": role,
            "content": content,
            "metadata": metadata,
            "timestamp": datetime.now()
        })

    def get_context_summary(self):
        """Generate compact summary of session so far"""
        return {
            "user_intent": self._extract_intent(),
            "data_type": self._infer_data_type(),
            "workflow_stage": self._current_stage(),
            "key_decisions": self.decisions_made,
            "open_questions": self._unresolved_questions()
        }

    def compact_history(self):
        """Compress old messages to summaries"""
        # Keep recent messages, summarize old ones
        if len(self.conversation_history) > 20:
            old_messages = self.conversation_history[:-10]
            summary = self._summarize_messages(old_messages)
            self.conversation_history = [
                {"role": "system", "content": f"Previous conversation summary: {summary}"}
            ] + self.conversation_history[-10:]
```

---

## 2. Iterative Workflow Refinement Process

### 2.1 Progressive Workflow Building

**Phase 1: Clarification**
```
User: "I want to analyze my proteomics data"

Claude: "I'll help you build a proteomics workflow. First, let me understand your data:

📊 Data Understanding Questions:
1. What type of mass spectrometry data do you have?
   ○ DDA (Data-Dependent Acquisition) - traditional shotgun
   ○ DIA (Data-Independent Acquisition) - newer, more comprehensive
   ○ I'm not sure

2. What's your analysis goal?
   ○ Protein identification only
   ○ Protein quantification (compare conditions)
   ○ Post-translational modification analysis
   ○ All of the above

3. What organism are your samples from?
   [Text input: ____________]
"
```

**Phase 2: Draft Workflow**
```
Claude: "Based on your answers (DIA data, mouse samples, quantification goal),
here's a draft workflow structure:

Step 1: File Conversion (RAW → mzML)
Step 2: DIA-NN Search
Step 3: Protein Quantification
Step 4: Statistical Analysis
Step 5: Visualization

Does this high-level flow make sense for your needs?
[Yes, continue] [No, I need X instead] [Show me more details]
"
```

**Phase 3: Step-by-Step Validation**
```
Claude: "Let's build this step by step.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Step 1: File Conversion
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Tool: MSConvert
Purpose: Convert Thermo RAW files to open mzML format
Input: Your RAW files (Thermo .raw format)
Output: mzML files (vendor-neutral format)

Why needed: Galaxy tools work with open formats, not vendor formats

⚙️ Parameters:
- Output format: mzML
- Compression: None (for compatibility)
- Peak picking: No (preserve raw data)

Does this look correct for your data?
[✓ Looks good] [✗ Change something] [? I have questions]
"
```

**Phase 4: Parameter Tuning**
```
Claude: "For DIA-NN search, I need to set some parameters based on your instrument.

What mass spectrometer did you use?
○ Orbitrap (Thermo)
  └─ Which model? [Dropdown: Exploris, Fusion, Q Exactive, ...]
○ QTOF (Waters/Agilent/Bruker)
○ Other

[If user selects Orbitrap Exploris]

Claude: "Great! For Orbitrap Exploris, I'll use these typical settings:

MS1 accuracy: 10 ppm (Orbitrap precision)
MS2 accuracy: 20 ppm
Scan window: 7 (DIA standard)

These are typical values for your instrument. Would you like to:
○ Use these recommended settings
○ Customize parameters (advanced)
"
```

### 2.2 Validation Checkpoints

**Before generation:**
- [ ] User intent understood
- [ ] Data type confirmed
- [ ] Required inputs available
- [ ] User preferences applied

**After generation:**
- [ ] Tool chain is compatible
- [ ] No redundant steps
- [ ] Parameters are scientifically valid
- [ ] Matches similar successful workflows

**Before execution:**
- [ ] All tools installed
- [ ] Resources available
- [ ] Estimated runtime acceptable
- [ ] User confirms final workflow

---

## 3. Rich Tool Metadata Schema

### 3.1 Extended Tool Schema

```json
{
  "tool_id": "dia_nn_search",
  "version": "1.8.1",
  "name": "DIA-NN",
  "category": "Proteomics",
  "subcategory": "Database Search",

  "description": {
    "short": "Deep learning-based search engine for DIA data",
    "long": "DIA-NN is a specialized search engine optimized for data-independent acquisition (DIA) proteomics data. It uses neural networks for accurate peptide identification and achieves high sensitivity.",
    "when_to_use": "Use DIA-NN when you have DIA/SWATH acquisition data and need deep proteome coverage with accurate quantification.",
    "when_not_to_use": "Do not use for DDA data - use MaxQuant, MSFragger, or MSGF+ instead."
  },

  "scientific_context": {
    "purpose": "Peptide identification and quantification from DIA data",
    "methodology": "Deep learning-based precursor and fragment scoring",
    "best_for": [
      "DIA/SWATH data",
      "Large-scale DIA experiments",
      "Deep proteome coverage",
      "Label-free quantification"
    ],
    "limitations": [
      "Requires library (can generate in-silico)",
      "Not suitable for DDA data",
      "Memory intensive for very large libraries"
    ],
    "typical_accuracy": {
      "sensitivity": "High (>10,000 proteins from human cells)",
      "specificity": "High (<1% FDR)",
      "quantification_cv": "< 15% for high abundance proteins"
    }
  },

  "input_output": {
    "inputs": [
      {
        "name": "raw_data",
        "format": ["mzML", "dia"],
        "description": "DIA mass spectrometry data files",
        "required": true,
        "validation": "Must be DIA acquisition mode"
      },
      {
        "name": "fasta_database",
        "format": ["fasta"],
        "description": "Protein sequence database",
        "required": true
      },
      {
        "name": "spectral_library",
        "format": ["tsv", "speclib"],
        "description": "Optional spectral library (can predict if not provided)",
        "required": false
      }
    ],
    "outputs": [
      {
        "name": "protein_matrix",
        "format": "tsv",
        "description": "Protein-level quantification matrix",
        "columns": ["Protein.Group", "Gene", "Sample1_Quantity", "Sample2_Quantity"]
      },
      {
        "name": "peptide_matrix",
        "format": "tsv",
        "description": "Peptide-level quantification matrix"
      },
      {
        "name": "report",
        "format": "tsv",
        "description": "Main DIA-NN report with statistics"
      }
    ]
  },

  "parameters": {
    "mass_accuracy_ms1": {
      "type": "float",
      "default": 10.0,
      "range": [1.0, 50.0],
      "unit": "ppm",
      "description": "Mass accuracy for MS1 precursors",
      "instrument_dependent": {
        "Orbitrap": 10.0,
        "QTOF": 20.0,
        "TOF": 30.0
      },
      "help": "Set based on your mass spectrometer's typical accuracy. Orbitrap: 5-10 ppm, QTOF: 10-20 ppm"
    },
    "mass_accuracy_ms2": {
      "type": "float",
      "default": 20.0,
      "range": [5.0, 50.0],
      "unit": "ppm",
      "description": "Mass accuracy for MS2 fragments",
      "instrument_dependent": {
        "Orbitrap": 20.0,
        "QTOF": 40.0
      }
    },
    "fdr": {
      "type": "float",
      "default": 0.01,
      "range": [0.001, 0.05],
      "description": "False discovery rate threshold",
      "help": "Standard is 1% (0.01). Use 0.001 for higher confidence, 0.05 for more identifications"
    }
  },

  "workflow_context": {
    "typical_position": "early",
    "typical_predecessors": [
      "file_conversion",
      "quality_control_optional"
    ],
    "typical_successors": [
      "normalization",
      "statistical_analysis",
      "visualization"
    ],
    "incompatible_with": {
      "before": ["tmt_labeling", "silac_labeling"],
      "after": []
    },
    "required_dataset_types": ["raw|mzML"]
  },

  "alternatives": {
    "same_task": [
      {
        "tool": "spectronaut",
        "when_better": "When you have vendor software license and want integrated analysis",
        "trade_offs": "Commercial, but excellent sensitivity and user-friendly"
      },
      {
        "tool": "openswath",
        "when_better": "When you need open-source solution with peptide library",
        "trade_offs": "Requires pre-built library, slightly lower sensitivity"
      }
    ],
    "different_acquisition": [
      {
        "tool": "maxquant",
        "when": "If you have DDA data instead of DIA"
      }
    ]
  },

  "common_mistakes": [
    {
      "mistake": "Using DIA-NN on DDA data",
      "why_wrong": "DIA-NN is optimized for DIA acquisition patterns",
      "correct_approach": "Use MaxQuant, MSFragger, or MSGF+ for DDA data"
    },
    {
      "mistake": "Using very tight mass accuracy (e.g., 1 ppm) for QTOF data",
      "why_wrong": "QTOF instruments typically have 10-20 ppm accuracy",
      "correct_approach": "Set mass accuracy based on instrument specifications"
    }
  ],

  "resources": {
    "documentation": "https://github.com/vdemichev/DiaNN",
    "paper": "https://doi.org/10.1038/s41592-019-0638-x",
    "tutorial": "https://youtu.be/...",
    "typical_runtime": "10-30 minutes per sample",
    "memory_requirements": "8-16 GB RAM",
    "disk_space": "2-3x input file size"
  },

  "validation_rules": [
    {
      "rule": "input_must_be_dia",
      "check": "acquisition_mode == 'DIA'",
      "error_message": "DIA-NN requires DIA acquisition data. Your data appears to be DDA. Please use MaxQuant or MSFragger instead."
    },
    {
      "rule": "reasonable_mass_accuracy",
      "check": "mass_accuracy_ms1 >= 5 && mass_accuracy_ms1 <= 50",
      "warning_message": "Mass accuracy seems unusual. Typical values: Orbitrap 5-10 ppm, QTOF 10-20 ppm"
    }
  ]
}
```

### 3.2 Tool Relationship Graph

```python
class ToolRelationshipGraph:
    """
    Maintains relationships between tools for intelligent suggestions
    """

    def __init__(self):
        self.graph = nx.DiGraph()
        self.compatibility_matrix = {}

    def can_follow(self, tool_a, tool_b):
        """Check if tool_b can follow tool_a in workflow"""
        # Check output → input compatibility
        tool_a_outputs = self.get_tool_outputs(tool_a)
        tool_b_inputs = self.get_tool_inputs(tool_b)

        return any(
            self.format_compatible(output, input_)
            for output in tool_a_outputs
            for input_ in tool_b_inputs
        )

    def find_bridging_tools(self, tool_a, tool_b):
        """Find tools that can bridge incompatible tools"""
        # If tool_a outputs format X, tool_b needs format Y
        # Find tools that convert X → Y
        pass

    def detect_redundancy(self, tools_list):
        """Detect if multiple tools perform same function"""
        purposes = [self.get_tool_purpose(t) for t in tools_list]

        duplicates = []
        for i, purpose_i in enumerate(purposes):
            for j, purpose_j in enumerate(purposes[i+1:], i+1):
                similarity = self.semantic_similarity(purpose_i, purpose_j)
                if similarity > 0.8:
                    duplicates.append((i, j, similarity))

        return duplicates
```

---

## 4. Intelligent Question Generation

### 4.1 Question Generator System

```python
class WorkflowQuestionGenerator:
    """
    Generates contextual questions to clarify ambiguous workflow requirements
    """

    def generate_questions(self, user_query, user_profile, available_datasets):
        questions = []
        context = self.parse_query(user_query)

        # Question 1: Data Type (if ambiguous)
        if not context.has_explicit_data_type():
            questions.append({
                "id": "data_type",
                "priority": "high",
                "question": "What type of proteomics data do you have?",
                "type": "single_choice",
                "options": [
                    {
                        "value": "DDA",
                        "label": "DDA (Data-Dependent Acquisition)",
                        "description": "Traditional shotgun proteomics",
                        "help": "Most common for TMT/iTRAQ experiments"
                    },
                    {
                        "value": "DIA",
                        "label": "DIA (Data-Independent Acquisition)",
                        "description": "Newer method with SWATH patterns",
                        "help": "Better for label-free quantification"
                    },
                    {
                        "value": "unknown",
                        "label": "I'm not sure",
                        "description": "I need help identifying my data type"
                    }
                ],
                "why": "Different acquisition modes require different analysis tools",
                "impacts": ["search_engine_selection", "quantification_method"]
            })

        # Question 2: Analysis Goal
        if not context.has_explicit_goal():
            questions.append({
                "id": "analysis_goal",
                "priority": "high",
                "question": "What's your primary analysis goal?",
                "type": "multiple_choice",  # Can select multiple
                "options": [
                    {
                        "value": "identification",
                        "label": "Protein Identification",
                        "description": "Just identify what proteins are present"
                    },
                    {
                        "value": "quantification",
                        "label": "Quantitative Comparison",
                        "description": "Compare protein levels between conditions"
                    },
                    {
                        "value": "ptm",
                        "label": "Post-Translational Modifications",
                        "description": "Find phosphorylation, acetylation, etc."
                    }
                ],
                "why": "This determines whether we need quantification and normalization steps"
            })

        # Question 3: Organism (if not in profile)
        if not user_profile.has_organism():
            questions.append({
                "id": "organism",
                "priority": "high",
                "question": "What organism are your samples from?",
                "type": "autocomplete",
                "common_options": ["Human", "Mouse", "Rat", "Yeast", "E. coli"],
                "allow_custom": True,
                "why": "This determines which protein database to search against",
                "impacts": ["database_selection"]
            })

        # Question 4: Instrument (if parameters needed)
        if context.needs_parameter_configuration():
            questions.append({
                "id": "instrument",
                "priority": "medium",
                "question": "What mass spectrometer did you use?",
                "type": "hierarchical",
                "options": [
                    {
                        "value": "orbitrap",
                        "label": "Orbitrap (Thermo)",
                        "children": [
                            {"value": "exploris", "label": "Exploris 480/240"},
                            {"value": "fusion", "label": "Orbitrap Fusion"},
                            {"value": "qexactive", "label": "Q Exactive HF/Plus"}
                        ]
                    },
                    {
                        "value": "qtof",
                        "label": "QTOF",
                        "children": [
                            {"value": "timstof", "label": "timsTOF (Bruker)"},
                            {"value": "ttof", "label": "TripleTOF (Sciex)"}
                        ]
                    }
                ],
                "why": "Instrument type determines optimal mass accuracy settings",
                "impacts": ["mass_tolerance_parameters"]
            })

        # Question 5: Expertise Level Confirmation
        if user_profile.expertise_level == "unknown":
            questions.append({
                "id": "expertise",
                "priority": "low",
                "question": "How familiar are you with proteomics analysis?",
                "type": "single_choice",
                "options": [
                    {
                        "value": "beginner",
                        "label": "Beginner",
                        "description": "New to proteomics analysis"
                    },
                    {
                        "value": "intermediate",
                        "label": "Intermediate",
                        "description": "Familiar with concepts, need help with Galaxy"
                    },
                    {
                        "value": "advanced",
                        "label": "Advanced",
                        "description": "Experienced, just want efficient workflow"
                    }
                ],
                "why": "This helps me tailor explanations and default parameters",
                "note": "This doesn't affect the workflow, just how I communicate"
            })

        return self.prioritize_questions(questions)
```

### 4.2 Smart Question Skipping

```python
def should_ask_question(self, question, user_profile, workflow_context):
    """
    Determine if question should be asked based on available context
    """

    # Skip if we can infer from dataset metadata
    if question["id"] == "organism":
        if workflow_context.selected_dataset:
            inferred_organism = workflow_context.selected_dataset.metadata.get("organism")
            if inferred_organism:
                return False, f"Using organism from dataset: {inferred_organism}"

    # Skip if user has strong preference from history
    if question["id"] == "search_engine":
        if user_profile.has_strong_preference("search_engine"):
            preferred = user_profile.get_preference("search_engine")
            return False, f"Using your preferred search engine: {preferred}"

    # Skip if only one valid option given context
    if question["id"] == "data_type":
        if workflow_context.selected_dataset:
            detected_type = self.detect_data_type(workflow_context.selected_dataset)
            if detected_type and detected_type != "unknown":
                return False, f"Detected data type from files: {detected_type}"

    return True, None
```

---

## 5. Error Detection & Recovery Framework

### 5.1 Multi-Layer Validation

```python
class WorkflowValidator:
    """
    Validates workflows at multiple levels before execution
    """

    def validate(self, workflow, context):
        issues = []

        # Layer 1: Structural Validation
        issues.extend(self.validate_structure(workflow))

        # Layer 2: Tool Chain Compatibility
        issues.extend(self.validate_tool_chain(workflow))

        # Layer 3: Parameter Validation
        issues.extend(self.validate_parameters(workflow, context))

        # Layer 4: Scientific Validity
        issues.extend(self.validate_scientific_logic(workflow, context))

        # Layer 5: Resource Availability
        issues.extend(self.validate_resources(workflow))

        return ValidationReport(issues)

    def validate_tool_chain(self, workflow):
        """Validate that tools can be chained together"""
        issues = []

        for i in range(len(workflow.steps) - 1):
            current_step = workflow.steps[i]
            next_step = workflow.steps[i + 1]

            # Check output → input format compatibility
            current_outputs = self.get_output_formats(current_step.tool)
            next_inputs = self.get_input_formats(next_step.tool)

            if not self.formats_compatible(current_outputs, next_inputs):
                # Try to find bridging tool
                bridge = self.find_format_converter(current_outputs, next_inputs)

                if bridge:
                    issues.append({
                        "type": "warning",
                        "severity": "medium",
                        "step": i,
                        "issue": f"Format mismatch between step {i} and {i+1}",
                        "suggestion": f"Add format conversion step: {bridge.name}",
                        "auto_fix": True,
                        "fix_action": lambda: self.insert_step(workflow, i+1, bridge)
                    })
                else:
                    issues.append({
                        "type": "error",
                        "severity": "critical",
                        "step": i,
                        "issue": f"Step {i} outputs {current_outputs} but step {i+1} requires {next_inputs}",
                        "suggestion": "These tools cannot be chained. Please select compatible tools.",
                        "auto_fix": False
                    })

        return issues

    def validate_scientific_logic(self, workflow, context):
        """Validate that workflow makes scientific sense"""
        issues = []

        # Rule 1: DIA data should not use DDA tools
        if context.data_type == "DIA":
            dda_only_tools = ["maxquant", "proteome_discoverer", "msgf_plus"]
            for step in workflow.steps:
                if step.tool.id in dda_only_tools:
                    issues.append({
                        "type": "error",
                        "severity": "critical",
                        "step": step.index,
                        "issue": f"{step.tool.name} is designed for DDA data, but you have DIA data",
                        "suggestion": f"Replace with DIA-specific tool like DIA-NN or Spectronaut",
                        "alternatives": self.get_alternatives(step.tool, context)
                    })

        # Rule 2: TMT/iTRAQ experiments need reporter ion quantification
        if self.has_isobaric_labeling(context):
            has_reporter_quant = any(
                step.tool.category == "isobaric_quantification"
                for step in workflow.steps
            )
            if not has_reporter_quant:
                issues.append({
                    "type": "error",
                    "severity": "high",
                    "issue": "TMT/iTRAQ experiment detected but no reporter ion quantification step",
                    "suggestion": "Add reporter ion quantification step after search"
                })

        # Rule 3: Check for redundant normalization
        normalization_steps = [
            step for step in workflow.steps
            if step.tool.category == "normalization"
        ]
        if len(normalization_steps) > 1:
            issues.append({
                "type": "warning",
                "severity": "medium",
                "issue": f"Multiple normalization steps detected: {[s.tool.name for s in normalization_steps]}",
                "suggestion": "Typically only one normalization method is needed. Consider removing redundant steps."
            })

        # Rule 4: Statistical analysis needs replicates
        stats_steps = [
            step for step in workflow.steps
            if step.tool.category == "statistical_analysis"
        ]
        if stats_steps and context.num_replicates < 2:
            issues.append({
                "type": "warning",
                "severity": "high",
                "issue": "Statistical analysis requires replicates, but only 1 sample per condition detected",
                "suggestion": "Statistical tests are not meaningful with n=1. Consider removing statistical analysis or confirming you have replicates."
            })

        return issues

    def generate_validation_report(self, issues):
        """Generate human-readable validation report"""

        critical = [i for i in issues if i["severity"] == "critical"]
        high = [i for i in issues if i["severity"] == "high"]
        medium = [i for i in issues if i["severity"] == "medium"]

        report = {
            "can_execute": len(critical) == 0,
            "summary": {
                "critical_issues": len(critical),
                "warnings": len(high) + len(medium)
            },
            "issues": issues,
            "recommendations": self.generate_recommendations(issues)
        }

        return report
```

### 5.2 Auto-Fix Capabilities

```python
class WorkflowAutoFixer:
    """
    Automatically fix common workflow issues when possible
    """

    def auto_fix(self, workflow, issues):
        fixes_applied = []

        for issue in issues:
            if issue.get("auto_fix"):
                if issue["type"] == "missing_conversion":
                    # Auto-insert format conversion step
                    converter_tool = issue["fix_tool"]
                    workflow.insert_step(issue["position"], converter_tool)
                    fixes_applied.append({
                        "issue": issue["issue"],
                        "fix": f"Inserted {converter_tool.name} at step {issue['position']}"
                    })

                elif issue["type"] == "redundant_step":
                    # Auto-remove redundant step
                    workflow.remove_step(issue["step_index"])
                    fixes_applied.append({
                        "issue": issue["issue"],
                        "fix": f"Removed redundant step: {issue['tool_name']}"
                    })

                elif issue["type"] == "parameter_out_of_range":
                    # Auto-correct parameter to valid range
                    step = workflow.steps[issue["step"]]
                    step.parameters[issue["parameter"]] = issue["suggested_value"]
                    fixes_applied.append({
                        "issue": issue["issue"],
                        "fix": f"Corrected {issue['parameter']} to {issue['suggested_value']}"
                    })

        return fixes_applied
```

---

## 6. Learning System

### 6.1 Feedback Loop

```python
class WorkflowLearningSystem:
    """
    Learn from user corrections and successful workflows
    """

    def record_correction(self, workflow_id, step_index, correction):
        """Record when user corrects Claude's suggestion"""

        correction_record = {
            "timestamp": datetime.now(),
            "workflow_id": workflow_id,
            "step_index": step_index,
            "original_tool": correction["original_tool"],
            "corrected_tool": correction["corrected_tool"],
            "context": correction["context"],  # data_type, organism, goal
            "user_explanation": correction.get("explanation"),
            "confidence": 1.0  # High confidence - direct user feedback
        }

        # Store in correction log
        self.store_correction(correction_record)

        # Extract learning rule
        rule = self.extract_rule(correction_record)
        self.update_rules(rule)

    def record_successful_workflow(self, workflow_id):
        """Record when workflow executes successfully"""
        workflow = self.get_workflow(workflow_id)

        # Reinforce tool choices made in this workflow
        for step in workflow.steps:
            self.reinforce_tool_choice(
                task=step.task,
                tool=step.tool,
                context=workflow.context,
                weight=0.1  # Small reinforcement
            )

    def record_failed_workflow(self, workflow_id, failure_reason):
        """Record when workflow fails"""
        workflow = self.get_workflow(workflow_id)

        # Identify problematic tool choices
        if failure_reason["type"] == "tool_error":
            problematic_step = failure_reason["step"]
            self.penalize_tool_choice(
                task=problematic_step.task,
                tool=problematic_step.tool,
                context=workflow.context,
                weight=0.2
            )

    def extract_rule(self, correction):
        """Extract reusable rule from correction"""

        # Example: User corrected MaxQuant → DIA-NN for DIA data
        if correction["context"]["data_type"] == "DIA":
            if "maxquant" in correction["original_tool"]:
                return {
                    "rule_type": "constraint",
                    "condition": "data_type == 'DIA' AND task == 'database_search'",
                    "avoid_tools": ["maxquant", "proteome_discoverer"],
                    "prefer_tools": ["dia_nn", "spectronaut"],
                    "reason": "DDA tools incompatible with DIA data",
                    "confidence": 0.95
                }

        return None

    def get_learned_preferences(self, user_id, context):
        """Get learned preferences for tool selection"""

        preferences = self.query_preferences(
            user_id=user_id,
            context=context
        )

        return preferences
```

---

## 7. User Interface Improvements

### 7.1 Progressive Disclosure UI

```typescript
// Workflow Builder Component
interface WorkflowBuilderState {
  mode: 'wizard' | 'advanced';
  currentStep: number;
  workflow: Workflow;
  validationIssues: ValidationIssue[];
}

// Wizard Mode (Beginner-friendly)
const WizardMode = () => {
  return (
    <div>
      <ProgressIndicator
        steps={[
          "Understand Data",
          "Choose Tools",
          "Set Parameters",
          "Review",
          "Execute"
        ]}
        current={currentStep}
      />

      {currentStep === 0 && <DataUnderstandingQuestions />}
      {currentStep === 1 && <ToolSelectionSuggestions />}
      {currentStep === 2 && <ParameterConfiguration />}
      {currentStep === 3 && <WorkflowReview />}
      {currentStep === 4 && <ExecutionPanel />}
    </div>
  );
};

// Advanced Mode (Experienced users)
const AdvancedMode = () => {
  return (
    <div>
      <WorkflowGraph />  {/* Full workflow editor */}
      <ToolPalette />    {/* Drag-and-drop tools */}
      <ParameterPanel /> {/* All parameters visible */}
    </div>
  );
};
```

### 7.2 Validation Feedback UI

```typescript
const ValidationReport = ({ issues }) => {
  const critical = issues.filter(i => i.severity === 'critical');
  const warnings = issues.filter(i => i.severity === 'medium');

  return (
    <div className="validation-report">
      {critical.length > 0 && (
        <Alert severity="error">
          <AlertTitle>Critical Issues - Cannot Execute</AlertTitle>
          {critical.map(issue => (
            <IssueCard key={issue.id} issue={issue}>
              <IssueDescription>{issue.issue}</IssueDescription>
              <Suggestion>{issue.suggestion}</Suggestion>
              {issue.auto_fix && (
                <Button onClick={() => applyAutoFix(issue)}>
                  Auto-Fix
                </Button>
              )}
            </IssueCard>
          ))}
        </Alert>
      )}

      {warnings.length > 0 && (
        <Alert severity="warning">
          <AlertTitle>Warnings - Review Recommended</AlertTitle>
          {warnings.map(issue => (
            <IssueCard key={issue.id} issue={issue}>
              <IssueDescription>{issue.issue}</IssueDescription>
              <Suggestion>{issue.suggestion}</Suggestion>
              <ButtonGroup>
                <Button onClick={() => acceptWarning(issue)}>
                  Proceed Anyway
                </Button>
                <Button onClick={() => applyFix(issue)}>
                  Apply Suggestion
                </Button>
              </ButtonGroup>
            </IssueCard>
          ))}
        </Alert>
      )}
    </div>
  );
};
```

---

## 8. Implementation Roadmap

### Phase 1: Foundation (2-3 weeks)
**Goal:** Establish core infrastructure for intelligent workflow generation

**Week 1: Tool Metadata Enrichment**
- [ ] Design extended tool schema
- [ ] Create tool metadata migration script
- [ ] Enrich top 50 most-used tools with full metadata
- [ ] Build tool relationship graph

**Week 2: Context Management**
- [ ] Implement user profile system
- [ ] Create session context management
- [ ] Build correction logging system
- [ ] Implement conversation compaction

**Week 3: Validation Framework**
- [ ] Implement multi-layer validator
- [ ] Create validation rules engine
- [ ] Build auto-fix system
- [ ] Create validation report UI

### Phase 2: Iterative Workflow Generation (2-3 weeks)
**Goal:** Enable step-by-step collaborative workflow building

**Week 4: Question Generation**
- [ ] Implement question generator
- [ ] Create question UI components
- [ ] Build smart question skipping logic
- [ ] Add question routing to Claude prompts

**Week 5: Progressive Workflow Building**
- [ ] Implement phased workflow generation
- [ ] Create step-by-step validation checkpoints
- [ ] Build workflow draft → review → refine flow
- [ ] Add real-time validation feedback

**Week 6: Parameter Intelligence**
- [ ] Implement instrument-based parameter defaults
- [ ] Create parameter explanation system
- [ ] Build parameter validation rules
- [ ] Add parameter recommendation UI

### Phase 3: Learning System (2 weeks)
**Goal:** Enable system to learn from corrections and successes

**Week 7: Feedback Collection**
- [ ] Implement correction tracking
- [ ] Build workflow outcome logging
- [ ] Create feedback UI components
- [ ] Add user preference learning

**Week 8: Rule Extraction**
- [ ] Implement rule extraction from corrections
- [ ] Build preference inference system
- [ ] Create rule confidence scoring
- [ ] Add learned rule application to generation

### Phase 4: UI/UX Improvements (1-2 weeks)
**Goal:** Make interface intuitive and helpful

**Week 9: Progressive Disclosure**
- [ ] Create wizard mode UI
- [ ] Build advanced mode toggle
- [ ] Implement contextual help system
- [ ] Add workflow explanation tooltips

**Week 10: Polish & Testing**
- [ ] End-to-end testing of all flows
- [ ] User testing with scientists
- [ ] Performance optimization
- [ ] Documentation

---

## 9. System Prompts for Claude

### 9.1 Main System Prompt

```markdown
You are a proteomics workflow assistant helping scientists analyze mass spectrometry data using Galaxy tools.

## Your Role

You are NOT just generating workflows - you are COLLABORATING with scientists to build optimal workflows through:
1. Understanding their data and goals through questions
2. Suggesting appropriate tools based on scientific context
3. Explaining your choices and reasoning
4. Validating workflows before execution
5. Learning from corrections and feedback

## Available Context

You have access to:
- **Tool Catalog**: {{tools_catalog}} - All available Galaxy tools with full metadata
- **User Profile**: {{user_profile}} - User's research area, preferences, past workflows
- **Session Context**: {{session_context}} - Current conversation summary
- **Workflow History**: {{workflow_history}} - User's past workflows and outcomes
- **Correction Log**: {{correction_log}} - Mistakes you made that user corrected

## Workflow Generation Process

### Phase 1: Clarification
ALWAYS start by understanding the user's needs:

1. **Data Type**: What acquisition mode? (DDA, DIA, targeted, etc.)
2. **Analysis Goal**: Identification, quantification, PTMs?
3. **Organism**: What species?
4. **Experimental Design**: How many conditions? Replicates?

Ask questions if ANY of these are unclear from the query.

### Phase 2: Draft Workflow
Create a high-level workflow structure:
- Show 4-6 major steps
- Explain the purpose of each step
- Get user confirmation before detailing

### Phase 3: Step-by-Step Building
For each step:
1. **Propose Tool**: "For [task], I suggest [tool] because [reason]"
2. **Explain Parameters**: Show key parameters with explanations
3. **Validate**: Check if step makes sense to user
4. **Refine**: Adjust based on feedback

### Phase 4: Final Validation
Before execution:
1. Check tool chain compatibility
2. Detect redundant steps
3. Validate scientific logic
4. Confirm with user

## Tool Selection Rules

### Critical Rules (NEVER VIOLATE):
1. **DIA data → DIA tools**: DIA-NN, Spectronaut, OpenSWATH (NOT MaxQuant, MSGF+)
2. **DDA data → DDA tools**: MaxQuant, MSFragger, MSGF+ (NOT DIA-NN)
3. **TMT/iTRAQ → Reporter ion quantification required**
4. **Output format must match next tool's input**

### Learned Rules (from user corrections):
{{learned_rules}}

### User Preferences (apply when appropriate):
{{user_preferences}}

## When You Make Mistakes

If the user corrects you:
1. **Acknowledge**: "You're right, [tool] is not appropriate for [reason]"
2. **Explain**: "I suggested it because [my reasoning], but I should have considered [correct reasoning]"
3. **Learn**: Store the correction for future workflows
4. **Apply**: Use the corrected approach immediately

## Validation Before Generation

ALWAYS validate:
- ✓ Tool compatibility (output → input formats match)
- ✓ Scientific appropriateness (tool matches data type)
- ✓ No redundancy (similar tools not repeated)
- ✓ Parameter validity (values in acceptable ranges)

## Communication Style

- **Be collaborative, not prescriptive**: "I suggest X because Y. Does that make sense?"
- **Explain your reasoning**: "I chose DIA-NN because you have DIA data"
- **Ask when uncertain**: "I'm not sure about X. Could you clarify?"
- **Learn from corrections**: "Thank you for that correction. I'll use [tool] for [task] in future workflows."

## Current Conversation Context

{{conversation_summary}}

## Your Task

The user's latest message is: {{user_query}}

Think through:
1. What do I know about their needs?
2. What questions do I still need to ask?
3. What tools are appropriate given the context?
4. Are there any potential issues to flag?

Then respond conversationally, following the workflow generation process above.
```

### 9.2 Validation Prompt

```markdown
You are validating a proposed proteomics workflow. Check for:

## Workflow to Validate
{{workflow_json}}

## Context
- Data type: {{data_type}}
- Organism: {{organism}}
- User goal: {{user_goal}}

## Validation Checks

### 1. Tool Chain Compatibility
For each consecutive pair of steps, verify:
- Step outputs match next step inputs (format compatibility)
- No missing conversion steps

### 2. Scientific Validity
Check:
- DIA data doesn't use DDA tools
- DDA data doesn't use DIA tools
- TMT experiments have reporter ion quantification
- Correct organism database is specified

### 3. Redundancy Detection
Identify:
- Multiple tools performing same function
- Unnecessary intermediate steps
- Duplicate normalization/processing

### 4. Parameter Validity
Verify:
- Mass tolerances match instrument type
- FDR thresholds are reasonable (0.01-0.05)
- Enzyme specificity matches experimental design

### 5. Resource Requirements
Estimate:
- Runtime (per sample)
- Memory requirements
- Disk space needed

## Output Format

Return validation report as JSON:
{
  "valid": true/false,
  "can_execute": true/false,
  "issues": [
    {
      "severity": "critical|high|medium|low",
      "type": "incompatibility|scientific_error|redundancy|parameter_issue",
      "step": step_index,
      "description": "Human-readable issue",
      "suggestion": "How to fix",
      "auto_fixable": true/false
    }
  ],
  "warnings": [...],
  "estimated_runtime": "2-3 hours",
  "estimated_resources": {...}
}
```

---

## 10. Success Metrics

### Quantitative Metrics
- **Workflow Quality**: % of workflows that execute successfully without errors
- **User Corrections**: Number of corrections per workflow (lower is better)
- **Redundancy**: % of workflows with redundant steps (target: <5%)
- **Validation Catch Rate**: % of issues caught before execution
- **Learning Rate**: Improvement in recommendations over time

### Qualitative Metrics
- **User Satisfaction**: Survey responses on workflow quality
- **Trust**: Do users feel confident in Claude's suggestions?
- **Efficiency**: Time to generate acceptable workflow
- **Educational Value**: Do users learn from Claude's explanations?

### Target Goals (6 months)
- 95% of workflows execute without errors
- <0.5 corrections per workflow on average
- <10% workflows with redundancy
- 90%+ user satisfaction rating
- 50% reduction in time to create workflow

---

## Conclusion

By implementing these Claude Code-inspired capabilities, the platform transforms from a simple "workflow generator" into an **intelligent scientific collaborator** that:

1. **Understands context** through memory and learning
2. **Asks smart questions** to clarify requirements
3. **Builds iteratively** with user validation
4. **Validates rigorously** before execution
5. **Learns continuously** from mistakes and successes
6. **Explains clearly** the reasoning behind choices

This creates a **collaborative experience** where Claude and the scientist work together to create optimal workflows, rather than Claude simply generating a workflow that the user must accept or reject.

The key insight: **The value is not in generating perfect workflows automatically, but in collaborating effectively to build workflows that meet the scientist's specific needs while teaching and learning along the way.**