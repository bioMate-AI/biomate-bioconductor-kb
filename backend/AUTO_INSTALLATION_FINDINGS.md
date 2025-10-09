# Auto-Installation Implementation Analysis

**Date**: October 7, 2025
**Finding**: ❌ **AUTO-INSTALLATION NOT IMPLEMENTED**

---

## Your Correction is Correct

You are **100% correct** that:
1. **Tool index contains ALL available tools** (2,169 tools from ToolShed), NOT just installed tools
2. **Auto-installation SHOULD be implemented** during workflow execution
3. **I was wrong** to claim the system only uses installed tools

---

## Current Implementation Status

### What EXISTS ✅

#### 1. GalaxyChat Client Method (READY)
**File**: `/private/tmp/GalaxyChat_version2/server/galaxy-api-proxy.ts:120-125`

```typescript
async checkAndInstallTool(toolId: string): Promise<ToolInstallResponse> {
    const response = await this.client.post<ToolInstallResponse>(
        '/api/tool_search/check_and_install',  // ❌ Backend endpoint MISSING
        { tool_id: toolId }
    );
    return response.data;
}
```

**Status**: ✅ Client code ready, but calls non-existent backend endpoint

---

#### 2. Galaxy Core Installation Infrastructure (READY)
**File**: `/private/tmp/lcms-platform-galaxy/lib/galaxy/tool_shed/galaxy_install/install_manager.py`

- **867 lines** of complete ToolShed installation code
- `InstallRepositoryManager` class fully implemented
- Can install tools from Galaxy ToolShed
- Can manage dependencies and repositories

**Status**: ✅ Complete installation infrastructure exists

---

#### 3. Tool Detection in Galaxy (ACTIVE)
**File**: `/private/tmp/lcms-platform-galaxy/lib/galaxy/workflow/modules.py:906, 2213, 2259, 2319`

```python
raise ToolMissingException("Tool in subworkflow missing.", tool_id=step.module.tool_id)
raise ToolMissingException(f"Tool {self.tool_id} missing. Cannot add dummy datasets.", tool_id=self.tool_id)
raise ToolMissingException(f"Tool {self.tool_id} missing. Cannot augment tool state for input connections.", tool_id=self.tool_id)
raise ToolMissingException(f"Tool {self.tool_id} missing. Cannot compute runtime state.", tool_id=self.tool_id)
```

**Status**: ✅ Galaxy DETECTS missing tools during workflow invocation

---

### What is MISSING ❌

#### 1. Galaxy Backend API Endpoint (CRITICAL)
**Expected**: `POST /api/tool_search/check_and_install`

**File**: Should be in `/private/tmp/lcms-platform-galaxy/lib/galaxy/webapps/galaxy/api/tool_search.py`

**Status**: ❌ **FILE DOES NOT EXIST** - No `tool_search.py` in API directory

**Impact**: GalaxyChat cannot trigger tool installation because backend endpoint doesn't exist

---

#### 2. Pre-Invocation Tool Installation Logic (CRITICAL)
**Expected Location**: Either in:
- `/private/tmp/GalaxyChat_version2/server/routes.ts:415` (before calling invokeWorkflow)
- `/private/tmp/lcms-platform-galaxy/lib/galaxy/webapps/galaxy/api/workflows.py:1090` (before invoking)

**Current Code** (GalaxyChat routes.ts:415-431):
```typescript
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
    try {
        const { workflow_id, inputs, parameters } = req.body;
        if (!workflow_id) {
            return res.status(400).json({ error: "workflow_id is required" });
        }

        // ❌ NO TOOL INSTALLATION LOGIC HERE
        const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
        res.json(invocation);
    } catch (error: any) {
        // ...
    }
});
```

**Expected Logic**:
```typescript
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
    try {
        const { workflow_id, inputs, parameters } = req.body;

        // 1. Get workflow definition
        const workflow = await galaxyAPIBackend.getWorkflow(workflow_id);

        // 2. Extract all tool IDs from workflow steps
        const toolIds = workflow.steps.map(step => step.tool_id);

        // 3. Check and install each tool
        for (const toolId of toolIds) {
            await galaxyAPIBackend.checkAndInstallTool(toolId);  // ❌ Backend missing
        }

        // 4. Now invoke workflow (all tools guaranteed to be installed)
        const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);
        res.json(invocation);
    } catch (error: any) {
        // ...
    }
});
```

**Status**: ❌ **NOT IMPLEMENTED** - No pre-invocation tool installation

---

## Current Behavior (BROKEN)

### Workflow Execution Flow

```
1. User requests: "Metabolomics workflow"
   ↓
2. AI searches tool index (2,169 tools) → finds "MetaboAnalystR"
   ↓
3. AI generates workflow using "MetaboAnalystR" (tool_id from index)
   ↓
4. Workflow saved to Galaxy
   ↓
5. User clicks "Execute Workflow"
   ↓
6. GalaxyChat POST /api/galaxy/workflows/invoke
   ↓
7. Galaxy Platform tries to run workflow
   ↓
8. Galaxy checks if "MetaboAnalystR" is installed
   ↓
9. ❌ Tool NOT installed → ToolMissingException thrown
   ↓
10. ❌ Workflow execution FAILS
```

**Result**: ❌ **WORKFLOWS WILL FAIL** if they use tools not pre-installed

---

## Implementation Requirements

### Priority 1: Galaxy Backend API

**Create**: `/private/tmp/lcms-platform-galaxy/lib/galaxy/webapps/galaxy/api/tool_search.py`

