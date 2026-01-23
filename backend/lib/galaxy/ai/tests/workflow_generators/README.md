# Workflow Generator Tests

This folder contains tests for comparing different workflow generation approaches.

## Approaches Being Tested

| Approach | File | Description |
|----------|------|-------------|
| **Original** | `galaxy_workflow_generator.py` | Search-first, tool-constrained generation |
| **V1** | `propose_validate_workflow_generator.py` | LLM proposes, then validates against tool index |
| **V2** | `propose_validate_v2_experimental.py` | Proposes with context (searches workflows + tools first) |

## Test Results (2026-01-21)

Quick comparison with mock LLM:

| Metric | V1 | V2 |
|--------|----|----|
| Success | True | True |
| Steps | 4 | 4 |
| Confidence | 0.99 | 1.00 |
| Tools Available | True | True |
| Time | 0.076s | 0.177s |
| LLM Calls | 1 | 1 |
| Context Gathered | No | Yes (3 workflows, 9 tools) |

## Key Differences

### V1 (ProposeValidate)
- LLM proposes workflow from training knowledge
- Validates each tool against Galaxy index
- Refines if tools not found (max 2 iterations)
- Fast (~0.08s)

### V2 (ProposeValidateV2Experimental)
- **Searches existing workflows** before proposing
- **Checks available tools** for the domain
- LLM proposes with this context (informed proposal)
- Dynamic iteration until confidence threshold (0.85)
- Slower (~0.18s) due to context gathering

## Files

- `test_harness_workflow_generators.py` - Full test harness comparing all approaches
- `test_propose_validate_comparison.py` - Quick V1 vs V2 comparison
- `test_propose_validate_generator.py` - Unit tests for V1
- `test_propose_validate_simple.py` - Simple tests without pytest

## Running Tests

```bash
# From backend directory
cd /home/yzhang/biomate/backend

# Quick V1 vs V2 comparison
python -c "exec(open('lib/galaxy/ai/tests/workflow_generators/quick_compare.py').read())"

# Full test harness
python lib/galaxy/ai/tests/workflow_generators/test_harness_workflow_generators.py
```

## Status

- **V1**: Experimental, not integrated into production
- **V2**: Experimental, not integrated into production
- **Original**: Currently used in `ai_assistant.py` for low-confidence path

## Next Steps

1. Test with real LLM (not mock)
2. Compare quality of generated workflows
3. Benchmark with various intents
4. Decide which approach to use in production
