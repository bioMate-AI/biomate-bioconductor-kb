# Frontend-Backend Architecture & Optimization Plan (2025-10-13)

## Executive Summary

BioMate uses a **three-tier architecture** with a React frontend, Express middleware layer, and Galaxy Python backend. The analysis reveals excellent infrastructure but opportunities for workflow optimization, especially for dataset query parameter generation and user feedback loops.

### Architecture Layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Frontend (React + TypeScript)                              │
│  - Enhanced Workflow Builder                                 │
│  - Real-time SSE updates                                     │
│  - Parameter configuration UI                                 │
└─────────────────────────────────────────────────────────────┘
                          ↓ HTTP/SSE
┌─────────────────────────────────────────────────────────────┐
│  Middleware (Express + Node.js)                             │
│  - Galaxy API Proxy (galaxy-api-proxy.ts)                   │
│  - Workflow SSE Manager (workflow-sse.ts)                   │
│  - State Polling (galaxy-state-poller.ts)                   │
└─────────────────────────────────────────────────────────────┘
                          ↓ HTTP
┌─────────────────────────────────────────────────────────────┐
│  Backend (Galaxy Python)                                     │
│  - AI Assistant API (/api/ai_assistant/*)                   │
│  - Tool Search API (/api/tool_search/*)                     │
│  - Dataset API (/api/datasets/*)                            │
│  - Workflow API (/api/workflows/*)                          │
│  - Job Execution (Galaxy Core)                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Part 1: Current Workflow Generation Flow

### Step-by-Step Execution

**User Action:** "Get kinase inhibitors from BindingDB and dock compounds"

```typescript
// 1. Frontend (enhanced-workflow-builder.tsx)
const handleGenerate = async () => {
  setGenerating(true);

  const response = await galaxyAPI.generateWorkflow({
    user_intent: userInput,
    datasets: selectedDatasets,
    max_tools_search: 30
  });

  if (response.success) {
    setWorkflowGa(response.workflow_ga);
    setWorkflowSteps(response.workflow_structure.steps);
  }
};
```

```typescript
// 2. Middleware (galaxy-api-proxy.ts)
async generateWorkflow(request: WorkflowGenerationRequest) {
  const backendRequest = {
    request_text: request.user_intent,
    available_datasets: request.datasets || [],
    constraints: {
      max_tools_search: request.max_tools_search || 30
    }
  };

  const response = await this.client.post(
    '/api/ai_assistant/generate_workflow',  // ✅ Unified endpoint
    backendRequest
  );

  return response.data;
}
```

```python
# 3. Backend (ai_assistant.py)
@router.post("/api/ai_assistant/generate_workflow")
def generate_workflow_unified(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
):
    ai_assistant = get_ai_assistant(trans)

    # Unified workflow generation with search-first approach
    result = ai_assistant.generate_workflow_unified(
        user_intent=request.request_text,
        uploaded_datasets=request.available_datasets
    )

    return result
```

```python
# 4. AI Assistant (ai_assistant.py: generate_workflow_unified)
def generate_workflow_unified(self, user_intent: str) -> Dict:
    # Step 1: Search existing templates
    search_results = self.workflow_search.search(user_intent, limit=5)
    score = search_results[0]['score'] if search_results else 0.0

    # Step 2: Decide strategy based on template match
    if score > 0.8:
        # High confidence - reuse template
        workflow_ga = self._build_workflow_ga_from_template(...)
        dataset_assignments = self.dataset_selector.select_datasets_for_workflow(...)

    elif score > 0.5:
        # Medium confidence - adapt template
        workflow_result = self.workflow_generator.generate_workflow(...)
        dataset_assignments = self.dataset_selector.select_datasets_for_workflow(...)

    else:
        # Low confidence - generate from scratch with tool constraint
        result = self.constrained_generator.generate_workflow(
            user_intent=user_intent,
            max_tools_search=30
        )
        workflow_ga = result['workflow_ga']

    return {
        'success': True,
        'workflow_ga': workflow_ga,
        'source': source,
        'confidence': score,
        'datasets_assigned': True
    }
```

```python
# 5. Constrained Generator (galaxy_workflow_generator.py)
def generate_workflow(self, user_intent: str) -> Dict:
    # Step 5.1: Search for tools
    fts_query = self._transform_intent_to_fts_query(user_intent)
    tools = self._search_tools(fts_query, max_results=max_tools_search)

    # Step 5.2: Generate workflow structure using LLM
    workflow_structure = self._generate_workflow_structure(user_intent, tools)

    # Step 5.3: Build Galaxy .ga JSON with parameter templates
    workflow_ga = self._build_galaxy_workflow_json(workflow_structure, {})
    # ⚠️ PROBLEM: Parameters use defaults, not LLM-generated!

    return {
        'success': True,
        'workflow_ga': workflow_ga,
        'workflow_structure': workflow_structure
    }
```

```python
# 6. Parameter Generation (CURRENT - Uses defaults)
def _build_galaxy_workflow_json(self, workflow_structure, dataset_assignments):
    for step in workflow_structure['steps']:
        tool_id = step['tool_id']

        # Get tool parameters from database
        tool_params, tool_help = self._get_tool_parameters_and_help(tool_id)

        # Build tool_state with DEFAULT values
        tool_state = self._build_tool_state(tool_params)
        # Returns: {"query_mode": "all", "filter_column": "", "filter_value": ""}
        # ❌ NOT using LLM to infer from user intent!
```

---

## Part 2: Current Problems

### Problem 1: Dataset Query Parameters Not Generated

**Issue**: When dataset tools are included in workflows, their query parameters use defaults instead of being inferred from user intent.

**Example**:
```python
# User intent: "Get kinase inhibitors from BindingDB"

# What's generated:
{
  "steps": {
    "0": {
      "tool_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
      "tool_state": {
        "query_mode": "all",        # ← Wrong! Returns entire 5.8GB dataset
        "filter_column": "",         # ← Empty!
        "filter_value": ""           # ← Empty!
      }
    }
  }
}

# What SHOULD be generated:
{
  "steps": {
    "0": {
      "tool_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
      "tool_state": {
        "query_mode": "filter",      # ← LLM inferred!
        "filter_column": "Target",   # ← LLM inferred!
        "filter_value": "kinase*"    # ← LLM inferred!
      }
    }
  }
}
```

---

### Problem 2: No User Confirmation Before Execution

**Issue**: Workflow executes immediately without showing user the generated query parameters.

**Current Flow**:
```
User: "Get kinase inhibitors"
  ↓
Generate workflow with default parameters
  ↓
Execute immediately
  ↓
Returns 2.5 million rows (entire dataset!)
  ↓
Next tool fails: "Too many input ligands"
```

**Desired Flow**:
```
User: "Get kinase inhibitors"
  ↓
Generate workflow with LLM-inferred parameters
  ↓
Show user BEFORE execution:
  ┌────────────────────────────────────────────┐
  │ ⚠️ Query Parameters Preview                │
  │                                            │
  │ Step 1: Query BindingDB                   │
  │   Mode: Filter                            │
  │   Column: Target                          │
  │   Value: kinase*                          │
  │   Estimated rows: ~15,000                  │
  │                                            │
  │ [Edit Parameters] [Execute] [Cancel]      │
  └────────────────────────────────────────────┘
  ↓
User confirms
  ↓
Execute workflow
  ↓
Returns 15,000 rows (correct!)
```

---

### Problem 3: No Dataset Availability Validation

**Issue**: Workflow generator doesn't check if datasets exist or APIs are reachable.

**Current Behavior**:
```
User: "Analyze DepMap cancer dependencies"
  ↓
Generate workflow with tool: biomate_dm_biomni_data_lake_DepMap_CRISPRGeneDependency
  ↓
Workflow created successfully ✅
  ↓
User clicks "Execute"
  ↓
FileNotFoundError: Dataset not found ❌
```

**Desired Behavior**:
```
User: "Analyze DepMap cancer dependencies"
  ↓
Generate workflow
  ↓
Validation: Check if /private/tmp/.../DepMap_CRISPRGeneDependency.csv exists
  ↓
File not found! Search for alternatives:
  - API alternative: biomate_datasource_api_depmap ✅
  - Test API: https://depmap.org/api ✅
  ↓
Replace local dataset with API query
  ↓
Show user:
  ┌────────────────────────────────────────────┐
  │ ⚠️ Dataset Substitution                    │
  │                                            │
  │ Original: DepMap local dataset            │
  │ Status: Not available                     │
  │                                            │
  │ Alternative: DepMap API                   │
  │ Status: Available ✅                       │
  │                                            │
  │ [Accept Alternative] [Cancel]             │
  └────────────────────────────────────────────┘
```

---

## Part 3: Optimization Opportunities

### Opportunity 1: Add Parameter Preview Dialog (Frontend Enhancement)

**Impact**: HIGH - Improves user control and reduces failed executions
**Effort**: 2-3 days

**Implementation**:

```typescript
// frontend/client/src/components/parameter-preview-dialog.tsx

interface ParameterPreviewDialogProps {
  workflowSteps: WorkflowStep[];
  onConfirm: () => void;
  onEdit: (stepId: number, parameters: any) => void;
  onCancel: () => void;
}

export function ParameterPreviewDialog({ workflowSteps, onConfirm, onEdit, onCancel }: ParameterPreviewDialogProps) {
  return (
    <Dialog>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>⚠️ Review Workflow Parameters</DialogTitle>
          <DialogDescription>
            Please review the auto-generated parameters before execution
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-4">
          {workflowSteps.map((step, idx) => (
            <Card key={idx}>
              <CardHeader>
                <CardTitle>Step {idx + 1}: {step.tool_name}</CardTitle>
              </CardHeader>
              <CardContent>
                {/* Show parameters */}
                <div className="space-y-2">
                  {Object.entries(step.tool_state).map(([param, value]) => (
                    <div key={param} className="flex justify-between">
                      <span className="font-medium">{param}:</span>
                      <span>{value || <em className="text-gray-400">empty</em>}</span>
                    </div>
                  ))}
                </div>

                {/* Show dataset query estimation */}
                {step.tool_type === 'data_source' && (
                  <Alert className="mt-4">
                    <AlertDescription>
                      📊 Estimated result size: {estimateQuerySize(step.tool_state)}
                    </AlertDescription>
                  </Alert>
                )}

                {/* Edit button */}
                <Button
                  variant="outline"
                  className="mt-4"
                  onClick={() => onEdit(idx, step.tool_state)}
                >
                  Edit Parameters
                </Button>
              </CardContent>
            </Card>
          ))}
        </div>

        <DialogFooter>
          <Button variant="outline" onClick={onCancel}>Cancel</Button>
          <Button onClick={onConfirm}>Execute Workflow</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