```python
"""
Galaxy Tool Search and Installation API
"""
from fastapi import HTTPException
from galaxy.webapps.galaxy.api import Router, DependsOnTrans
from galaxy.managers.context import ProvidesAdminContext
from galaxy.tool_shed.galaxy_install.install_manager import InstallRepositoryManager

router = Router(tags=["tool_search"])

@router.post("/api/tool_search/check_and_install")
def check_and_install_tool(
    tool_id: str,
    trans: ProvidesAdminContext = DependsOnTrans
) -> dict:
    """
    Check if tool is installed; if not, install from ToolShed.
    Requires admin authentication.
    """
    # 1. Check if tool is already installed
    toolbox = trans.app.toolbox
    if tool_id in toolbox.tools():
        return {
            "success": True,
            "already_installed": True,
            "tool_id": tool_id,
            "message": "Tool already installed"
        }

    # 2. Search ToolShed for tool
    # 3. Install using InstallRepositoryManager
    install_manager = InstallRepositoryManager(trans.app)

    # Install tool from ToolShed
    # (Implementation details depend on ToolShed API)

    return {
        "success": True,
        "installed": True,
        "tool_id": tool_id,
        "message": "Tool installed successfully"
    }

@router.get("/api/tool_search")
def search_tools(q: str, category: str = None, limit: int = 50):
    """Search tools using galaxy_tool_rag.py"""
    # Use GalaxyToolRAG to search galaxy_ai_tools.db
    pass

@router.get("/api/tool_search/categories")
def get_categories():
    """Get tool categories"""
    # Use GalaxyToolRAG to get categories
    pass
```

**Estimated Effort**: 4-6 hours

---

### Priority 2: Pre-Invocation Tool Installation

**Modify**: `/private/tmp/GalaxyChat_version2/server/routes.ts:415`

```typescript
app.post("/api/galaxy/workflows/invoke", async (req, res) => {
    try {
        const { workflow_id, inputs, parameters } = req.body;

        console.log('[Workflow Invoke] Fetching workflow to check tools...');

        // 1. Get workflow definition
        const workflow = await galaxyAPIBackend.getWorkflow(workflow_id);

        // 2. Extract tool IDs from workflow steps
        const toolIds = workflow.steps
            .filter(step => step.tool_id)
            .map(step => step.tool_id);

        console.log(`[Workflow Invoke] Found ${toolIds.length} tools to check`);

        // 3. Check and install each tool
        const installResults = [];
        for (const toolId of toolIds) {
            console.log(`[Tool Install] Checking tool: ${toolId}`);
            try {
                const result = await galaxyAPIBackend.checkAndInstallTool(toolId);
                installResults.push(result);

                if (result.installed) {
                    console.log(`[Tool Install] ✅ Installed: ${toolId}`);
                } else if (result.already_installed) {
                    console.log(`[Tool Install] ✅ Already installed: ${toolId}`);
                }
            } catch (error) {
                console.error(`[Tool Install] ❌ Failed to install ${toolId}:`, error);
                return res.status(500).json({
                    error: 'ToolInstallationFailed',
                    message: `Failed to install tool: ${toolId}`,
                    tool_id: toolId
                });
            }
        }

        console.log('[Workflow Invoke] All tools installed, invoking workflow...');

        // 4. Now invoke workflow (all tools guaranteed installed)
        const invocation = await galaxyAPIBackend.invokeWorkflow(workflow_id, inputs, parameters);

        res.json({
            ...invocation,
            tools_installed: installResults
        });

    } catch (error: any) {
        console.error("Workflow invocation error:", error);
        res.status(error.status_code || 500).json({
            error: error.error || 'InvocationError',
            message: error.message || 'Failed to invoke workflow',
        });
    }
});
```

**Estimated Effort**: 1-2 hours

---

## Corrected Workflow Execution Flow (AFTER IMPLEMENTATION)

```
1. User requests: "Metabolomics workflow"
   ↓
2. AI searches tool index (2,169 ALL tools) → finds "MetaboAnalystR"
   ↓
3. AI generates workflow using "MetaboAnalystR" (from full catalog)
   ↓
4. Workflow saved to Galaxy
   ↓
5. User clicks "Execute Workflow"
   ↓
6. GalaxyChat POST /api/galaxy/workflows/invoke
   ↓
7. **NEW**: GalaxyChat checks workflow tools
   ↓
8. **NEW**: For each tool:
      → POST /api/tool_search/check_and_install
      → Galaxy checks if installed
      → If not installed → InstallRepositoryManager.install()
      → Wait for installation to complete (5-30 min)
   ↓
9. **NEW**: All tools now installed ✅
   ↓
10. Galaxy Platform invokes workflow
   ↓
11. ✅ Workflow executes successfully (all tools available)
```

**Result**: ✅ **WORKFLOWS EXECUTE SUCCESSFULLY** regardless of pre-installed tools

---

## Summary

### You Were Right ✅

1. ✅ Tool index contains ALL tools (2,169 from ToolShed), not just installed
2. ✅ Auto-installation SHOULD happen during workflow invocation
3. ✅ Current implementation is INCOMPLETE

### What's Missing ❌

1. ❌ Galaxy Backend API: `/api/tool_search/check_and_install` endpoint
2. ❌ Pre-invocation logic: Tool installation before workflow execution
3. ❌ Tool search APIs: `/api/tool_search`, `/api/tool_search/categories`

### Current Status ⚠️

**The system WILL FAIL if workflows use tools that aren't pre-installed**

- Tool catalog search finds ANY tool from ToolShed
- Workflows are generated using those tools
- But execution fails with `ToolMissingException` if tools aren't already installed

### Solution Required 🔧

Implement the missing APIs and pre-invocation logic as outlined above.

**Estimated Total Effort**: ~6-8 hours

---

**Last Updated**: October 7, 2025
**Status**: ❌ **AUTO-INSTALLATION NOT IMPLEMENTED - SYSTEM WILL FAIL**
