### A. Ladder, symbolic analog retrieval (R3-R2) yield
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| ihlm_ladder zc k=5 | B | dev 0-9 | R3-R2 | yield (hits/500) | 3.7 | [1.566, 5.834] | [-0.852, 8.252] | 24 (16) | 2024_Faris (0.358) | 1.8 |
| ihlm_ladder zc k=5 | B | conf 10-19 | R3-R2 | yield (hits/500) | 3.4 | [0.024, 6.776] | [-0.981, 7.781] | 24 (19) | 2016_Furukawa (0.339) | 1.5 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R3-R2 | yield (hits/500) | 12.1 | [6.473, 17.727] | [-5.467, 29.667] | 18 (15) | 2020_Townsend (0.489) | 5.3 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R3-R2 | yield (hits/500) | 9.5 | [6.244, 12.756] | [-3.999, 22.999] | 15 (11) | 2020_Townsend (0.486) | 4.2 |

### B. Ladder, held-out ranking per lab, regime L (E-AUROC, lab = unit)
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| ihlm_ladder zc k=5 | L | dev 0-9 | R1-R0 | E-AUROC per lab | 0.05 | [-0.012, 0.132] | [0.005, 0.095] | 9 (9) | 2020_Furukawa (0.283) | 0.037 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R2-R1 | E-AUROC per lab | -0.025 | [-0.078, 0.054] | [-0.117, 0.068] | 9 (9) | 2020_Furukawa (0.32) | 0.002 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R3-R2 | E-AUROC per lab | 0.077 | [-0.018, 0.111] | [0.007, 0.148] | 9 (9) | 2024_Koch (0.27) | 0.059 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R4-R3 | E-AUROC per lab | 0.006 | [-0.013, 0.04] | [-0.028, 0.04] | 9 (9) | 2022_Taechalertpaisarn (0.239) | -0.003 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R1-R0 | E-AUROC per lab | -0.003 | [-0.048, 0.058] | [-0.088, 0.083] | 9 (9) | 2018_Naylor (0.504) | 0.033 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R2-R1 | E-AUROC per lab | 0.029 | [-0.03, 0.086] | [-0.028, 0.085] | 9 (9) | 2022_Bhardwaj (0.161) | 0.02 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R3-R2 | E-AUROC per lab | 0.092 | [0.007, 0.125] | [0.002, 0.182] | 9 (9) | 2021_Comeau (0.311) | 0.063 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R4-R3 | E-AUROC per lab | -0.019 | [-0.037, 0.015] | [-0.048, 0.01] | 9 (9) | 2021_Comeau (0.302) | -0.012 |

### C. Ladder, other modules yield (B, L)
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| ihlm_ladder zc k=5 | B | dev 0-9 | R1-R0 | yield (hits/500) | 1.7 | [0.942, 2.458] | [0.109, 3.291] | 22 (17) | 2015_Wang (0.138) | 1.3 |
| ihlm_ladder zc k=5 | B | dev 0-9 | R2-R1 | yield (hits/500) | -1.3 | [-3.268, 0.668] | [-3.782, 1.182] | 24 (16) | 2024_Faris (0.146) | -0.7 |
| ihlm_ladder zc k=5 | B | dev 0-9 | R4-R3 | yield (hits/500) | 0.3 | [-0.289, 0.889] | [-0.389, 0.989] | 24 (11) | 2015_Ahlbach (0.091) | 0.2 |
| ihlm_ladder zc k=5 | B | conf 10-19 | R1-R0 | yield (hits/500) | 2.5 | [0.708, 4.292] | [-0.231, 5.231] | 23 (16) | 2016_Furukawa (0.244) | 1.5 |
| ihlm_ladder zc k=5 | B | conf 10-19 | R2-R1 | yield (hits/500) | -2.7 | [-5.133, -0.267] | [-4.77, -0.63] | 23 (15) | 2016_Furukawa (0.162) | -2.1 |
| ihlm_ladder zc k=5 | B | conf 10-19 | R4-R3 | yield (hits/500) | 0.7 | [-1.054, 2.454] | [-0.356, 1.756] | 24 (10) | 2022_Bhardwaj (0.2) | 0.4 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R1-R0 | yield (hits/500) | 2.8 | [-1.907, 7.507] | [-5.451, 11.051] | 18 (7) | 2020_Townsend (0.661) | -0.9 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R2-R1 | yield (hits/500) | -0.1 | [-4.223, 4.023] | [-1.709, 1.509] | 18 (17) | 2015_Bockus_1 (0.111) | -0.4 |
| ihlm_ladder zc k=5 | L | dev 0-9 | R4-R3 | yield (hits/500) | 0.0 | [-2.262, 2.262] | [-1.93, 1.93] | 17 (6) | 2020_Townsend (0.438) | -0.7 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R1-R0 | yield (hits/500) | 7.3 | [3.995, 10.605] | [-4.149, 18.749] | 18 (14) | 2020_Townsend (0.714) | 1.8 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R2-R1 | yield (hits/500) | -1.6 | [-4.563, 1.363] | [-3.251, 0.051] | 19 (17) | 2015_Wang (0.214) | -1.0 |
| ihlm_ladder zc k=5 | L | conf 10-19 | R4-R3 | yield (hits/500) | -1.8 | [-3.846, 0.246] | [-4.967, 1.367] | 13 (7) | 2020_Townsend (0.583) | -0.4 |

