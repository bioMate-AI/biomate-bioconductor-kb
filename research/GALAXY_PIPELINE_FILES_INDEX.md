# Galaxy Pipeline Files Index
**Repository:** https://github.com/bioMate-AI/galaxy
**Cloned to:** `/home/yzhang/biomate/research/galaxy`
**Date:** November 4, 2025

---

## Summary

Galaxy has been successfully cloned and analyzed for pipeline/workflow files.

### Quick Stats
- **Galaxy Workflow Files (.ga):** Found in repository
- **Workflow Directories:** 11 major directories
- **Pipeline Implementation:** Multiple Python modules

---

## 1. Galaxy Workflow Files (.ga format)

### Root Level Workflows
```
./enhanced_cloud_workflow.ga          # Enhanced cloud execution workflow
./real_complex_workflow.ga            # Complex real-world workflow
./simple_cloud_workflow.ga            # Simple cloud workflow example
./test_cloud_workflow.ga              # Cloud workflow test
./test_cloud_workflow_simple.ga       # Simple cloud test workflow
./test_cloud_workflow_regex.ga        # Regex pattern test workflow
./test_cloud_workflow_multifile.ga    # Multi-file cloud workflow
./test_cloud_simple.ga                # Simple test workflow
```

---

## 2. Workflow Directories

### Core Workflow Implementation
- **`lib/galaxy/workflow/`** - Main workflow engine
- **`lib/galaxy/schema/workflow/`** - Workflow schema definitions
- **`lib/galaxy/ai/data/workflows/`** - AI-generated workflows
- **`lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow/`** - Cloud workflow executor

### Testing & Templates
- **`lib/galaxy_test/workflow/`** - Workflow tests
- **`test/unit/workflows/`** - Unit tests for workflows
- **`test/functional/tools/for_workflows/`** - Tools for workflow testing
- **`templates/webapps/galaxy/workflow/`** - Web UI templates

### Package & Client
- **`packages/app/galaxy/workflow/`** - Workflow package
- **`lib/tool_shed/test/test_data/filtering_workflow/`** - Tool shed workflow examples

---

## 3. Key Workflow Locations

### Where to Find:

**For AI-Generated Workflows:**
```
cd /home/yzhang/biomate/research/galaxy/lib/galaxy/ai/data/workflows
```

**For Core Workflow Engine:**
```
cd /home/yzhang/biomate/research/galaxy/lib/galaxy/workflow
```

**For Cloud Workflows:**
```
cd /home/yzhang/biomate/research/galaxy/lib/galaxy/galaxy-cloud-executor/galaxy_cloud/galaxy_workflow
```

**For Workflow Examples:**
```
cd /home/yzhang/biomate/research/galaxy
ls *.ga  # List all workflow files
```

---

## 4. Workflow File Types

### .ga Files (Galaxy Workflow Format)
- JSON-based workflow definition
- Contains steps, tools, connections, parameters
- Can be imported into Galaxy UI
- Editable via workflow editor

### Python Modules
- Workflow execution engine
- Workflow validation
- Workflow scheduling
- Workflow optimization

### YAML Files (GitHub Actions)
- CI/CD pipeline definitions in `.github/workflows/`
- Not Galaxy pipelines, but build/test pipelines

---

## 5. Notable Files

### Cloud Execution Workflows
```
enhanced_cloud_workflow.ga           # Production cloud workflow
simple_cloud_workflow.ga             # Basic cloud example
```

### Complex Workflows
```
real_complex_workflow.ga             # Real-world complex pipeline
```

### Test Workflows
```
test_cloud_workflow*.ga              # Various cloud test scenarios
```

---

## 6. Workflow Engine Files

Key Python files in `lib/galaxy/workflow/`:
- `run.py` - Workflow execution
- `scheduling_manager.py` - Workflow scheduling
- `extract.py` - Workflow extraction
- `modules.py` - Workflow modules
- `steps.py` - Workflow step definitions

---

## 7. AI Workflows

Location: `lib/galaxy/ai/data/workflows/`

This directory contains AI-generated or AI-assisted workflow templates.

---

## 8. Quick Commands

### List all .ga workflow files:
```bash
cd /home/yzhang/biomate/research/galaxy
find . -name "*.ga" -type f
```

### View a workflow file:
```bash
cat enhanced_cloud_workflow.ga | jq .
```

### Find workflow Python files:
```bash
find lib/galaxy/workflow -name "*.py" -type f
```

### Search for workflow-related code:
```bash
grep -r "class.*Workflow" lib/galaxy/workflow/*.py
```

---

## 9. Integration Opportunities

For BioMate integration, the most relevant are:

1. **`lib/galaxy/ai/data/workflows/`** - AI workflow templates
2. **`lib/galaxy/workflow/`** - Core engine to understand execution
3. **`*.ga` files in root** - Example workflows to test with

---

## 10. Next Steps

To explore specific workflows:

```bash
# 1. Go to research directory
cd /home/yzhang/biomate/research/galaxy

# 2. View AI workflows
ls -la lib/galaxy/ai/data/workflows/

# 3. Examine a workflow file
cat enhanced_cloud_workflow.ga | jq . | less

# 4. Check workflow engine
ls -la lib/galaxy/workflow/

# 5. Look at workflow tests
ls -la test/unit/workflows/
```

---

**Status:** ✅ Galaxy repository cloned and indexed
**Location:** `/home/yzhang/biomate/research/galaxy`
**Workflow Files:** Multiple .ga files found
**Implementation:** Complete Python workflow engine available