```

---

### Opportunity 2: Implement LLM Query Parameter Generation (Backend Enhancement)

**Impact**: HIGH - Enables automated parameter inference
**Effort**: 5-8 days

**Implementation**:

```python
# backend/lib/galaxy/ai/galaxy_workflow_generator.py

def _build_galaxy_workflow_json(
    self,
    workflow_structure: Dict[str, Any],
    dataset_assignments: Dict[str, Any],
    user_intent: str  # NEW: Pass user intent
) -> Dict[str, Any]:

    for step in workflow_structure.get('steps', []):
        tool_id = step['tool_id']

        # Get tool parameters
        tool_params, tool_help = self._get_tool_parameters_and_help(tool_id)

        # NEW: Check if this is a dataset tool
        if self._is_dataset_tool(tool_id):
            # Generate parameters using LLM based on user intent
            tool_state = self._llm_generate_dataset_parameters(
                tool_id=tool_id,
                user_intent=user_intent,
                available_params=tool_params,
                tool_help=tool_help
            )
        else:
            # Regular tool - use defaults
            tool_state = self._build_tool_state(tool_params)

        # Build step with generated parameters
        galaxy_steps[str(step_num)] = {
            'id': step_num,
            'tool_id': tool_id,
            'tool_state': json.dumps(tool_state),
            'annotation': step.get('purpose', '')
        }

    return galaxy_workflow


