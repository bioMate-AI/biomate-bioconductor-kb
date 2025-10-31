# Code Modifications Needed for Updated Database

**Date:** October 30, 2025
**Database Schema:** See `DATABASE_SCHEMA_20251030.md`

---

## Summary

The Galaxy AI Tools database has been updated with comprehensive metadata including:
- Function distinction (wrapper vs underlying software)
- Examples, usage guides, citations
- EDAM ontology terms
- Structured inputs/outputs with format details

**Required Changes:** Backend API and Frontend UI need updates to expose and display this new information.

---

## 1. Backend Modifications

### 1.1 Add Missing Database Columns (CRITICAL)

**File:** `database/galaxy_ai_tools.db`
**Issue:** Code references columns that don't exist
**Location:** `lib/galaxy/tools/search_index.py:171-192`

**Missing columns:**
```sql
ALTER TABLE tools ADD COLUMN is_installed INTEGER DEFAULT 0;
ALTER TABLE tools ADD COLUMN install_status TEXT;
ALTER TABLE tools ADD COLUMN install_date TEXT;
```

**Alternative:** Modify code to handle missing columns gracefully:

```python
# In lib/galaxy/tools/search_index.py

def get_installed_tools(self) -> List[Dict[str, Any]]:
    """Get list of installed tools (thread-safe)"""
    with self._get_cursor() as cursor:
        try:
            cursor.execute('SELECT * FROM tools WHERE is_installed = 1 ORDER BY install_date DESC')
            return [dict(row) for row in cursor.fetchall()]
        except sqlite3.OperationalError:
            # Column doesn't exist yet
            log.warning("is_installed column not found, returning empty list")
            return []

def mark_installed(self, tool_id: str, status: str = 'installed'):
    """Mark a tool as installed (thread-safe with locking)"""
    if not tool_id:
        raise ValueError("tool_id cannot be empty")

    with self._lock:
        conn = self._get_connection()
        cursor = conn.cursor()
        try:
            # Check if columns exist
            cursor.execute("PRAGMA table_info(tools)")
            columns = [row[1] for row in cursor.fetchall()]

            if 'is_installed' in columns:
                cursor.execute('''
                    UPDATE tools
                    SET is_installed = 1,
                        install_status = ?,
                        install_date = CURRENT_TIMESTAMP
                    WHERE tool_id = ?
                ''', (status, tool_id))
                conn.commit()
                log.info(f"Marked tool {tool_id} as {status}")
            else:
                log.warning("is_installed column not found, skipping mark_installed")
        except Exception as e:
            conn.rollback()
            log.error(f"Error marking tool as installed: {e}")
            raise
```

### 1.2 Enhance get_tool_schema API Response

**File:** `lib/galaxy/tools/search_index.py:266-361`
**Issue:** API doesn't return comprehensive metadata
**Current return:** Only `id, name, version, description, inputs, outputs`
**Missing:** `function_info, examples, usage_guide, citations, edam_operations, requirements`

**Modification:**

