# How Dataset Tools Work in Workflows (2025-10-13)

## Executive Summary

You asked three critical questions about dataset workflow behavior:

1. **"If it is a step inside the workflow, the LLM needs to generate query on-demand based on user's intention, right? is it realized?"**
   - ❌ **NOT REALIZED** - Currently parameters are NOT generated on-demand by LLM
   - Tool parameters are set to defaults in workflow JSON
   - User must manually configure query parameters after workflow creation

2. **"If a dataset is needed but the dataset is not locally available or API available, what the workflow generator will do?"**
   - ⚠️ **NO EXPLICIT HANDLING** - Workflow generator doesn't validate dataset availability
   - Tool will fail at execution time if dataset missing
   - No fallback mechanism exists

3. **"How galaxy will do typically?"**
   - 🌐 **Galaxy native approach**: Browser-based interactive query interface
   - User fills out web form → callback to Galaxy with results
   - NOT automated via LLM - always requires user interaction

---

## Part 1: How Galaxy Native Data Source Tools Work

### Architecture: Interactive Browser-Based Workflow

Galaxy's native data source tools (BioMart, UCSC, SRA) use a **completely different paradigm** from regular tools:

```xml
<!-- biomart.xml -->
<tool name="BioMart" id="biomart" tool_type="data_source">
    <inputs action="http://www.ensembl.org/biomart/martview" method="get">
        <display>go to BioMart Ensembl $GALAXY_URL</display>
        <param name="GALAXY_URL" type="baseurl" value="/tool_runner/biomart" />
    </inputs>
</tool>
```

### Execution Flow:

```
Step 1: User clicks "BioMart" tool in Galaxy
         ↓
Step 2: Galaxy REDIRECTS user's browser to:
        http://www.ensembl.org/biomart/martview?GALAXY_URL=https://galaxy.server/tool_runner/biomart
         ↓
Step 3: User fills out BioMart web form interactively:
        - Select database (e.g., Ensembl Genes)
        - Select filters (e.g., Chromosome 1, Gene type: protein_coding)
        - Select attributes (e.g., Gene ID, Gene name, Description)
        - Click "Results" button
         ↓
Step 4: BioMart server sends query results BACK to Galaxy via callback:
        POST https://galaxy.server/tool_runner/biomart
        Body: CSV data + metadata
         ↓
Step 5: Galaxy receives data and adds to history
        User continues workflow with this data
```

### Key Characteristics:

✅ **Interactive**: User ALWAYS fills out query form in browser
✅ **No AI**: No LLM involvement - 100% manual
✅ **Reliable**: Established protocol used by Galaxy for 15+ years
✅ **Flexible**: User has full control over query parameters

❌ **Not automated**: Cannot be used in fully automated workflows
❌ **Breaks AI workflow generation**: LLM cannot generate query parameters
❌ **User intervention required**: Workflow stops until user completes form

---

## Part 2: How BioMate Dataset Tools Work

### Architecture: Parameter-Based Query Tools

BioMate dataset tools use **explicit parameters** that COULD be set by LLM but currently aren't:

```xml
<!-- biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv.xml -->
<tool id="biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv"
      name="Query BindingDB_All_202409.tsv"
      tool_type="data_source">

    <command>
        python '$__tool_directory__/biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv.py'
            --dataset_path '/private/tmp/.../BindingDB_All_202409.tsv'
            --query_mode '$query_mode'
            --filter_column '$filter_column'
            --filter_value '$filter_value'
            --output '$output'
    </command>

    <inputs>
        <param name="query_mode" type="select" label="Query Mode">
            <option value="all">Return All Data</option>
            <option value="filter">Filter by Column Value</option>
            <option value="sample">Random Sample</option>
            <option value="head">First N Rows</option>
        </param>

        <param name="filter_column" type="text" label="Filter Column"/>
        <param name="filter_value" type="text" label="Filter Value"/>
        <param name="sample_size" type="integer" value="1000"/>
    </inputs>
</tool>
```

### Current Workflow Generation Behavior:

**What ACTUALLY happens** when LLM generates a workflow with dataset tools:

```python
# In galaxy_workflow_generator.py: _build_galaxy_workflow_json()

# Get tool parameters from database
tool_params, tool_help = self._get_tool_parameters_and_help(tool_id)

# Build tool_state with DEFAULT values
tool_state = self._build_tool_state(tool_params)
# Returns: {"query_mode": "all", "filter_column": "", "filter_value": ""}
```

**Result**: Workflow JSON contains **EMPTY/DEFAULT parameters**:

```json
{
  "steps": {
    "0": {
      "tool_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
      "tool_state": {
        "query_mode": "all",        // ← Default!
        "filter_column": "",         // ← Empty!
        "filter_value": ""           // ← Empty!
      }
    }
  }
}
```

### ❌ Problem: No LLM-Generated Query Parameters

**What we NEED** (but don't have):

```python
# User intent: "Get kinase proteins from BindingDB"

# What LLM SHOULD generate:
{
  "tool_state": {
    "query_mode": "filter",
    "filter_column": "Target",
    "filter_value": "kinase*"
  }
}

# What LLM ACTUALLY generates:
{
  "tool_state": {
    "query_mode": "all",    # ← Returns ENTIRE dataset (5.8GB!)
    "filter_column": "",    # ← No filtering!
    "filter_value": ""
  }
}
```

---

## Part 3: Why LLM Query Generation Isn't Realized

### Code Analysis: workflow_generator.py

The `_llm_generate_parameters()` method EXISTS but is **not used for dataset tools**:

```python
# lib/galaxy/ai/workflow_generator.py

def _generate_tool_parameters(self, task: Task, tool: Tool) -> Dict[str, Any]:
    """Generate default parameters for a tool based on the task."""
    parameters = {}

    # Use LLM to suggest appropriate parameters
    if self.config.use_llm_for_parameters and task.description:
        try:
            llm_params = self._llm_generate_parameters(task, tool)
            parameters.update(llm_params)
        except Exception as e:
            print(f"LLM parameter generation failed: {e}")
            # Fall back to default parameters

    # Set defaults for any remaining parameters
    for input_spec in tool.inputs:
        param_name = input_spec.get('name')
        if param_name not in parameters:
            parameters[param_name] = self._get_default_value(input_spec)

    return parameters

def _llm_generate_parameters(self, task: Task, tool: Tool) -> Dict[str, Any]:
    """Use LLM to generate appropriate tool parameters."""

    # Build prompt with task context
    prompt = f"""Generate appropriate parameters for this bioinformatics tool.

    Tool: {tool.name}
    Tool ID: {tool.id}
    Description: {tool.description}

    Task:
    - Name: {task.name}
    - Description: {task.description}
    - Task Type: {task.task_type.value}
    - Intent: {task.intent_type.value}

    Provide sensible default parameters that would be appropriate for this task.
    Consider standard bioinformatics best practices.
    Only include parameters that are commonly adjusted and important for the analysis.

    Return a JSON object with parameter names as keys and their values.
    """

    # ... LLM call to generate parameters ...
```

### ❌ Problem: This Method Is NOT Called for Dataset Tools

**Reason**: The `galaxy_workflow_generator.py` (used by unified workflow system) does NOT call `_llm_generate_parameters()`:

```python
# lib/galaxy/ai/galaxy_workflow_generator.py

def _build_galaxy_workflow_json(
    self,
    workflow_structure: Dict[str, Any],
    dataset_assignments: Dict[str, Any]
) -> Dict[str, Any]:
    """Build Galaxy .ga workflow JSON with embedded datasets and parameter templates."""

    for step in workflow_structure.get('steps', []):
        tool_id = step['tool_id']

        # Get tool parameters from database
        tool_params, tool_help = self._get_tool_parameters_and_help(tool_id)

        # Build tool_state with DEFAULT values
        tool_state = self._build_tool_state(tool_params)  # ← Just uses defaults!
        # NO LLM CALL HERE!
```

---

## Part 4: What Happens When Dataset Is Unavailable?

### Current Behavior: NO VALIDATION

**At workflow generation time:**

```python
# galaxy_workflow_generator.py

def generate_workflow(self, user_intent: str) -> Dict[str, Any]:
    # Step 1: Search for tools
    tools = self._search_tools(fts_query, max_results=max_tools_search)
    # ← No check if datasets exist!

    # Step 2: Generate workflow structure
    workflow_structure = self._generate_workflow_structure(user_intent, tools)
    # ← No validation of dataset availability!

    # Step 3: Build Galaxy workflow JSON
    workflow_ga = self._build_galaxy_workflow_json(workflow_structure, {})
    # ← Dataset paths are hardcoded in tool XML, not validated!
```

**At workflow execution time:**

```bash
# User executes workflow with BindingDB dataset tool

# Galaxy executes tool command:
python biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv.py \
    --dataset_path '/private/tmp/lcms-platform-galaxy/knowledge_data/biomni_data_lake/BindingDB_All_202409.tsv' \
    --query_mode 'all' \
    --output 'output.tsv'

# Python script tries to open file:
import pandas as pd
df = pd.read_csv('/private/tmp/.../BindingDB_All_202409.tsv', sep='\t')
# FileNotFoundError: [Errno 2] No such file or directory

# Workflow FAILS with error
# NO fallback mechanism
# User sees error in Galaxy history
```

### ❌ No Graceful Degradation

**What SHOULD happen** (but doesn't):

```python
# Ideal workflow generator behavior:

def generate_workflow(self, user_intent: str) -> Dict[str, Any]:
    # Step 1: Search for tools including datasets
    tools = self._search_tools(user_intent)

    # Step 2: VALIDATE dataset availability
    for tool in tools:
        if tool['tool_type'] == 'data_source':
            if tool['tool_id'].startswith('biomate_dm_'):
                # Check local file exists
                dataset_path = self._get_dataset_path(tool['tool_id'])
                if not os.path.exists(dataset_path):
                    warnings.append(f"Local dataset not available: {tool['name']}")
                    # FALLBACK: Search for API alternative
                    alternative = self._find_api_alternative(tool)
                    if alternative:
                        tool = alternative
                        warnings.append(f"Using API alternative: {alternative['name']}")
                    else:
                        # Remove tool from workflow
                        warnings.append(f"No alternative found, removing: {tool['name']}")
                        tools.remove(tool)

            elif tool['tool_id'].startswith('biomate_datasource_api_'):
                # Check API reachable
                api_url = self._get_api_url(tool['tool_id'])
                if not self._test_api_connection(api_url):
                    warnings.append(f"API not reachable: {tool['name']}")
                    # FALLBACK: Search for local dataset alternative
                    alternative = self._find_local_alternative(tool)
                    # ... similar logic
```

**Current reality**: None of this validation exists!

---

## Part 5: Galaxy's Typical Approach vs BioMate's Approach

### Comparison Table

| Aspect | Galaxy Native | BioMate Current | BioMate Ideal |
|--------|---------------|-----------------|---------------|
| **Query Interface** | Browser redirect | Parameters in XML | LLM-generated params |
| **User Interaction** | Required (web form) | Optional (default params) | None (fully automated) |
| **Parameter Source** | User fills out form | Hardcoded defaults | LLM infers from intent |
| **Automation** | ❌ Not possible | ⚠️ Partial (uses defaults) | ✅ Fully automated |
| **Flexibility** | ✅ Full control | ⚠️ Limited (needs manual edit) | ✅ Intent-based |
| **Reliability** | ✅ High (15+ years) | ⚠️ Medium (defaults often wrong) | ❓ Unknown (not implemented) |
| **Dataset Validation** | ✅ External site validates | ❌ No validation | ✅ Pre-execution check |
| **Error Handling** | ✅ External site handles | ❌ Fails at execution | ✅ Graceful degradation |
| **Fallback** | ❌ No alternative needed | ❌ No fallback | ✅ API ↔ Local switching |

---

## Part 6: Detailed Example Scenarios

### Scenario 1: Galaxy Native (BioMart) Workflow

**User Intent**: "Get mouse genes from Ensembl and analyze expression"

**Generated Workflow**:
```json
{
  "steps": {
    "0": {
      "tool_id": "biomart",
      "tool_type": "data_source",
      "annotation": "Query Ensembl for mouse genes"
    },
    "1": {
      "tool_id": "nfcore_deseq2",
      "annotation": "Differential expression analysis"
    }
  }
}
```

**Execution**:
```
1. User clicks "Run Workflow"
2. Galaxy redirects to http://www.ensembl.org/biomart/martview
3. WORKFLOW PAUSES - waiting for user input
4. User fills out BioMart form:
   - Database: Ensembl Genes
   - Dataset: Mouse genes (GRCm39)
   - Filters: Chromosome 1
   - Attributes: Gene ID, Gene name, Description
5. User clicks "Results"
6. BioMart sends data back to Galaxy
7. Galaxy resumes workflow with Step 1 (DESeq2)
```

**Result**:
- ✅ Workflow completes successfully
- ⚠️ Requires user intervention (not automated)
- ⏱️ Total time: 30 seconds + user interaction time

---

### Scenario 2: BioMate Current (BindingDB) Workflow

**User Intent**: "Get kinase inhibitors from BindingDB and dock compounds"

**Generated Workflow**:
```json
{
  "steps": {
    "0": {
      "tool_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
      "tool_state": {
        "query_mode": "all",        // ← Wrong! Should be "filter"
        "filter_column": "",         // ← Empty! Should be "Target"
        "filter_value": ""           // ← Empty! Should be "kinase*"
      }
    },
    "1": {
      "tool_id": "nfcore_autodock",
      "annotation": "Molecular docking"
    }
  }
}
```

**Execution**:
```
1. User clicks "Run Workflow"
2. Step 0 executes with default parameters:
   - Reads ENTIRE BindingDB dataset (5.8GB!)
   - Returns 2.5 million rows
   - Takes 5 minutes to load
3. Step 1 (AutoDock) receives 2.5M compounds
   - Fails: "Too many input ligands (max: 10,000)"
4. Workflow FAILS

User must:
5. Edit workflow
6. Manually set parameters:
   - query_mode: "filter"
   - filter_column: "Target"
   - filter_value: "kinase*"
7. Re-run workflow
8. Now returns 15,000 kinase compounds
9. AutoDock processes successfully
```

**Result**:
- ❌ Initial workflow fails
- ⚠️ Requires manual editing
- ⏱️ Total time: 5min (failure) + manual edit + 2min (success) = ~10 minutes

---

### Scenario 3: BioMate Ideal (If LLM Query Generation Was Implemented)

**User Intent**: "Get kinase inhibitors from BindingDB and dock compounds"

**Generated Workflow** (with LLM-generated parameters):
```json
{
  "steps": {
    "0": {
      "tool_id": "biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
      "tool_state": {
        "query_mode": "filter",       // ← LLM inferred!
        "filter_column": "Target",    // ← LLM inferred!
        "filter_value": "kinase*"     // ← LLM inferred!
      }
    },
    "1": {
      "tool_id": "nfcore_autodock",
      "annotation": "Molecular docking"
    }
  }
}
```

**LLM Parameter Generation Process**:
```python
# LLM receives prompt:
"""
User Intent: "Get kinase inhibitors from BindingDB and dock compounds"

Tool: Query BindingDB_All_202409.tsv
Available parameters:
- query_mode: ["all", "filter", "sample", "head"]
- filter_column: text (available: ligand, target, affinity, ki, kd, ic50)
- filter_value: text (supports wildcards)
- sample_size: integer

Dataset columns:
- ligand: Drug/compound name
- target: Protein target name
- affinity: Binding affinity value
- ki, kd, ic50: Binding constants

Task: Generate appropriate query parameters to get kinase inhibitor data.

Return JSON:
{
  "query_mode": "?",
  "filter_column": "?",
  "filter_value": "?"
}
"""

# LLM reasoning:
# - User wants "kinase inhibitors"
# - Need to filter by target type
# - "kinase" is in target column
# - Use wildcard to match all kinase variants

# LLM response:
{
  "query_mode": "filter",
  "filter_column": "Target",
  "filter_value": "kinase*"
}
```

**Execution**:
```
1. User clicks "Run Workflow"
2. Step 0 executes with LLM-generated parameters:
   - Filters BindingDB for Target matching "kinase*"
   - Returns 15,000 rows (8 seconds)
3. Step 1 (AutoDock) receives 15K compounds
   - Processes successfully (20 minutes)
4. Workflow COMPLETES
```

**Result**:
- ✅ Workflow succeeds on first try
- ✅ Fully automated (no user intervention)
- ⏱️ Total time: 8s + 20min = ~20 minutes

---

## Part 7: Missing Dataset Handling Examples

### Example 1: Local Dataset Missing

**User Intent**: "Analyze cancer cell dependencies from DepMap"

**Workflow Generation**:
```python
# Tool selected: biomate_dm_biomni_data_lake_DepMap_CRISPRGeneDependency_csv
# Dataset path: /private/tmp/.../DepMap_CRISPRGeneDependency.csv

# Current behavior (NO VALIDATION):
workflow = generate_workflow(user_intent)
# Returns: Success! Workflow created.

# Execution:
galaxy.execute_workflow(workflow)
# FileNotFoundError: Dataset not found
# Workflow fails
```

**Ideal Behavior** (with validation):
```python
# Workflow generation WITH validation:
workflow = generate_workflow(user_intent)

# Validation check:
if not os.path.exists('/private/tmp/.../DepMap_CRISPRGeneDependency.csv'):
    # FALLBACK 1: Check for API alternative
    api_tool = find_tool("query_depmap_api")
    if api_tool and test_api_connection("https://depmap.org/api"):
        # Replace local dataset with API query
        workflow['steps'][0] = {
            'tool_id': 'biomate_datasource_api_depmap',
            'annotation': 'Query DepMap via API (local dataset unavailable)'
        }
        warnings.append("Using DepMap API instead of local dataset")
    else:
        # FALLBACK 2: Remove dataset requirement, use user upload
        workflow['steps'][0] = {
            'tool_id': 'upload1',
            'annotation': 'Upload DepMap data manually'
        }
        warnings.append("Dataset not available - please upload manually")

# Returns: Workflow with fallback + warnings
```

---

### Example 2: API Unavailable

**User Intent**: "Get protein sequences from UniProt and predict structure"

**Workflow Generation**:
```python
# Tool selected: biomate_datasource_api_uniprot

# Current behavior (NO VALIDATION):
workflow = generate_workflow(user_intent)
# Returns: Success! Workflow created.

# Execution:
galaxy.execute_workflow(workflow)
# ConnectionError: UniProt API unreachable
# Workflow fails
```

**Ideal Behavior** (with validation):
```python
# Workflow generation WITH validation:
workflow = generate_workflow(user_intent)

# API check:
try:
    response = requests.get("https://rest.uniprot.org/uniprotkb/search?query=*", timeout=5)
    if response.status_code != 200:
        raise Exception("API not responding")
except Exception:
    # FALLBACK 1: Check for local mirror
    local_tool = find_tool("biomate_dm_biomni_data_lake_uniprot_cache")
    if local_tool:
        workflow['steps'][0] = {
            'tool_id': local_tool['tool_id'],
            'annotation': 'Query local UniProt cache (API unavailable)'
        }
        warnings.append("Using local UniProt cache - may be outdated")
    else:
        # FALLBACK 2: Use Galaxy native SRA as data source
        galaxy_tool = find_tool("ncbi_datasets")
        workflow['steps'][0] = {
            'tool_id': 'ncbi_datasets',
            'annotation': 'Query NCBI as alternative to UniProt'
        }
        warnings.append("UniProt unavailable - using NCBI alternative")

# Returns: Workflow with fallback + warnings
```

---

## Part 8: Implementation Gap Summary

### What Exists ✅

1. **Dataset tool XML definitions** with explicit parameters
2. **Tool database** with parameter metadata
3. **Workflow generator** infrastructure
4. **LLM parameter generation method** (`_llm_generate_parameters()`)
5. **EnhancedGalaxyToolRAG** for dataset discovery

### What's Missing ❌

1. **LLM parameter inference for dataset tools**
   - Method exists but not called
   - No prompt engineering for dataset queries
   - No integration with workflow generation

2. **Dataset availability validation**
   - No pre-execution checks
   - No file existence validation
   - No API connectivity tests

3. **Fallback mechanism**
   - No API ↔ Local dataset switching
   - No alternative tool suggestion
   - No graceful degradation

4. **User intent → Query parameter mapping**
   - "kinase inhibitors" → `filter_column="Target", filter_value="kinase*"`
   - "brain tissue expression" → `filter_column="Tissue", filter_value="brain*"`
   - No LLM reasoning about query construction

---

## Part 9: Recommendations for Implementation

### Priority 1: Enable LLM Query Parameter Generation (5-8 days)

**Modify**: `lib/galaxy/ai/galaxy_workflow_generator.py`

```python
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
```

**New Method**:
```python
def _llm_generate_dataset_parameters(
    self,
    tool_id: str,
    user_intent: str,
    available_params: List[Dict],
    tool_help: Dict
) -> Dict[str, Any]:
    """
    Use LLM to generate dataset query parameters based on user intent.

    Example:
    - User: "Get kinase inhibitors from BindingDB"
    - LLM generates: {"query_mode": "filter", "filter_column": "Target", "filter_value": "kinase*"}
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

        return params

    except Exception as e:
        log.error(f"LLM dataset parameter generation failed: {e}")
        return self._build_tool_state(available_params)
```

---

### Priority 2: Add Dataset Availability Validation (3-5 days)

**Modify**: `lib/galaxy/ai/galaxy_workflow_generator.py`

```python
def generate_workflow(
    self,
    user_intent: str,
    max_tools_search: int = 30
) -> Dict[str, Any]:

    # ... existing code ...

    # NEW: Validate dataset availability
    validated_tools = self._validate_dataset_tools(tools, user_intent)

    # Generate workflow with validated tools
    workflow_structure = self._generate_workflow_structure(
        user_intent,
        validated_tools  # Use validated list
    )
```

**New Method**:
```python
def _validate_dataset_tools(
    self,
    tools: List[Dict],
    user_intent: str
) -> List[Dict]:
    """Validate dataset tool availability and suggest fallbacks."""

    validated = []
    warnings = []

    for tool in tools:
        if tool['tool_type'] != 'data_source':
            validated.append(tool)
            continue

        # Check local dataset
        if tool['tool_id'].startswith('biomate_dm_'):
            dataset_path = self._extract_dataset_path(tool['tool_id'])

            if os.path.exists(dataset_path):
                validated.append(tool)
            else:
                log.warning(f"Local dataset not found: {dataset_path}")

                # Try API fallback
                api_alternative = self._find_api_alternative(tool, user_intent)
                if api_alternative:
                    validated.append(api_alternative)
                    warnings.append(f"Using API: {api_alternative['name']}")
                else:
                    # Remove from workflow
                    warnings.append(f"Dataset unavailable, removed: {tool['name']}")

        # Check API availability
        elif tool['tool_id'].startswith('biomate_datasource_api_'):
            api_url = self._get_api_url(tool['tool_id'])

            if self._test_api_connection(api_url):
                validated.append(tool)
            else:
                log.warning(f"API not reachable: {api_url}")

                # Try local fallback
                local_alternative = self._find_local_alternative(tool, user_intent)
                if local_alternative:
                    validated.append(local_alternative)
                    warnings.append(f"Using local: {local_alternative['name']}")
                else:
                    warnings.append(f"API unavailable, removed: {tool['name']}")

    return validated
```

---

### Priority 3: Implement Graceful Degradation (2-3 days)

**Add fallback strategies**:

```python
def _find_api_alternative(self, local_tool: Dict, user_intent: str) -> Optional[Dict]:
    """Find API alternative for local dataset."""

    # Extract dataset type from tool_id
    # e.g., "biomate_dm_biomni_data_lake_BindingDB" → "bindingdb"
    dataset_type = self._extract_dataset_type(local_tool['tool_id'])

    # Search for corresponding API tool
    api_search_query = f"{dataset_type} API"
    api_tools = self.db_manager.search_tools_fts5(api_search_query, limit=5)

    for api_tool in api_tools:
        if api_tool['tool_type'] == 'data_source' and 'api' in api_tool['tool_id'].lower():
            # Test if API is reachable
            if self._test_api_connection(self._get_api_url(api_tool['tool_id'])):
                return api_tool

    return None

def _find_local_alternative(self, api_tool: Dict, user_intent: str) -> Optional[Dict]:
    """Find local dataset alternative for API."""

    # Extract database name from API tool_id
    # e.g., "biomate_datasource_api_uniprot" → "uniprot"
    db_name = api_tool['tool_id'].replace('biomate_datasource_api_', '')

    # Search for local dataset
    local_search_query = f"{db_name} data lake"
    local_tools = self.db_manager.search_tools_fts5(local_search_query, limit=5)

    for local_tool in local_tools:
        if local_tool['tool_id'].startswith('biomate_dm_'):
            # Check if file exists
            dataset_path = self._extract_dataset_path(local_tool['tool_id'])
            if os.path.exists(dataset_path):
                return local_tool

    return None
```

---

## Part 10: Testing Recommendations

### Test Case 1: LLM Query Generation

```python
# Test: User intent → Query parameters

test_cases = [
    {
        "intent": "Get kinase inhibitors from BindingDB",
        "expected": {
            "query_mode": "filter",
            "filter_column": "Target",
            "filter_value": "kinase*"
        }
    },
    {
        "intent": "Sample 1000 drug compounds from BindingDB",
        "expected": {
            "query_mode": "sample",
            "sample_size": 1000
        }
    },
    {
        "intent": "Get all brain tissue expression data",
        "expected": {
            "query_mode": "filter",
            "filter_column": "Tissue",
            "filter_value": "brain*"
        }
    }
]

for test in test_cases:
    params = llm_generate_dataset_parameters(
        tool_id="biomate_dm_biomni_data_lake_BindingDB_All_202409_tsv",
        user_intent=test["intent"],
        available_params=[...],
        tool_help={...}
    )

    assert params == test["expected"], f"Failed: {test['intent']}"
```

---

### Test Case 2: Dataset Availability Validation

```python
# Test: Missing dataset → Fallback to API

# Setup: Remove local DepMap file
os.rename(
    '/private/tmp/.../DepMap_CRISPRGeneDependency.csv',
    '/private/tmp/.../DepMap_CRISPRGeneDependency.csv.backup'
)

# Generate workflow
workflow = generator.generate_workflow("Analyze cancer dependencies from DepMap")

# Assert: Should use API fallback
assert workflow['steps'][0]['tool_id'] == 'biomate_datasource_api_depmap'
assert "Using API" in workflow['warnings'][0]

# Cleanup
os.rename(
    '/private/tmp/.../DepMap_CRISPRGeneDependency.csv.backup',
    '/private/tmp/.../DepMap_CRISPRGeneDependency.csv'
)
```

---

### Test Case 3: API Unavailable → Local Fallback

```python
# Test: API down → Use local dataset

# Mock API failure
with mock.patch('requests.get', side_effect=ConnectionError):
    workflow = generator.generate_workflow("Get protein sequences from UniProt")

# Assert: Should use local fallback
assert 'biomate_dm_' in workflow['steps'][0]['tool_id']
assert "Using local" in workflow['warnings'][0]
```

---

## Conclusion

### Answers to Your Questions:

1. **"Is LLM query generation realized?"**
   - **NO** - The infrastructure exists (`_llm_generate_parameters()`) but is NOT used for dataset tools
   - Workflow JSON contains empty/default parameters
   - User must manually edit workflow after generation

2. **"What happens if dataset is unavailable?"**
   - **NO VALIDATION** - Generator doesn't check availability
   - Workflow fails at execution time with FileNotFoundError/ConnectionError
   - NO fallback mechanism exists

3. **"How does Galaxy do it?"**
   - **Interactive browser-based**: User always fills out web form
   - **NO automation**: Cannot be used in fully automated workflows
   - **Reliable**: 15+ years of established protocol
   - **Different paradigm**: Not designed for AI workflow generation

### Implementation Priority:

1. **Enable LLM query parameter generation** (5-8 days) - HIGH IMPACT
2. **Add dataset availability validation** (3-5 days) - HIGH IMPACT
3. **Implement graceful degradation** (2-3 days) - MEDIUM IMPACT

**Total Effort**: 10-16 days to achieve fully automated dataset workflows

---

**Document Version:** 1.0
**Created:** 2025-10-13
**Author:** BioMate Analysis System
**Related Documents:**
- WORKFLOW_EXECUTION_ANALYSIS_2025-10-13.md
- DATASET_TOOL_COMPATIBILITY_GAP_ANALYSIS_2025-10-13.md
- COMPLETE_DATASET_TOOLS_INVENTORY_2025-10-13.md
