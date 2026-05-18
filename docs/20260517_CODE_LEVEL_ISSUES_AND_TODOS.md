# Code-Level Issues and Technical Debt

**Date:** 2026-05-17
**Branch:** `integration/next-phase`
**Auditor:** Claude Code (stability assessment)

---

## Executive Summary

Beyond performance optimizations, the codebase has **7 categories of code-level issues** that should be addressed:

1. **Security vulnerabilities** (SQL injection, exposed secrets)
2. **Silent failure patterns** (swallowed exceptions, no error logging)
3. **Incomplete implementations** (TODOs, commented-out code)
4. **Resource leaks** (unclosed connections, memory leaks)
5. **Error handling gaps** (generic exceptions, no retries)
6. **Testing gaps** (no unit tests for critical paths)
7. **Documentation debt** (Chinese comments, missing docstrings)

---

## 1. Security Issues (CRITICAL)

### 1.1 Hardcoded API Keys in Logs

**File:** `backend/lib/galaxy/ai/llm_client.py`

**Issue:**
```python
log.debug(f"Using API key: {self.api_key[:10]}...")  # Logs first 10 chars of key
```

**Risk:** API keys visible in logs, could be leaked in log aggregation systems

**Fix:**
```python
log.debug(f"Using API key: {'*' * 10}...")  # Never log actual key
```

---

### 1.2 SQL Injection Risk (Potential)

**File:** `backend/lib/galaxy/ai/workflow_search.py`

**Need to verify:** Are user inputs sanitized before SQL queries?

**Example vulnerable pattern:**
```python
query = f"SELECT * FROM workflows WHERE name LIKE '%{user_input}%'"  # UNSAFE
```

**Should be:**
```python
query = "SELECT * FROM workflows WHERE name LIKE ?"
cursor.execute(query, (f'%{user_input}%',))
```

**Action:** Audit all SQL queries for parameterization

---

### 1.3 Exposed Secrets in Error Messages

**File:** Multiple files in `backend/lib/galaxy/ai/`

**Issue:**
```python
except Exception as e:
    log.error(f"Failed to connect: {e}")  # May contain connection strings with passwords
```

**Fix:**
```python
except Exception as e:
    log.error(f"Failed to connect: {type(e).__name__}")  # Only log error type
```

---

## 2. Silent Failure Patterns (HIGH)

### 2.1 Swallowed Exceptions

**File:** `backend/lib/galaxy/ai/ai_assistant.py` (multiple locations)

**Issue:**
```python
try:
    some_operation()
except Exception:
    pass  # SILENT FAILURE - no logging, no handling
```

**Found instances:**
- Line ~580: Memory update fails silently
- Line ~820: Literature search fails silently
- Line ~1100: Tool recommendation fails silently

**Impact:** Debugging is impossible, users see partial failures

**Fix:**
```python
try:
    some_operation()
except Exception as e:
    log.warning(f"Operation failed (non-critical): {e}", exc_info=True)
    # Return graceful fallback
```

---

### 2.2 Return Empty Results Instead of Errors

**File:** `backend/lib/galaxy/ai/tool_recommender.py`

**Issue:**
```python
except Exception as e:
    print(f"LLM tool recommendation failed: {e}")
    return []  # User thinks there are no tools, but actually system failed
```

**Fix:**
```python
except Exception as e:
    log.error(f"Tool recommendation failed: {e}")
    raise ToolRecommendationError("Tool search temporarily unavailable") from e
```

---

## 3. Incomplete Implementations (MEDIUM)

### 3.1 TODO Comments (20+ found)

**File:** `backend/lib/galaxy/ai/workflow_ops/autofix/`

**Examples:**
```python
# TODO: 实现实际的 workflow 重启逻辑
# TODO: 实际更新 workflow_invocation 的参数
# TODO: 从用户配置读取
# TODO: 实际发送HTTP请求到Slack
```

**Impact:** Features marked as incomplete may be exposed to users

**Action needed:**
1. Audit all TODOs
2. Complete critical ones (workflow restart, parameter updates)
3. Remove or disable incomplete features

---

### 3.2 Commented-Out Code

**Multiple files** - should be removed or moved to feature flags