```python
def get_tool_schema(self, tool_id: str) -> Optional[Dict[str, Any]]:
    """
    Get tool parameter schema formatted for frontend consumption

    Args:
        tool_id: Tool identifier

    Returns:
        Comprehensive tool schema with all metadata
    """
    import json

    tool = self.get_by_id(tool_id)
    if not tool:
        return None

    # Parse JSON fields
    try:
        parameters = json.loads(tool.get('parameters', '[]')) if isinstance(tool.get('parameters'), str) else (tool.get('parameters') or [])
        inputs = json.loads(tool.get('inputs', '[]')) if isinstance(tool.get('inputs'), str) else (tool.get('inputs') or [])
        outputs = json.loads(tool.get('outputs', '[]')) if isinstance(tool.get('outputs'), str) else (tool.get('outputs') or [])
        help_text = json.loads(tool.get('help_text', '{}')) if isinstance(tool.get('help_text'), str) else (tool.get('help_text') or {})
        examples = json.loads(tool.get('examples', '[]')) if isinstance(tool.get('examples'), str) else (tool.get('examples') or [])
        citations = json.loads(tool.get('citations', '[]')) if isinstance(tool.get('citations'), str) else (tool.get('citations') or [])
        edam_operations = json.loads(tool.get('edam_operations', '[]')) if isinstance(tool.get('edam_operations'), str) else (tool.get('edam_operations') or [])
        requirements = json.loads(tool.get('requirements', '[]')) if isinstance(tool.get('requirements'), str) else (tool.get('requirements') or [])
        tags = json.loads(tool.get('tags', '[]')) if isinstance(tool.get('tags'), str) else (tool.get('tags') or [])
    except (json.JSONDecodeError, TypeError) as e:
        log.warning(f"Failed to parse JSON fields for tool {tool_id}: {e}")
        parameters = []
        inputs = []
        outputs = []
        help_text = {}
        examples = []
        citations = []
        edam_operations = []
        requirements = []
        tags = []

    # Convert database parameters to frontend ToolParameter format
    frontend_inputs = []
    for param in parameters:
        frontend_param = {
            'name': param.get('name', ''),
            'label': param.get('label', param.get('name', '')),
            'type': self._map_parameter_type(param.get('type', 'text')),
            'help': param.get('help', ''),
            'optional': param.get('optional', True),
        }

        # Add type-specific fields
        if frontend_param['type'] in ['integer', 'float']:
            if 'min' in param:
                frontend_param['min'] = param['min']
            if 'max' in param:
                frontend_param['max'] = param['max']

        if frontend_param['type'] == 'select' and 'options' in param:
            frontend_param['options'] = param['options']

        if 'value' in param or 'default' in param:
            frontend_param['value'] = param.get('value', param.get('default'))

        frontend_inputs.append(frontend_param)

    # If no parameters, try to use inputs
    if not frontend_inputs and inputs:
        for input_spec in inputs:
            frontend_param = {
                'name': input_spec.get('name', ''),
                'label': input_spec.get('description', input_spec.get('name', '')),
                'type': self._map_parameter_type(input_spec.get('type', 'text')),
                'help': input_spec.get('description', ''),
                'optional': input_spec.get('optional', True),
            }
            frontend_inputs.append(frontend_param)

    # Format outputs
    frontend_outputs = []
    for output in outputs:
        if isinstance(output, dict):
            frontend_outputs.append({
                'name': output.get('name', ''),
                'format': output.get('format', output.get('type', 'data')),
                'label': output.get('label', output.get('description', output.get('name', ''))),
                'description': output.get('description', ''),
                'pattern': output.get('pattern', ''),
            })
        else:
            # Simple format list
            frontend_outputs.append({
                'name': output,
                'format': output,
                'label': output,
            })

    # Extract function info
    function_info = help_text.get('function_info', {})

    # Get software version from requirements (not wrapper version)
    software_version = None
    underlying_software = function_info.get('underlying_software')
    for req in requirements:
        if isinstance(req, dict):
            req_name = req.get('name', '').split('::')[-1].lower()
            if req_name == underlying_software or req.get('type') in ['package', 'conda']:
                software_version = req.get('version')
                if software_version:
                    break

    # Return comprehensive schema
    return {
        # Basic info
        'id': tool.get('tool_id') or tool.get('id'),
        'name': tool.get('name', ''),
        'version': tool.get('version', ''),  # Wrapper version
        'description': tool.get('description', '') or help_text.get('what_it_does', ''),
        'category': tool.get('category', ''),

        # Parameters and I/O
        'inputs': frontend_inputs,
        'outputs': frontend_outputs,

        # NEW: Comprehensive metadata
        'function_info': {
            'underlying_software': function_info.get('underlying_software'),
            'software_version': software_version,  # Actual software version
            'wrapper_version': tool.get('version'),  # Wrapper version
            'wrapper_function': function_info.get('wrapper_function'),
            'operation_type': function_info.get('operation_type'),
            'is_primary_function': function_info.get('is_primary_function', True),
        },

        'examples': examples,
        'usage_guide': tool.get('usage_guide', ''),
        'citations': citations,
        'edam_operations': edam_operations,
        'requirements': requirements,
        'tags': tags,

        'help': {
            'what_it_does': help_text.get('what_it_does', ''),
            'how_to_use': help_text.get('how_to_use', ''),
            'homepage': help_text.get('homepage', ''),
            'documentation': help_text.get('documentation', ''),
            'keywords': help_text.get('keywords', []),
        },

        'url': tool.get('url', ''),
        'repo_owner': tool.get('repo_owner', ''),
        'repo_name': tool.get('repo_name', ''),
    }
```