def _llm_generate_dataset_parameters(
    self,
    tool_id: str,
    user_intent: str,
    available_params: List[Dict],
    tool_help: Dict
) -> Dict[str, Any]:
    """
    Use LLM to generate dataset query parameters based on user intent.
    """

    # Extract dataset metadata
    dataset_name = tool_id.split('_')[-1]
    available_columns = tool_help.get('columns', [])

    prompt = f"""Generate query parameters for a dataset tool.

User Intent: "{user_intent}"

Dataset: {dataset_name}
Available Columns: {', '.join(available_columns)}

Available Parameters:
{json.dumps(available_params, indent=2)}

Task: Infer appropriate query parameters based on the user's intent.

Guidelines:
1. If user mentions specific criteria (e.g., "kinase", "brain"), use filter mode
2. If user wants exploratory analysis, use sample mode
3. Match column names (e.g., "target" for protein targets, "tissue" for tissues)
4. Use wildcards (*) for broad matches

Return JSON with parameter values:
{{
  "query_mode": "filter|sample|head|all",
  "filter_column": "column_name",
  "filter_value": "value_or_pattern*",
  "sample_size": 1000
}}

Example inferences:
- "kinase inhibitors" → filter_column="Target", filter_value="kinase*"
- "brain tissue" → filter_column="Tissue", filter_value="brain*"
- "explore dataset" → query_mode="sample", sample_size=1000
"""

    try:
        response = self.client.messages.create(
            model=self.model,
            max_tokens=500,
            messages=[{"role": "user", "content": prompt}]
        )

        params_json = response.content[0].text
        params = json.loads(params_json)

        # Validate parameters
        if not self._validate_dataset_params(params, available_params):
            log.warning(f"Invalid LLM parameters, using defaults")
            return self._build_tool_state(available_params)

        log.info(f"LLM generated parameters for {tool_id}: {params}")
        return params

    except Exception as e:
        log.error(f"LLM dataset parameter generation failed: {e}")
        return self._build_tool_state(available_params)