**Bad:**
```python
# self.enable_feature_x = True  # Disabled for now
# if self.enable_feature_x:
#     do_something()
```

**Better:**
```python
if os.getenv('FEATURE_X_ENABLED', 'false') == 'true':
    do_something()
```

---

## 4. Resource Leaks (HIGH)

### 4.1 Unclosed HTTP Clients

**File:** `backend/lib/galaxy/ai/llm_client.py`

**Already addressed in our fallback implementation** ✅

---

### 4.2 Database Connection Leaks

**File:** Need to audit `backend/lib/galaxy/ai/workflow_search.py`

**Pattern to look for:**
```python
conn = sqlite3.connect(db_path)
# ... operations ...
# Missing: conn.close()
```

**Should be:**
```python
with sqlite3.connect(db_path) as conn:
    # ... operations ...
# Auto-closes
```

---

### 4.3 File Handle Leaks

**Audit needed** for all file operations:
```python
f = open(filename)
data = f.read()
# Missing: f.close()
```

---

## 5. Error Handling Gaps (MEDIUM)

### 5.1 Generic Exception Catching

**File:** Multiple files

**Issue:**
```python
except Exception as e:  # Too broad!
    handle_error(e)
```

**Should be:**
```python
except (httpx.HTTPError, TimeoutError) as e:  # Specific
    handle_network_error(e)
except ValueError as e:  # Specific
    handle_validation_error(e)
# Let other exceptions bubble up
```

---

### 5.2 No Distinction Between Transient and Permanent Errors

**File:** `backend/lib/galaxy/ai/llm_client.py`

**Issue:** Treats all errors the same
- 429 rate limit → should retry
- 401 unauthorized → should NOT retry
- 500 server error → should retry
- 400 bad request → should NOT retry

**Already partially fixed in our fallback implementation** ✅

---

## 6. Testing Gaps (HIGH)

### 6.1 No Unit Tests for LLM Client

**Missing:** `backend/tests/test_llm_client.py`

**Should test:**
- Retry logic
- Fallback behavior
- Error handling
- Billing emission

---

### 6.2 No Integration Tests for Workflow Execution

**Missing:** End-to-end tests for:
- Workflow generation → execution → completion
- QC gate triggers
- Auto-loop functionality

---

### 6.3 No Load Testing

**Impact:** Unknown behavior under concurrent load
- How many concurrent users can it handle?
- Does it crash under load?
- Are there race conditions?

---

## 7. Documentation Debt (LOW)

### 7.1 Chinese Comments

**File:** `backend/lib/galaxy/ai/workflow_ops/autofix/` (multiple)

**Issue:** Comments in Chinese make code hard to review for non-Chinese speakers

**Examples:**
```python
# TODO: 实现实际的 workflow 重启逻辑
# TODO: 使用 LLM 或正则表达式提取参数
```

**Action:** Translate to English or add English translations

---

### 7.2 Missing Docstrings

**Many functions lack docstrings**, especially:
- Complex algorithmic functions
- Public API endpoints
- Configuration parameters

**Example:**
```python
def _try_provider_with_retry(llm_client, provider_config, prompt, **kwargs):
    # What does this do? What are the parameters? What does it return?
    ...
```

**Should be:**
```python
def _try_provider_with_retry(
    llm_client: LLMClient,
    provider_config: LLMProviderConfig,
    prompt: str,
    **kwargs
) -> str:
    """
    Try a specific LLM provider with exponential backoff retry.

    Args:
        llm_client: The LLMClient instance
        provider_config: Configuration for the provider to try
        prompt: User prompt to send to LLM
        **kwargs: Additional arguments (user_id, session_id, etc.)

    Returns:
        Generated text from the LLM

    Raises:
        Exception: If all retry attempts fail
    """
```

---

## Prioritized Action Items

### Week 1: Critical (Must Do Before Release)

| Issue | File | Time | Priority |
|-------|------|------|----------|
| Remove API key logging | `llm_client.py` | 15min | CRITICAL |
| Add specific exception types | `llm_client.py` | 30min | CRITICAL |
| Fix silent failures in ai_assistant | `ai_assistant.py` | 2h | HIGH |
| Audit SQL injection risks | `workflow_search.py` | 1h | CRITICAL |
| Close all resource leaks | Multiple | 2h | HIGH |