### 1.3 Add Database Path Configuration

**File:** `lib/galaxy/tools/search_index.py:24-25`
**Issue:** Hardcoded path `galaxy_ai_tools.db` doesn't match actual location `database/galaxy_ai_tools.db`

**Modification:**

```python
def __init__(self, db_path: str = None):
    if db_path is None:
        # Try database/ subdirectory first, then root
        db_path_1 = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"
        db_path_2 = Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db"

        if db_path_1.exists():
            db_path = str(db_path_1)
        elif db_path_2.exists():
            db_path = str(db_path_2)
        else:
            raise FileNotFoundError(
                f"Galaxy AI tools database not found at {db_path_1} or {db_path_2}"
            )

    self.db_path = db_path
    self._local = threading.local()
    self._lock = threading.RLock()

    # Verify database exists
    if not Path(self.db_path).exists():
        raise FileNotFoundError(f"Tool search index not found at {self.db_path}")
```

---

## 2. Frontend Modifications

### 2.1 Show Operation Type in Tool Selection/Search UI

**File:** `frontend/client/src/components/workflow-builder.tsx` or tool search components
**Purpose:** Help users distinguish between different functions of the same software BEFORE they select a tool
**Location:** Tool selection dropdown, search results, or tool picker

**Add operation type badge:**

```tsx
// Add this import
import { Badge } from "@/components/ui/badge"

// In tool list/search results, show operation type badge
function ToolListItem({ tool }: { tool: any }) {
  const functionInfo = tool.help_text?.function_info || {};

  // Map operation types to user-friendly labels and colors
  const operationTypeConfig = {
    'primary_analysis': { label: 'Analysis', color: 'blue' },
    'post_processing': { label: 'Post-processing', color: 'purple' },
    'visualization': { label: 'Visualization', color: 'green' },
    'format_conversion': { label: 'Conversion', color: 'orange' },
    'batch_processing': { label: 'Batch', color: 'gray' },
    'data_manipulation': { label: 'Filter/Edit', color: 'yellow' },
  };

  const typeConfig = operationTypeConfig[functionInfo.operation_type] || { label: 'Tool', color: 'gray' };

  return (
    <div className="flex items-start gap-3 p-3 hover:bg-gray-50 dark:hover:bg-gray-800 rounded">
      <div className="flex-1">
        <div className="flex items-center gap-2">
          <h4 className="font-medium">{tool.name}</h4>
          {!functionInfo.is_primary_function && (
            <Badge variant="outline" className={`text-${typeConfig.color}-600`}>
              {typeConfig.label}
            </Badge>
          )}
        </div>
        <p className="text-sm text-gray-600 dark:text-gray-400 mt-1">
          {functionInfo.wrapper_function || tool.description}
        </p>
      </div>
    </div>
  );
}
```

**Example display:**
```
🔵 FastQC (devteam)
   Perform primary analysis

📊 FastQC Summary (nml) [Post-processing]
   Summarize or aggregate results from the base tool

🌐 Fastqc Site (mingchen0919) [Visualization]
   Generate website/portal with results
```

### 2.2 Parameter Dialog - Keep Simple (Codeless Platform)

**File:** `frontend/client/src/components/parameter-dialog.tsx`
**Purpose:** Focus ONLY on parameters, not technical details
**NO CHANGES NEEDED** - Keep parameter dialog simple:
- Tool name
- Description
- Parameter form fields
- Execute button

**Do NOT add:**
- ❌ Code examples (platform is codeless)
- ❌ Software version vs wrapper version (technical detail)
- ❌ Underlying software info (confusing for users)
- ❌ Operation type (already shown during tool selection)

---

## 3. Testing Requirements

### 3.1 Backend API Tests

**Test file:** `tests/test_tool_search_api.py`