def _validate_dataset_params(self, params: Dict, available_params: List[Dict]) -> bool:
    """Validate that LLM-generated parameters are valid."""

    # Check query_mode is valid
    valid_modes = ["all", "filter", "sample", "head"]
    if params.get("query_mode") not in valid_modes:
        return False

    # If filter mode, require filter_column and filter_value
    if params.get("query_mode") == "filter":
        if not params.get("filter_column") or not params.get("filter_value"):
            return False

    # If sample mode, require sample_size
    if params.get("query_mode") == "sample":
        if not isinstance(params.get("sample_size"), int):
            return False

    return True
```

---

### Opportunity 3: Add Dataset Availability Validation (Backend Enhancement)

**Impact**: MEDIUM - Prevents execution failures
**Effort**: 3-5 days

**Implementation**:

```python
# backend/lib/galaxy/ai/galaxy_workflow_generator.py

def generate_workflow(
    self,
    user_intent: str,
    max_tools_search: int = 30
) -> Dict[str, Any]:

    # ... existing code ...

    # Step 1: Search for tools
    tools = self._search_tools(fts_query, max_results=max_tools_search)

    # NEW: Validate dataset availability
    validated_tools, warnings = self._validate_dataset_tools(tools, user_intent)

    # Step 2: Generate workflow with validated tools
    workflow_structure = self._generate_workflow_structure(
        user_intent,
        validated_tools
    )

    # Return with validation warnings
    return {
        'success': True,
        'workflow_ga': workflow_ga,
        'validation_warnings': warnings,  # NEW
        'dataset_substitutions': substitutions  # NEW
    }