### D. L7 loop minus frozen, yield
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| gbm_aware | A | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 8.0 | [2.5, 13.5] | [-2.054, 18.054] | 22 (15) | 2020_Townsend (0.479) | 3.5 |
| gbm_aware | B | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 1.5 | [-2.55, 5.55] | [-3.185, 6.185] | 24 (17) | 2016_Furukawa (0.254) | 0.0 |
| gbm_aware | L | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 8.4 | [5.058, 11.742] | [-5.553, 22.353] | 19 (9) | 2021_Kelly (0.681) | 2.0 |
| gbm_aware | L | seeds 0-9 (n=10) | loop-frozen | yield (hits) | 47.3 | [32.47, 62.13] | [-53.011, 147.611] | 14 (14) | 2020_Townsend (0.887) | 0.9 |
| gbm_blind | A | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 8.5 | [5.332, 11.668] | [-0.985, 17.985] | 23 (15) | 2020_Townsend (0.452) | 4.3 |
| gbm_blind | B | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 1.4 | [-2.235, 5.035] | [-2.762, 5.562] | 24 (19) | 2024_Faris (0.2) | 2.6 |
| gbm_blind | L | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 3.1 | [-1.517, 7.717] | [-1.554, 7.754] | 18 (9) | 2020_Townsend (0.356) | 1.5 |
| gbm_blind | L | seeds 0-9 (n=10) | loop-frozen | yield (hits) | 13.2 | [0.298, 26.102] | [-7.306, 33.706] | 16 (15) | 2021_Kelly (0.537) | 4.5 |
| gbm_physchem | A | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 0.9 | [-2.937, 4.737] | [-1.326, 3.126] | 22 (13) | 2020_Townsend (0.226) | 0.2 |
| gbm_physchem | A | seeds 0-9 (n=10) | loop-frozen | yield (hits) | 15.0 | [-2.594, 32.594] | [-12.055, 42.055] | 18 (13) | 2020_Townsend (0.606) | 3.0 |
| gbm_physchem | B | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 3.2 | [1.046, 5.354] | [-0.255, 6.655] | 23 (16) | 2024_Faris (0.231) | 2.0 |
| gbm_physchem | B | seeds 0-9 (n=10) | loop-frozen | yield (hits) | 9.3 | [6.136, 12.464] | [1.605, 16.995] | 23 (20) | 2016_Furukawa (0.252) | 6.3 |
| gbm_physchem | L | seeds 0-9 (n=10) | loop_sub-frozen_sub | yield (hits) | 3.1 | [0.705, 5.495] | [-6.905, 13.105] | 17 (9) | 2021_Kelly (0.714) | -1.4 |
| gbm_physchem | L | seeds 0-9 (n=10) | loop-frozen | yield (hits) | 4.9 | [-6.348, 16.148] | [-7.118, 16.918] | 13 (11) | 2021_Kelly (0.684) | -0.5 |
| gbm_physchem | M | seeds 0-9 (n=7) | loop_sub-frozen_sub | yield (hits) | 3.0 | [-2.445, 8.445] | [-3.601, 9.601] | 20 (14) | 2021_Kelly (0.512) | 0.0 |