```python
def test_get_tool_schema_comprehensive():
    """Test that schema endpoint returns all metadata"""
    response = client.get("/api/tool_search/schema?tool_id=toolshed...fastqc")
    assert response.status_code == 200

    data = response.json()

    # Basic fields
    assert 'id' in data
    assert 'name' in data
    assert 'inputs' in data
    assert 'outputs' in data

    # NEW: Comprehensive metadata
    assert 'function_info' in data
    assert 'underlying_software' in data['function_info']
    assert 'wrapper_function' in data['function_info']
    assert 'operation_type' in data['function_info']

    assert 'examples' in data
    assert 'usage_guide' in data
    assert 'citations' in data
    assert 'requirements' in data

def test_function_info_distinguishes_wrappers():
    """Test that different FastQC wrappers are distinguished"""
    # Primary FastQC
    resp1 = client.get("/api/tool_search/schema?tool_id=toolshed...devteam/fastqc")
    data1 = resp1.json()
    assert data1['function_info']['is_primary_function'] == True
    assert data1['function_info']['operation_type'] == 'primary_analysis'

    # FastQC Summary (post-processing)
    resp2 = client.get("/api/tool_search/schema?tool_id=toolshed...nml/fastqc_stats")
    data2 = resp2.json()
    assert data2['function_info']['is_primary_function'] == False
    assert data2['function_info']['operation_type'] == 'post_processing'
    assert data2['function_info']['underlying_software'] == 'fastqc'
```

### 3.2 Frontend UI Tests

**Test scenarios:**
1. Open parameter dialog → Verify function info badge displays
2. Check wrapper function description matches database
3. Verify software version ≠ wrapper version
4. Confirm examples section appears when available
5. Test help links open in new tab

---

## 4. Migration Steps

### Phase 1: Backend (No Breaking Changes)
1. ✅ Add missing database columns (or handle gracefully)
2. ✅ Update `get_tool_schema()` to return comprehensive metadata
3. ✅ Fix database path configuration
4. ✅ Deploy backend
5. ✅ Test API returns new fields (old clients ignore them)

### Phase 2: Frontend
1. ✅ Update ParameterDialog component
2. ✅ Add ToolFunctionInfo component
3. ✅ Add examples display
4. ✅ Add help links
5. ✅ Deploy frontend
6. ✅ Test UI displays new information

### Phase 3: Enhancement
1. Add search filters by operation type
2. Add version comparison view
3. Add related tools suggestion (same underlying software)
4. Add citation export feature

---

## 5. Priority Summary

### CRITICAL (Must have for correct operation)
- [ ] Fix database path configuration (line 24-25 in search_index.py)
- [ ] Handle missing `is_installed` columns gracefully (line 171, 189 in search_index.py)

### HIGH (Exposes valuable new data)
- [ ] Update `get_tool_schema()` to return function_info for API completeness
- [ ] Show operation type badge in tool selection UI (helps users pick right tool)
- [ ] Show wrapper_function description in tool selection UI

### MEDIUM (Nice to have - Future)
- [ ] Add operation type filters in search/browse
- [ ] Citation export feature for researchers
- [ ] Related tools suggestions (same underlying software)

### LOW (Not needed for codeless platform)
- [ ] ~~Display code examples~~ (platform is codeless)
- [ ] ~~Show software version vs wrapper version~~ (technical detail)
- [ ] ~~Version comparison view~~ (technical detail)

---

## 6. Files to Modify

### Backend (CRITICAL)
- `lib/galaxy/tools/search_index.py` (3 changes):
  1. Fix database path configuration
  2. Handle missing is_installed columns
  3. Update get_tool_schema() to return function_info
- `database/galaxy_ai_tools.db` (add 3 columns OR handle gracefully)

### Frontend (HIGH - for better UX)
- `frontend/client/src/components/workflow-builder.tsx` or tool selection component:
  - Add operation type badge to tool list items
  - Show wrapper_function description
- `frontend/client/src/components/ui/badge.tsx` (if not exists, add)

### Frontend (NO CHANGES NEEDED)
- `frontend/client/src/components/parameter-dialog.tsx` - Keep as-is (codeless platform)

### Tests (Optional - New files)
- `tests/test_tool_search_comprehensive.py` - Backend API tests
- `frontend/tests/tool-selection.test.tsx` - Test operation type badges

---

## 7. Rollback Plan

If issues arise:
1. Backend can be rolled back independently (old schema still works)
2. Frontend can be rolled back independently (old API still works)
3. Database can stay updated (new columns don't break old code)

**Safe migration:** Backend changes are backward-compatible.

---

## Contact

For questions about these modifications:
- Database schema: See `DATABASE_SCHEMA_20251030.md`
- Backend changes: See `lib/galaxy/tools/search_index.py`
- Frontend changes: See `frontend/client/src/components/parameter-dialog.tsx`