def _validate_dataset_tools(
    self,
    tools: List[Dict],
    user_intent: str
) -> Tuple[List[Dict], List[str]]:
    """Validate dataset tool availability and suggest fallbacks."""

    validated = []
    warnings = []
    substitutions = []

    for tool in tools:
        if tool['tool_type'] != 'data_source':
            validated.append(tool)
            continue

        # Check local dataset
        if tool['tool_id'].startswith('biomate_dm_'):
            dataset_path = self._extract_dataset_path(tool['tool_id'])

            if os.path.exists(dataset_path):
                validated.append(tool)
                log.info(f"Local dataset available: {dataset_path}")
            else:
                log.warning(f"Local dataset not found: {dataset_path}")

                # Try API fallback
                api_alternative = self._find_api_alternative(tool, user_intent)
                if api_alternative:
                    validated.append(api_alternative)
                    warnings.append(f"Using API: {api_alternative['name']}")
                    substitutions.append({
                        'original': tool['name'],
                        'alternative': api_alternative['name'],
                        'reason': 'Local dataset not available'
                    })
                else:
                    # Remove from workflow
                    warnings.append(f"Dataset unavailable, removed: {tool['name']}")

        # Check API availability
        elif tool['tool_id'].startswith('biomate_datasource_api_'):
            api_url = self._get_api_url(tool['tool_id'])

            if self._test_api_connection(api_url, timeout=5):
                validated.append(tool)
                log.info(f"API available: {api_url}")
            else:
                log.warning(f"API not reachable: {api_url}")

                # Try local fallback
                local_alternative = self._find_local_alternative(tool, user_intent)
                if local_alternative:
                    validated.append(local_alternative)
                    warnings.append(f"Using local: {local_alternative['name']}")
                    substitutions.append({
                        'original': tool['name'],
                        'alternative': local_alternative['name'],
                        'reason': 'API not reachable'
                    })
                else:
                    warnings.append(f"API unavailable, removed: {tool['name']}")

    return validated, warnings, substitutions


def _test_api_connection(self, api_url: str, timeout: int = 5) -> bool:
    """Test if API is reachable."""
    try:
        import requests
        response = requests.get(api_url, timeout=timeout)
        return response.status_code == 200
    except Exception as e:
        log.debug(f"API connection test failed: {e}")
        return False
```

---

### Opportunity 4: Add Parameter Estimation (Backend Helper)

**Impact**: MEDIUM - Helps users understand query size
**Effort**: 2-3 days

**Implementation**:

```python
# backend/lib/galaxy/ai/dataset_query_estimator.py

class DatasetQueryEstimator:
    """Estimate dataset query result sizes."""

    def __init__(self, db_path: str):
        self.db_path = db_path
        self.dataset_stats = self._load_dataset_stats()

    def _load_dataset_stats(self) -> Dict[str, Dict]:
        """Load dataset statistics from database."""
        import sqlite3
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        cursor.execute("""
            SELECT dataset_id, total_rows, file_size_mb, columns
            FROM dataset_statistics
        """)

        stats = {}
        for row in cursor.fetchall():
            stats[row[0]] = {
                'total_rows': row[1],
                'file_size_mb': row[2],
                'columns': json.loads(row[3])
            }

        conn.close()
        return stats

    def estimate_query_size(
        self,
        dataset_id: str,
        query_params: Dict[str, Any]
    ) -> Dict[str, Any]:
        """Estimate result size for a dataset query."""

        if dataset_id not in self.dataset_stats:
            return {'estimated_rows': 'unknown', 'confidence': 0.0}

        stats = self.dataset_stats[dataset_id]
        total_rows = stats['total_rows']

        query_mode = query_params.get('query_mode', 'all')

        if query_mode == 'all':
            return {
                'estimated_rows': total_rows,
                'estimated_size_mb': stats['file_size_mb'],
                'confidence': 1.0,
                'warning': 'Returns entire dataset - may be very large!'
            }

        elif query_mode == 'sample':
            sample_size = query_params.get('sample_size', 1000)
            return {
                'estimated_rows': sample_size,
                'estimated_size_mb': (sample_size / total_rows) * stats['file_size_mb'],
                'confidence': 1.0
            }

        elif query_mode == 'head':
            sample_size = query_params.get('sample_size', 1000)
            return {
                'estimated_rows': min(sample_size, total_rows),
                'estimated_size_mb': (sample_size / total_rows) * stats['file_size_mb'],
                'confidence': 1.0
            }

        elif query_mode == 'filter':
            # Estimate based on filter selectivity
            filter_column = query_params.get('filter_column', '')
            filter_value = query_params.get('filter_value', '')

            selectivity = self._estimate_filter_selectivity(
                dataset_id,
                filter_column,
                filter_value
            )

            estimated_rows = int(total_rows * selectivity)

            return {
                'estimated_rows': estimated_rows,
                'estimated_size_mb': selectivity * stats['file_size_mb'],
                'confidence': 0.7,  # Lower confidence for filters
                'note': f'Estimated based on {selectivity*100:.1f}% selectivity'
            }

        return {'estimated_rows': 'unknown', 'confidence': 0.0}

    def _estimate_filter_selectivity(
        self,
        dataset_id: str,
        column: str,
        value: str
    ) -> float:
        """Estimate what fraction of rows will match the filter."""

        # Simple heuristic-based estimation
        # In production, this would use column statistics from database

        if '*' in value:
            # Wildcard filter - assume 5-10% match
            return 0.075
        else:
            # Exact match - assume 1% match
            return 0.01
