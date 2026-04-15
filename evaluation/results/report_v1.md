# BioMate Evaluation — Competitive Report

_Generated from 46 result DBs in: results/_

## BioMate Scores vs Competitors

| Benchmark | BioMate | Target | Best Competitor | All Competitors |
|---|---|---|---|---|
| biomni_eval1 | 22.0% (n=223) | 65.0% | No competitor (BioMate-unique) | No competitor has this capability |
| biomni_eval1__rare_disease_diagnosis | **TBD** | — | Biomni (original): 67.0% | Biomni (original): 67.0% |
| bixbench | 2.9% (n=205) | 40.0% | Biomni Lab: 52.2% | GPT-4o (baseline): 17.0%; Claude 3.5 Sonnet: 17.0%; Claude Code Opus 4.6: 39.5%; OpenAI Agents SDK: 38.5%; Edison Analysis: 42.4%; Biomni Lab: 52.2% |
| bixbench_verified50 | **TBD** | 70.0% | Biomni Lab: 88.7% | Claude Code Opus 4.6: 65.3%; OpenAI Agents SDK: 61.3%; Edison Analysis: 78.0%; Biomni Lab: 88.7% |
| cross_domain_routing | 94.6% (n=120) | 80.0% | Raw LLM + GalaxyMCP (est.): 45.0% | BM25 keyword (est.): 35.0%; Raw LLM + GalaxyMCP (est.): 45.0% |
| license_gating | 98.2% (n=54) | 90.0% | No competitor (BioMate-unique) | No competitor has this capability |
| prereq_recovery | 97.5% (n=40) | 85.0% | GalaxyMCP (est.): 42.0% | Raw LLM (est.): 38.0%; GalaxyMCP (est.): 42.0% |
| protocol_thresholds | 65.0% (n=20) | 80.0% | — | MultiQC (universal thresholds): N/A (naive=FAIL on all 20 edge cases) |
| sgi_bench | 20.9% (n=369) | — | GPT-4o: 72.0% | GPT-4o: 72.0%; Claude 3.5 Sonnet: 69.0% |
| sgi_bench_life | **TBD** | 60.0% | GPT-4o: 72.0% | GPT-4o: 72.0%; Claude 3.5 Sonnet: 69.0% |

## Run History

| run_id | benchmark | n | mean_score | finished_at |
|---|---|---|---|---|
| sgi_bench_20260410_041202 | sgi_bench | 369 | 0.209 | 2026-04-10T05:30:41.375963 |
| bixbench_20260410_041155 | bixbench | 205 | 0.029 | 2026-04-10T04:30:18.323159 |
| biomni_eval1_20260410_041150 | biomni_eval1 | 223 | 0.220 | 2026-04-10T04:27:07.921321 |
| sgi_bench_20260410_035940 | sgi_bench | 10 | 0.100 | 2026-04-10T04:00:43.316405 |
| biomni_eval1_20260410_035943 | biomni_eval1 | 20 | 0.050 | 2026-04-10T04:00:22.893424 |
| bixbench_20260410_035628 | bixbench | 10 | 0.100 | 2026-04-10T03:57:29.833328 |
| sgi_bench_20260410_035621 | sgi_bench | 10 | 0.000 | 2026-04-10T03:57:25.069012 |
| biomni_eval1_20260410_033505 | biomni_eval1 | 10 | 0.100 | 2026-04-10T03:35:35.892355 |
| bixbench_20260410_033332 | bixbench | 10 | 0.100 | 2026-04-10T03:34:40.252177 |
| sgi_bench_20260410_033326 | sgi_bench | 10 | 0.000 | 2026-04-10T03:34:30.710916 |
| sgi_bench_20260410_031525 | sgi_bench | 10 | 0.000 | 2026-04-10T03:16:28.992173 |
| biomni_eval1_20260410_031322 | biomni_eval1 | 10 | 0.000 | 2026-04-10T03:15:07.343190 |
| prereq_recovery_20260410_022321 | prereq_recovery | 40 | 0.975 | 2026-04-10T02:50:28.936534 |
| prereq_recovery_20260410_015820 | prereq_recovery | 40 | 0.975 | 2026-04-10T02:26:11.065690 |
| prereq_recovery_20260410_020036 | prereq_recovery | 30 | 0.967 | 2026-04-10T02:21:18.817214 |
| prereq_recovery_20260410_014414 | prereq_recovery | 20 | 0.950 | 2026-04-10T01:58:09.988568 |
| prereq_recovery_20260410_013906 | prereq_recovery | 8 | 1.000 | 2026-04-10T01:44:06.573525 |
| prereq_recovery_20260410_012644 | prereq_recovery | 5 | 1.000 | 2026-04-10T01:29:58.064380 |
| prereq_recovery_20260410_005019 | prereq_recovery | 3 | 1.000 | 2026-04-10T00:52:15.418499 |
| cross_domain_routing_20260409_235509 | cross_domain_routing | 120 | 0.946 | 2026-04-10T00:36:28.200642 |

## Notes

- Competitor scores sourced from: `docs/papers/20260401_COMPETITOR_BENCHMARK_LANDSCAPE.md`
- `(est.)` scores are rough estimates, not from published papers
- BioMate-unique benchmarks have no published competitor baseline
- Scores on BixBench should note: original ground truth has errors (see BixBench-Verified-50)