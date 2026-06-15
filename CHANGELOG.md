# Changelog

All notable changes to the BioMate-KB Bioconductor skill bundle. Versions follow
[semantic versioning](https://semver.org/) (MAJOR = coverage/structure change).

## 2.0.0 — 2026-06-15
- **Coverage doubled: 100 → 200 packages** — added the **top 100 rising-star** Bioconductor
  analysis packages (newly released since ~2021, ranked by 2025 download growth).
- **Per-package `## Workflows` recipes** — packages that support several analyses now expose each
  as a `### ` recipe subsection (390 workflows across the 200 packages; 89 are multi-workflow).
- **Rising stars vignette-grounded** — all 100 rewritten grounded in their Bioconductor vignettes
  (mean function-name verify 0.91); each workflow recipe carries vignette-verified R code.
- **Pinned to Bioconductor 3.21** (previously the implicit moving `release` pointer) — recorded in
  `MANIFEST.json` (`bioconductor_version`).
- **New `PACKAGES.md`** — full 200-package table (Category · Package · Description · Workflows) with
  a domain jump-menu — plus per-domain histograms and a download-volume coverage / selection
  methodology section in the README.

## 1.0.0 — 2026-06-09
- Initial release: the **top 100** most-downloaded Bioconductor packages as Claude Code skills,
  vignette-grounded, each with when-to-use / parameters / assumptions / pitfalls / alternatives.