```

**Add API endpoint**:

```python
# backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py

@router.post("/api/ai_assistant/estimate_query_size")
def estimate_query_size(
    request: QueryEstimationRequest,
    trans: ProvidesUserContext = DependsOnTrans
):
    """Estimate result size for a dataset query."""

    from galaxy.ai.dataset_query_estimator import DatasetQueryEstimator

    estimator = DatasetQueryEstimator(trans.app.config.ai_tools_db_path)

    estimation = estimator.estimate_query_size(
        dataset_id=request.dataset_id,
        query_params=request.query_params
    )

    return estimation
```

---

## Part 4: Frontend Integration

### Updated Workflow Generation Flow

```typescript
// frontend/client/src/components/enhanced-workflow-builder.tsx

const handleGenerate = async () => {
  setGenerating(true);

  try {
    // Step 1: Generate workflow with LLM-inferred parameters
    const response = await galaxyAPI.generateWorkflow({
      user_intent: userInput,
      datasets: selectedDatasets,
      max_tools_search: 30
    });

    if (!response.success) {
      setError(response.error);
      return;
    }

    // Step 2: Show validation warnings if any
    if (response.validation_warnings && response.validation_warnings.length > 0) {
      setValidationWarnings(response.validation_warnings);
    }

    // Step 3: Show dataset substitutions if any
    if (response.dataset_substitutions && response.dataset_substitutions.length > 0) {
      const userAccepted = await showDatasetSubstitutionDialog(
        response.dataset_substitutions
      );

      if (!userAccepted) {
        setGenerating(false);
        return;
      }
    }

    // Step 4: Estimate query sizes for all dataset steps
    const stepsWithEstimations = await Promise.all(
      response.workflow_structure.steps.map(async (step) => {
        if (step.tool_type === 'data_source') {
          const estimation = await galaxyAPI.estimateQuerySize(
            step.tool_id,
            step.tool_state
          );

          return { ...step, query_estimation: estimation };
        }
        return step;
      })
    );

    // Step 5: Show parameter preview dialog
    const userConfirmed = await showParameterPreviewDialog(
      stepsWithEstimations
    );

    if (!userConfirmed) {
      setGenerating(false);
      return;
    }

    // Step 6: User approved - save workflow
    setWorkflowGa(response.workflow_ga);
    setWorkflowSteps(stepsWithEstimations);

    // Step 7: Optionally execute immediately or let user execute manually
    if (autoExecute) {
      await executeWorkflow(response.workflow_ga);
    }

  } catch (error) {
    setError(error.message);
  } finally {
    setGenerating(false);
  }
};