**Total: ~6 hours**

### Week 2: High (Should Do Soon)

| Issue | File | Time | Priority |
|-------|------|------|----------|
| Complete TODO implementations | `workflow_ops/` | 4h | HIGH |
| Add unit tests for LLM client | `tests/` | 3h | HIGH |
| Add integration tests | `tests/` | 4h | MEDIUM |
| Translate Chinese comments | Multiple | 2h | LOW |

**Total: ~13 hours**

### Week 3+: Medium (Nice to Have)

| Issue | File | Time | Priority |
|-------|------|------|----------|
| Add comprehensive docstrings | Multiple | 6h | MEDIUM |
| Set up load testing | `tests/` | 4h | MEDIUM |
| Remove commented-out code | Multiple | 2h | LOW |

**Total: ~12 hours**

---

## Quick Wins (Can Do Today)

### 1. Remove API Key Logging (15 min)

```bash
cd /Users/kky/biomate/backend
grep -r "api.key\|API.KEY" lib/galaxy/ai --include="*.py" | grep log
# Review each instance, replace with masked version
```

### 2. Add Specific Exception Types (30 min)

Replace all:
```python
except Exception as e:
```

With specific types:
```python
except (httpx.HTTPError, TimeoutError) as e:
```

### 3. Add Error Context (1 hour)

Wrap all bare `except: pass` with:
```python
except Exception as e:
    log.warning(f"Non-critical operation failed: {e}", exc_info=True)
```

---

## Testing Strategy

### Unit Tests (Priority 1)

```python
# backend/tests/unit/test_llm_fallback.py

@pytest.mark.asyncio
async def test_primary_succeeds():
    """Primary provider works → no fallback"""

@pytest.mark.asyncio
async def test_primary_fails_fallback_succeeds():
    """Primary fails → fallback succeeds"""

@pytest.mark.asyncio
async def test_all_providers_fail():
    """All providers fail → raise error"""
```

### Integration Tests (Priority 2)

```python
# backend/tests/integration/test_workflow_execution.py

def test_full_workflow_lifecycle():
    """Test: generate → execute → QC → complete"""

def test_qc_gate_blocks_workflow():
    """Test: QC gate fires when threshold exceeded"""

def test_autoloop_remediates_failure():
    """Test: Auto-loop fixes failed step"""
```

### Load Tests (Priority 3)

```python
# backend/tests/load/test_concurrent_users.py

def test_10_concurrent_users():
    """Can handle 10 users simultaneously?"""

def test_100_concurrent_workflows():
    """Can run 100 workflows in parallel?"""
```

---

## Monitoring and Alerting

### Metrics to Track

1. **Error rates by type:**
   - LLM failures
   - Workflow execution failures
   - QC gate triggers
   - Auto-loop attempts

2. **Performance:**
   - LLM call latency
   - Workflow execution time
   - Memory usage per worker

3. **Business metrics:**
   - Workflows generated per day
   - Success rate
   - Provider usage distribution (Gemini vs Claude vs OpenAI)

### Alerts to Configure

1. **Critical:**
   - All LLM providers down
   - Backend crashes
   - Memory >90%

2. **Warning:**
   - LLM fallback rate >10%
   - Error rate >5%
   - Response time >5s

---

## Related Documents

- `docs/20260517_LLM_PRIORITY_AND_FALLBACK_IMPLEMENTATION.md` - LLM fallback design
- `docs/20260517_STABILITY_ASSESSMENT_AND_FIXES.md` - System-level issues
- `docs/20260517_IMMEDIATE_STABILITY_FIXES.md` - Performance optimizations
- `backend/tests/FUNCTIONAL_TEST_SUMMARY.md` - Current test coverage

---

## Summary

**Total technical debt identified:** ~30 hours of work
- Week 1 (critical): 6 hours
- Week 2 (high): 13 hours
- Week 3+ (medium): 12 hours

**Recommendation:** Focus on Week 1 items before production release.

Most critical:
1. ✅ LLM fallback (DONE)
2. Remove API key logging
3. Fix silent failures
4. Audit SQL injection
5. Close resource leaks

After these, system will be production-ready from a code quality perspective.
