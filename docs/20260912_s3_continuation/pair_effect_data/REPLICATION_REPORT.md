# Donor-pair effect replication — 12 September 2026

Known-perturbation transfer only. Each direction compares two nonoverlapping donor pairs. The three complementary partitions reuse four donors; directions are not independent cohorts.

| Source → destination | Matched rows | Transfer MSE | Mean baseline MSE | Transfer Spearman | Baseline Spearman | Shuffled Spearman mean |
|---|---:|---:|---:|---:|---:|---:|
| CE0006864_CE0008162 → CE0008678_CE0010866 | 80 | 0.238636 | 0.256398 | 0.314197 | 0.165843 | 0.059492 |
| CE0006864_CE0008678 → CE0008162_CE0010866 | 80 | 0.259431 | 0.242998 | 0.280238 | 0.170990 | 0.061425 |
| CE0006864_CE0010866 → CE0008162_CE0008678 | 80 | 0.219308 | 0.227341 | 0.313556 | 0.221297 | 0.066779 |
| CE0008162_CE0008678 → CE0006864_CE0010866 | 80 | 0.219308 | 0.224069 | 0.313556 | 0.196050 | 0.068418 |
| CE0008162_CE0010866 → CE0006864_CE0008678 | 80 | 0.259431 | 0.251660 | 0.280238 | 0.181910 | 0.059941 |
| CE0008678_CE0010866 → CE0006864_CE0008162 | 80 | 0.238636 | 0.216633 | 0.314197 | 0.216706 | 0.059614 |

Effects and baselines use identical finite readout masks, including all 100 fixed-seed null comparisons. The masks and row indices are saved separately. Full results include constant-row exclusions, coverage and null reference quantiles. A zero correlation is never substituted for an undefined correlation.

The baseline averages all source-pair effects in the same condition. The null permutes matched source target assignments within condition, allowing fixed points. The same-target source effect is an observed experimental effect, not a learned model prediction. Strong replication would establish available response signal, not predictive generalization.

Selection is restricted to successful on-target perturbations and the earlier development panel. These results do not establish donor-independent baseline-state modeling; no model was trained.

Observed result: same-target rank agreement is 0.280–0.314, above condition means (0.166–0.221) and shuffled assignment means (0.059–0.068). Same-target MSE improves on the condition mean in only 3 of 6 directions. Rank replication is present in this selected panel, but magnitude transfer is inconsistent. No missing, constant or fewer-than-three-readout rows were excluded. Synthetic metric checks and independent alignment/MSE recomputation passed; see `replication_verification.json`.