// Parameter preview dialog
async function showParameterPreviewDialog(steps: WorkflowStep[]): Promise<boolean> {
  return new Promise((resolve) => {
    setParameterPreviewSteps(steps);
    setParameterPreviewOpen(true);

    const handleConfirm = () => {
      setParameterPreviewOpen(false);
      resolve(true);
    };

    const handleCancel = () => {
      setParameterPreviewOpen(false);
      resolve(false);
    };

    // Store handlers for dialog component
    setParameterPreviewHandlers({ handleConfirm, handleCancel });
  });
}
```

---

## Part 5: Implementation Roadmap

### Phase 1: LLM Parameter Generation (Priority: HIGH)

**Duration**: 5-8 days

**Tasks**:
1. ✅ Add `_llm_generate_dataset_parameters()` method
2. ✅ Modify `_build_galaxy_workflow_json()` to use LLM for dataset tools
3. ✅ Add parameter validation logic
4. ✅ Test with various user intents and datasets
5. ✅ Monitor LLM accuracy and refine prompts

**Success Metrics**:
- 80%+ accuracy in parameter inference
- User-confirmed parameters match LLM-generated 90%+ of time
- Average parameter generation time < 2 seconds

---

### Phase 2: Frontend Parameter Preview (Priority: HIGH)

**Duration**: 2-3 days

**Tasks**:
1. ✅ Create `ParameterPreviewDialog` component
2. ✅ Add query size estimation display
3. ✅ Implement edit parameters functionality
4. ✅ Add user confirmation flow
5. ✅ Update workflow builder to use preview

**Success Metrics**:
- 100% of workflows show parameter preview before execution
- Users can edit parameters in < 30 seconds
- < 10% of workflows rejected by users

---

### Phase 3: Dataset Availability Validation (Priority: MEDIUM)

**Duration**: 3-5 days

**Tasks**:
1. ✅ Add `_validate_dataset_tools()` method
2. ✅ Implement API connection testing
3. ✅ Add fallback search logic (API ↔ Local)
4. ✅ Create substitution dialog component
5. ✅ Add validation warnings to API response

**Success Metrics**:
- 0 workflow execution failures due to missing datasets
- 90%+ success rate in finding alternatives
- Average validation time < 5 seconds

---

### Phase 4: Query Size Estimation (Priority: LOW)

**Duration**: 2-3 days

**Tasks**:
1. ✅ Create `DatasetQueryEstimator` class
2. ✅ Populate dataset statistics table
3. ✅ Add `/api/ai_assistant/estimate_query_size` endpoint
4. ✅ Display estimations in parameter preview
5. ✅ Add warnings for very large queries

**Success Metrics**:
- Estimation accuracy within 20% of actual size
- Warnings shown for all queries > 1M rows
- Reduced failed executions due to size issues

---

## Part 6: Testing Strategy

### Test Case 1: LLM Parameter Generation Accuracy

```python
# backend/tests/test_llm_parameter_generation.py

test_cases = [
    {
        "user_intent": "Get kinase inhibitors from BindingDB",
        "dataset_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
        "expected_params": {
            "query_mode": "filter",
            "filter_column": "Target",
            "filter_value": "kinase*"
        },
        "acceptable_alternatives": [
            {"filter_column": "target_name", "filter_value": "kinase*"},
            {"filter_column": "Target", "filter_value": "*kinase*"}
        ]
    },
    {
        "user_intent": "Sample 1000 drug compounds",
        "dataset_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
        "expected_params": {
            "query_mode": "sample",
            "sample_size": 1000
        }
    },
    {
        "user_intent": "Get brain tissue expression data from Protein Atlas",
        "dataset_id": "biomate_dm_biomni_data_lake_proteinatlas_tsv",
        "expected_params": {
            "query_mode": "filter",
            "filter_column": "Tissue",
            "filter_value": "brain*"
        }
    }
]

def test_parameter_generation_accuracy():
    generator = GalaxyWorkflowGenerator()

    correct = 0
    total = len(test_cases)

    for test in test_cases:
        params = generator._llm_generate_dataset_parameters(
            tool_id=test["dataset_id"],
            user_intent=test["user_intent"],
            available_params=[...],
            tool_help={...}
        )

        if params == test["expected_params"]:
            correct += 1
        elif any(params == alt for alt in test.get("acceptable_alternatives", [])):
            correct += 1

    accuracy = correct / total
    assert accuracy >= 0.8, f"Parameter generation accuracy {accuracy:.1%} below threshold"
```

---

### Test Case 2: Dataset Availability Validation

```python
# backend/tests/test_dataset_validation.py

