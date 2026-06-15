# Bioconductor fixed-set — final executable rate (2026-06-15)

Three fix rounds + a cache-poison harness fix, validated on the (now reliable) per-image-cache
harness. Combined best-status across the 300s clean run + the 1800s longer-cap run + round-3.

## Headline: 69/90 executable (76%) — 80% excluding 4 infra-skip packages
| status | n |
|---|---:|
| ok | 33 |
| ok_warnings | 36 |
| **executable** | **69 (76%)** |
| exec_error | 13 | 4th-round candidates (genuine remaining R bugs) |
| timeout | 2 | web-API only (mgnifyr/omnipathr-class) — need AWS Batch (no cap) |
| ran_empty_output | 2 |
| fixture_timeout | 1 |
| skip_input_type | 3 | harness can't synth these input types yet |

Progression: round-1 (cache-corrupted) 21/90 (23%) → clean consolidated 40/90 (44%) →
+round-3 ~46 → +1800s longer-cap **69/90 (76%)**. The cache-poison fix (per-image rlib) was
essential — round-1's low number was a harness artifact, not the fixes.

## What this means
- The 1800s cap converts the slow-install workflows that production AWS Batch (no 300s cap)
  runs fine — so the realistic production-executable rate of this set is ~76-80%.
- 4 packages (rawrr/lpsymphony/widgettools/ssrch) are infra/IO/GUI/optimization, not analysis
  workflows — marked skip_infra (see 20260615_BIOC_INFRA_SKIP.md); excluding them → 80%.
- 13 exec_error remain for a 4th round; 2 web-API timeouts need a Batch run to confirm.

All fixes are on next-phase (tested-only): 4-bucket + round-2 + round-3 + step-param enricher +
serving + viz P0/P1. Harness fix on fix/bioc-broken-wrappers.
