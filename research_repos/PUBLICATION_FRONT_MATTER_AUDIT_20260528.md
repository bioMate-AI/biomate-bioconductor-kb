# Front Matter + End Matter Audit — 2026-05-28

Audit of author block, affiliations, correspondence, ORCIDs, DAS/CAS, repo URLs, and acknowledgments across the 3 BioMate manuscripts. **No edits applied** — this is a user-action punch list before bioRxiv submission.

## Flagship (`flagship_paper/manuscript/MANUSCRIPT_DRAFT.md`)

| Item | State |
|---|---|
| Authors | L11: `Yaoyun Zhang¹*, Yuhan Zhang²* *(placeholder — confirm with corresponding author)*` — has editorial placeholder comment |
| Affiliations | L13-14: BioMate AI; St. Jude Dept of Structural Biology, Memphis, TN, USA — BioMate AI address incomplete |
| Corresponding author | **MISSING** |
| Equal contribution | L15: present |
| ORCID | **MISSING** |
| Funding | **MISSING** |
| Competing interests | **MISSING** |
| DAS | **MISSING** |
| CAS | ~L157: `https://github.com/[REPO-PLACEHOLDER]/biomate` — literal placeholder |
| Acknowledgments | **MISSING** |

## AutoLoop (`autoloop_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`)

| Item | State |
|---|---|
| Authors | L13: same `*(placeholder — confirm…)*` editorial comment |
| Affiliations | L15-16: same as Flagship — BioMate AI address incomplete |
| Corresponding author | **MISSING** |
| Equal contribution | L17: present |
| ORCID | **MISSING** |
| Funding | **MISSING** |
| Competing interests | **MISSING** |
| DAS | **MISSING** |
| CAS | **MISSING** |
| Acknowledgments | **MISSING** |

## BioMate-Cryo (`cryo_em_benchmark_paper/manuscript/MANUSCRIPT_DRAFT.md`)

| Item | State |
|---|---|
| Authors | L11: clean — no placeholder text |
| Affiliations | L13-14: BioMate AI (incomplete address); St. Jude Memphis TN USA |
| Corresponding author | L16: `yaoyun.zhang@biomate.com; yuhan.zhang@stjude.org` — verify biomate.com email is operational |
| Equal contribution | L15: present |
| ORCID | **MISSING** |
| Funding | **MISSING** |
| Competing interests | **MISSING** |
| DAS | L365: present but "upon request" — vague |
| CAS | L365: "upon request" — no GitHub URL |
| Acknowledgments | **MISSING** |
| Preprint target | L5: "bioRxiv, before 2026-05-01" — past date, update |

## Cross-paper consistency

| Item | Flagship | AutoLoop | Cryo | Match |
|---|---|---|---|---|
| Author names | ✓ | ✓ | ✓ | Y |
| Affiliations (names) | ✓ | ✓ | ✓ | Y |
| Corresponding | missing | missing | present | **N** |
| DAS | missing | missing | vague | **N** |
| CAS | placeholder URL | missing | upon request | **N** |
| bioRxiv target | not stated | not stated | stale date | **N** |

## Punch list (user must fill)

| Paper | File | Item | Current | Action |
|---|---|---|---|---|
| Flagship | L11 | Author placeholder comment | `*(placeholder — confirm…)*` | Delete editorial comment |
| Flagship | L11 | Corresponding author | missing | Add email |
| Flagship | ~L157 | Repo URL | `[REPO-PLACEHOLDER]` | Fill real GitHub org |
| Flagship | L13 | BioMate AI address | name only | Add street/city/country |
| AutoLoop | L13 | Author placeholder comment | same | Delete |
| AutoLoop | L13 | Corresponding author | missing | Add email |
| AutoLoop | L15 | BioMate AI address | name only | Add address |
| AutoLoop | new | CAS section | missing | Add with repo URL |
| Cryo | L11 | BioMate AI address | name only | Add address |
| Cryo | L16 | biomate.com email | maybe placeholder | Verify or replace |
| Cryo | L5 | bioRxiv target date | past | Update |
| Cryo | L365 | DAS specificity | "upon request" | Commit to deposit (Zenodo? GitHub on acceptance?) |
| ALL 3 | front | ORCID iDs | missing | Add 2 ORCID URLs |
| ALL 3 | end | Funding statement | missing | Declare or state "No external funding" |
| ALL 3 | end | Competing interests | missing | Declare or state none |
| ALL 3 | end | Acknowledgments | missing | Draft acknowledgments |

## Summary

**~12 critical placeholder/missing items.** Top 3 most urgent:
1. **Corresponding author emails** — required by every venue; missing in Flagship + AutoLoop; verify in Cryo
2. **GitHub repository URL** — Flagship has literal `[REPO-PLACEHOLDER]`; AutoLoop + Cryo have none
3. **BioMate AI institutional address** — name-only across all 3; venues require full address

Secondary: ORCID iDs, Funding statement, Competing interests, Acknowledgments — uniformly missing across all 3.