def test_local_dataset_missing_fallback_to_api():
    # Setup: Remove local DepMap file
    original_path = '/private/tmp/.../DepMap_CRISPRGeneDependency.csv'
    backup_path = original_path + '.backup'
    os.rename(original_path, backup_path)

    try:
        generator = GalaxyWorkflowGenerator()

        # Generate workflow
        result = generator.generate_workflow(
            "Analyze cancer dependencies from DepMap"
        )

        # Should succeed with API fallback
        assert result['success'] == True
        assert 'biomate_datasource_api_depmap' in str(result['workflow_ga'])
        assert len(result['validation_warnings']) > 0
        assert 'Using API' in result['validation_warnings'][0]

    finally:
        # Cleanup
        os.rename(backup_path, original_path)


def test_api_unavailable_fallback_to_local():
    # Mock API failure
    with mock.patch('requests.get', side_effect=ConnectionError):
        generator = GalaxyWorkflowGenerator()

        result = generator.generate_workflow(
            "Get protein sequences from UniProt"
        )

        # Should use local fallback if available
        if result['success']:
            assert 'biomate_dm_' in str(result['workflow_ga'])
            assert 'Using local' in result['validation_warnings'][0]
```

---

## Part 7: Deployment Considerations

### Configuration

```yaml
# backend/config/galaxy.yml

ai_assistant:
  enable_llm_parameter_generation: true
  llm_parameter_generation_timeout: 10  # seconds

  dataset_validation:
    enabled: true
    api_connection_timeout: 5  # seconds
    enable_fallbacks: true

  query_estimation:
    enabled: true
    statistics_db_path: /path/to/dataset_statistics.db
```

### Monitoring

Add logging for key metrics:

```python
# backend/lib/galaxy/ai/workflow_monitoring.py

import logging
from datetime import datetime

log = logging.getLogger(__name__)

class WorkflowMetrics:
    """Track workflow generation metrics."""

    @staticmethod
    def log_parameter_generation(
        dataset_id: str,
        user_intent: str,
        generated_params: Dict,
        llm_time_ms: int,
        user_accepted: bool
    ):
        log.info(f"[ParameterGeneration] dataset={dataset_id}, "
                 f"intent_length={len(user_intent)}, "
                 f"llm_time={llm_time_ms}ms, "
                 f"accepted={user_accepted}")

    @staticmethod
    def log_dataset_validation(
        dataset_id: str,
        available: bool,
        fallback_used: bool,
        validation_time_ms: int
    ):
        log.info(f"[DatasetValidation] dataset={dataset_id}, "
                 f"available={available}, "
                 f"fallback={fallback_used}, "
                 f"time={validation_time_ms}ms")
```

---

## Conclusion

### Current State Summary:

✅ **Strong Infrastructure**:
- React frontend with SSE real-time updates
- Express middleware for API proxying
- Galaxy Python backend with AI Assistant
- Unified workflow generation architecture

⚠️ **Key Gaps**:
- Dataset query parameters use defaults (not LLM-generated)
- No user confirmation before workflow execution
- No dataset availability validation
- No query size estimation

### Optimization Impact:

| Enhancement | Impact | Effort | Priority |
|-------------|--------|--------|----------|
| LLM Parameter Generation | HIGH | 5-8 days | HIGH |
| Frontend Parameter Preview | HIGH | 2-3 days | HIGH |
| Dataset Validation | MEDIUM | 3-5 days | MEDIUM |
| Query Size Estimation | LOW | 2-3 days | LOW |

**Total Implementation Time**: 12-19 days

**Expected Improvements**:
- 80%+ reduction in failed workflow executions
- 90%+ user satisfaction with generated parameters
- 100% awareness of query parameters before execution
- 0 failures due to missing datasets (with fallbacks)

---

**Document Version:** 1.0
**Created:** 2025-10-13
**Author:** BioMate Analysis System
**Related Documents:**
- HOW_DATASETS_WORK_IN_WORKFLOWS_2025-10-13.md
- WORKFLOW_EXECUTION_ANALYSIS_2025-10-13.md
