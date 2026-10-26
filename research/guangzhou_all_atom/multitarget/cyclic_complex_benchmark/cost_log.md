# Cost log (spot only; cap $120). Prices are ASSUMPTIONS (not verified against the AWS price list).
| date | item | assumption | est. cost |
|---|---|---|---|
| 2026-10-25 | smoke0/1/1b/2 (3 complexes) | ~0.3 GPU-h @ ~$0.4/GPU-h | ~$0.2 |
| 2026-10-26 | pilot: 8 jobs, 40 complexes (26 produced samples; spot retries) | ~8 GPU-h | ~$3–4 |
| 2026-10-26 | ccd_check x2 (8 GB tar read, ~10 min each, spot GPU node) | ~0.5 GPU-h | ~$0.3 |
| 2026-10-26 | Stage B: 35 jobs, 410 complexes x 25 samples | ~41 GPU-h (≈6 min/complex on T4) | ~$15–25 |
Running total estimate after Stage B submission: ≈ $20–30 of the $120 cap.