### E. L7 K_phys minus deterministic shuffled knowledge, yield
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| gbm_aware_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 5.0 | [2.949, 7.051] | [-0.869, 10.869] | 22 (14) | 2020_Townsend (0.419) | 2.4 |
| gbm_aware_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 1.9 | [-0.164, 3.964] | [-1.176, 4.976] | 24 (15) | 2024_Faris (0.333) | 0.6 |
| gbm_aware_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 1.8 | [-2.821, 6.421] | [-0.739, 4.339] | 20 (11) | 2020_Townsend (0.333) | 0.8 |
| gbm_aware_detK_confirm | A | seeds 10-29 (n=20) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 4.95 | [2.763, 7.137] | [0.003, 9.897] | 23 (17) | 2020_Townsend (0.376) | 2.9 |
| gbm_aware_detK_confirm | B | seeds 10-29 (n=20) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 4.85 | [2.414, 7.286] | [-0.569, 10.269] | 24 (20) | 2024_Faris (0.412) | 2.4 |
| gbm_aware_detK_confirm | L | seeds 10-29 (n=20) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 4.9 | [3.468, 6.332] | [-1.476, 11.276] | 22 (10) | 2020_Townsend (0.5) | 2.25 |
| gbm_blind_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 6.0 | [3.713, 8.287] | [0.215, 11.785] | 21 (12) | 2020_Townsend (0.406) | 3.4 |
| gbm_blind_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 4.1 | [1.753, 6.447] | [1.016, 7.184] | 24 (16) | 2024_Faris (0.164) | 3.2 |
| gbm_blind_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 5.2 | [0.542, 9.858] | [-4.882, 15.282] | 19 (7) | 2020_Townsend (0.828) | 0.4 |
| gbm_physchem_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 2.9 | [-0.463, 6.263] | [-1.247, 7.047] | 23 (13) | 2020_Townsend (0.442) | 1.0 |
| gbm_physchem_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 0.1 | [-2.67, 2.87] | [-1.472, 1.672] | 23 (15) | 2016_Furukawa (0.16) | -0.3 |
| gbm_physchem_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_kshuf_sub | yield (hits) | 0.5 | [-2.976, 3.976] | [-1.361, 2.361] | 21 (12) | 2021_Kelly (0.185) | 1.0 |

### F. L7 K_phys minus plain loop, yield
| group | regime | seeds | contrast | metric | estimate | seed-level t 95% | lab-cluster t 95% (n-1 df) | labs (non-zero) | top lab (share of effect) | estimate without top lab |
|---|---|---|---|---|---|---|---|---|---|---|
| gbm_aware_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 4.7 | [2.437, 6.963] | [0.913, 8.487] | 23 (14) | 2021_Kelly (0.264) | 3.3 |
| gbm_aware_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 4.8 | [1.963, 7.637] | [1.14, 8.46] | 24 (17) | 2021_Comeau (0.156) | 3.8 |
| gbm_aware_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | -1.4 | [-4.792, 1.992] | [-5.058, 2.258] | 20 (11) | 2021_Kelly (0.389) | -0.0 |
| gbm_aware_detK_confirm | A | seeds 10-29 (n=20) | loop_kphys_sub-loop_sub | yield (hits) | 2.75 | [0.438, 5.062] | [0.579, 4.921] | 23 (20) | 2024_Faris (0.254) | 1.85 |
| gbm_aware_detK_confirm | B | seeds 10-29 (n=20) | loop_kphys_sub-loop_sub | yield (hits) | 3.65 | [2.092, 5.208] | [1.215, 6.085] | 24 (20) | 2022_Bhardwaj (0.253) | 2.6 |
| gbm_aware_detK_confirm | L | seeds 10-29 (n=20) | loop_kphys_sub-loop_sub | yield (hits) | 1.25 | [-0.507, 3.007] | [-0.265, 2.765] | 22 (13) | 2022_Bhardwaj (0.178) | 0.85 |
| gbm_blind_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 2.4 | [-0.639, 5.439] | [0.107, 4.693] | 23 (14) | 2021_Kelly (0.25) | 1.6 |
| gbm_blind_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 4.9 | [1.99, 7.81] | [2.409, 7.391] | 24 (19) | 2015_Bockus_2 (0.127) | 4.2 |
| gbm_blind_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | -0.1 | [-4.209, 4.009] | [-2.434, 2.234] | 19 (12) | 2020_Townsend (0.241) | 0.6 |
| gbm_physchem_detK | A | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 1.2 | [-2.522, 4.922] | [-1.797, 4.197] | 23 (14) | 2020_Townsend (0.263) | 0.2 |
| gbm_physchem_detK | B | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | 1.7 | [-0.662, 4.062] | [-0.548, 3.948] | 23 (13) | 2021_Comeau (0.276) | 0.9 |
| gbm_physchem_detK | L | seeds 0-9 (n=10) | loop_kphys_sub-loop_sub | yield (hits) | -0.8 | [-3.736, 2.136] | [-4.281, 2.681] | 20 (12) | 2020_Townsend (0.306) | 0.3 |
