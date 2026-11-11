# Source Intelligence — VARIANT / CLINICAL cluster
**Sources:** ClinVar, dbSNP, gnomAD, OMIM, ClinicalTrials.gov, Open Targets
**Audited:** 2026-11-11 · all curl examples below executed live (`-A "BioMate/1.0"`) and returned the summarized result.

Repo under audit: `/Users/kky/biomate-syncprep-20261111`
- Federated layer: `backend/lib/galaxy/ai/federated_query.py` (`_FETCHERS`, `ENTITY_SOURCES`)
- Registry: `backend/lib/galaxy/ai/data_sources.py`
- ClinVar/variant helpers: `backend/lib/galaxy/ai/agents/research_agent.py`
- Open Targets engine: `backend/lib/galaxy/ai/target_id/data_channels.py` (`OPENTARGETS_GQL`, `_OT_ASSOC_QUERY`), `snapshot_open_targets.py`
- Skills: `backend/lib/galaxy/ai/skills/evidence-source-selection.md`, `gwas-statistician.md`, `clinical-biostatistician.md`, `regulatory-affairs.md`

---

## Current wiring snapshot (what exists today)

| Source | Surface | Current fetcher | Protocol |
|---|---|---|---|
| ClinVar | federation + helper | `_fetch_ncbi_entrez(q,"clinvar")` (title only) + `lookup_clinvar_gene()` (rich) | REST E-utils |
| dbSNP | federation | `_fetch_ncbi_entrez(q,"snp")` (title only) | REST E-utils |
| gnomAD | federation | `_fetch_gnomad()` — generic `search` query, returns **variant_id only, no frequency** | GraphQL |
| Open Targets | dedicated (not fan-out) | `OpenTargetsGeneticsChannel` / `write_ot_snapshot` (disease→targets) + `lookup_open_targets_gene` (stub, falls back to GWAS Catalog) | GraphQL |
| ClinicalTrials.gov | federation | `_fetch_clinicaltrials()` — v2, keyless, `query.term` only | REST v2 |
| OMIM | **declared gap, no handler** | `lookup_omim_gene()` goes via mygene.info (MIM IDs only, no key) | — |

`ENTITY_SOURCES`: `variant → [dbsnp, clinvar, gnomad, pubmed, semantic_scholar]`; `disease → [hpo, clinvar, clinicaltrials, pubmed, europepmc, semantic_scholar]`. Open Targets is **not** in any `ENTITY_SOURCES` list — only reachable through the target_id engine (`identify_targets`).

---

## 1. ClinVar

**1. What/URL/key.** NCBI's curated variant→clinical-significance archive. REST via **E-utilities** (`https://eutils.ncbi.nlm.nih.gov/entrez/eutils/`). No key required; add `&api_key=` to raise rate limit 3→10 req/s. Also a richer **VCV/RCV JSON** via `efetch` and a bulk `clinvar_vcf`/`variant_summary.txt.gz` FTP.

**2. Endpoints + use case.**
- gene→variants: `esearch.fcgi?db=clinvar&term=<GENE>[gene]` → UIDs → `esummary.fcgi?db=clinvar&id=…`. Identifier expected: **HGNC gene symbol**.
- variant→clinical significance: filter the term with `[CLNSIG]` (e.g. `pathogenic[CLNSIG]`, `"risk factor"[CLNSIG]`, `"likely benign"[CLNSIG]`, `"uncertain significance"[CLNSIG]`). esummary field `clinical_significance.description` + `trait_set[].trait_name` (condition).
- variant by rsID: `term=rs34637584` (ClinVar resolves it).
- Richer record (HGVS, molecular consequence, review status / star rating): `efetch.fcgi?db=clinvar&rettype=vcv&id=<VCV>` (XML) or the Variation Services `https://www.ncbi.nlm.nih.gov/clinvar/api/v2/...`.

**3. Verified filter (CLNSIG improves relevance).**
```
curl -A "BioMate/1.0" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?db=clinvar&term=LRRK2%5Bgene%5D+AND+%22risk+factor%22%5BCLNSIG%5D&retmax=3&retmode=json"
```
→ `count=2, ids=['1943','1940']` — the LRRK2 G2385R "risk factor" class is retrievable only with the non-pathogenic CLNSIG filter. `BRCA1[gene] AND pathogenic[CLNSIG]` → count=14336 (so always cap + sort by review status).

**4. Pitfalls.** (a) `pathogenic_only` historically hid benign/risk-factor/VUS — the known LRRK2 bug. (b) esummary **title is legacy protein notation** (`NM_…(GENE):c.… (p.Gly2019Ser)`) — HGVS vs legacy G2019S must be normalized (done in `_normalize_protein_variant`). (c) No assembly in esummary; VCV needed for GRCh37/38 coordinates. (d) Review status (0–4 gold stars) is the real confidence signal and is **absent** from the esummary path — needs efetch/VCV. (e) `clinical_significance` can be a compound string (`pathogenic-likely-pathogenic,risk-factor`).

**5. Current + gaps.** `lookup_clinvar_gene()` is now correct (all-CLNSIG when `pathogenic_only=False`, `signal_errors` for None-vs-empty). **Gaps:** no CLNSIG as a structured filter param (it's all-or-pathogenic); no star/review-status ranking; the federation path `_fetch_ncbi_entrez` returns **only the title** (drops significance + condition that `lookup_clinvar_gene` already extracts) — the fan-out underuses ClinVar.

**6. Integrate.** Skill `evidence-source-selection.md` already lists ClinVar under Variant + Disease facets. External: NCBI ClinVar E-utils docs (https://www.ncbi.nlm.nih.gov/books/NBK25501/), ClinVar Variation Services (https://www.ncbi.nlm.nih.gov/variation/services/).

**7. Fixes (priority).**
- **P1** Route the federation `clinvar` fetcher through `lookup_clinvar_gene(..., pathogenic_only=False)` so fan-out rows carry `clinical_significance` + `condition`, not just title.
- **P2** Add optional `clnsig` param (enum: pathogenic / likely_pathogenic / benign / risk_factor / uncertain) → inject `AND "<x>"[CLNSIG]`.
- **P3** Add review-status (star) ranking via one `efetch` VCV per top hit; sort practitioner-facing results by stars desc.

---

## 2. dbSNP

**1. What/URL/key.** NCBI catalog of short variants (SNV/indel). REST via E-utils `db=snp`; also **SPDI/Variation Services** (`https://api.ncbi.nlm.nih.gov/variation/v0/`) for coordinate↔rsID↔HGVS. No key needed.

**2. Endpoints + use case.** rsID→annotation: `esummary.fcgi?db=snp&id=<numeric rsid>`; identifier = **rsID without the `rs` prefix** for `id=`, or `term=rs…` for esearch. esummary returns `genes`, `clinical_significance`, `global_mafs` (frequency by project: 1000G, ALFA, TOPMED, gnomAD), `snp_class`, `chrpos` (GRCh38) + `chrpos_prev_assm` (GRCh37). Variation Services `…/refsnp/<rsid>` gives full allele/HGVS/placement JSON.

**3. Verified.**
```
curl -A "BioMate/1.0" "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?db=snp&id=34637584&retmode=json"
```
→ `gene=LRRK2, clinsig=pathogenic-likely-pathogenic,risk-factor,pathogenic, global_mafs=10 projects`. So dbSNP esummary alone yields gene + clinvar-significance + MAF without a second call.

**4. Pitfalls.** (a) `id=` wants the bare integer; passing `rs34637584` to `id=` fails. (b) Two assemblies in the record (`chrpos` GRCh38 vs `chrpos_prev_assm` GRCh37) — must pick explicitly. (c) MAF is per-project; pick the right cohort. (d) Merged rsIDs redirect — a queried rsID may be reported under a newer one.

**5. Current + gaps.** `_fetch_ncbi_entrez(q,"snp")` returns **only `title`** — discards the gene, clinical_significance and global_mafs the same esummary already contains. Large waste.

**6. Integrate.** External: dbSNP E-utils + NCBI Variation Services (https://api.ncbi.nlm.nih.gov/variation/v0/). In-repo: `lookup_ensembl_vep` (research_agent) covers consequence prediction and complements dbSNP.

**7. Fixes.**
- **P1** Parse dbSNP esummary properly: emit `{rsid, gene, clinical_significance, maf (pick ALFA/gnomAD/1000G), snp_class, grch38, grch37}` instead of title.
- **P2** Add rsID→SPDI→HGVS normalization via Variation Services so a legacy coordinate query resolves to a canonical rsID (feeds gnomAD/ClinVar identifier chains).

---

## 3. gnomAD

**1. What/URL/key.** Broad population-allele-frequency resource. **GraphQL only**: `https://gnomad.broadinstitute.org/api`. No key; be gentle (public, rate-limited; single POST per query).

**2. Endpoints + use case.** gene→variants+freq: `gene(gene_symbol, reference_genome){variants(dataset:gnomad_r4){variant_id rsids genome{af populations{id ac an}}}}`. variant→frequency: `variant(variantId:"CHR-POS-REF-ALT", dataset:gnomad_r4){genome{af ac an populations{id ac an}} exome{af}}`. Identifier for a single variant = **gnomAD variant id `chrom-pos-ref-alt`** (GRCh38 for r4), NOT an rsID directly (rsID → use `search`/dbSNP to resolve to coordinates first). Also `region(...)`, `clinvar_variants`, constraint (`gnomad_constraint pLI/LOEUF`) on the gene object.

**3. Verified (two queries).**
```
curl -A "BioMate/1.0" -X POST https://gnomad.broadinstitute.org/api -H "Content-Type: application/json" \
  -d '{"query":"query($g:String!){gene(gene_symbol:$g,reference_genome:GRCh38){gene_id variants(dataset:gnomad_r4){variant_id rsids genome{af populations{id ac an}}}}}","variables":{"g":"PCSK9"}}'
```
→ `n_variants=4544`, ex `1-55039763-C-A`.
```
# variant-level freq, with rsid resolved in the row
-d '{"query":"query($v:String!){variant(variantId:$v,dataset:gnomad_r4){variant_id rsids genome{af ac an populations{id ac an}}exome{af}}}","variables":{"v":"1-55039974-G-T"}}'
```
→ `variant=1-55039974-G-T, rsids=['rs11591147'], genome_af=0.0122, populations=276` (276 includes sex-split subpops — must filter).

**4. Pitfalls.** (a) **GraphQL not REST** — the generic `search` query the current fetcher uses returns IDs with **no frequency**, defeating the purpose. (b) `dataset` is mandatory and versioned (`gnomad_r4` GRCh38 vs `gnomad_r2_1` GRCh37) — wrong dataset ⇒ wrong/empty freq and assembly mismatch. (c) `populations` array mixes top-level ancestries (afr/amr/eas/nfe/sas/asj/fin/ami/mid/remaining) with `_XX`/`_XY` sex splits — filter to top-level or you double-count. (d) variantId must be GRCh38 `chr-pos-ref-alt`; rsID is not accepted by `variant(variantId:)` — resolve via dbSNP/`search` first. (e) popmax / grpmax is the clinically relevant number (rare-disease ACMG BA1/BS1) — must compute max over top-level pops.

**5. Current + gaps.** `_fetch_gnomad()` uses a generic `search(query){gene/variant}` returning `variant_id` with **no allele frequency at all** — the single most important gnomAD field is missing. No dataset/assembly control, no popmax.

**6. Integrate.** External: gnomAD API docs (https://gnomad.broadinstitute.org/api) + browser schema. In-repo complements: `lookup_ensembl_vep`, GWAS Catalog helpers. Skill `gwas-statistician.md` references allele frequencies.

**7. Fixes.**
- **P1** Replace the `search` query with a real `variant(variantId,dataset)` query returning `genome.af/ac/an`, `exome.af`, and populations; add a `gene(...)→variants` mode. **Compute popmax** over top-level populations only.
- **P2** Add rsID→coordinate resolution (dbSNP or gnomAD `search` → feed `variantId`), and a `reference_genome`/`dataset` param (default GRCh38/`gnomad_r4`).

---

## 4. OMIM

**1. What/URL/key.** Authoritative gene↔Mendelian-disease catalog. REST `https://api.omim.org/api/` — **requires a registered API key** (free for academics; `?apiKey=...&format=json`). No key = no direct access.

**2. Endpoints + use case.** gene→disease: `entry?mimNumber=<MIM>&include=geneMap`. disease→gene/phenotype: `clinicalSynopsis` / `entry?include=clinicalSynopsis`. search: `entry/search?search=<term>`. Identifier = **6-digit MIM number** (or gene symbol via `geneMap/search`). Resolution chain: gene symbol → MIM via NCBI Gene / mygene.info → OMIM entry.

**3. Verified.** Not curled — live call needs a key the repo doesn't hold. Keyless proxy verified instead: mygene.info returns MIM IDs (`lookup_omim_gene` path) and Monarch returns OMIM→HPO phenotype associations (`lookup_omim_disease_phenotypes`).

**4. Pitfalls.** (a) **API key mandatory** — `data_sources.py` correctly marks OMIM `status="key_required"` with no handler. (b) Licensing: OMIM data redistribution is restricted; raw text can't be freely cached/shipped on-prem. (c) Phenotype-MIM vs gene-MIM distinction (same 6-digit space, different meaning). (d) Allelic variants in OMIM use legacy nomenclature.

**5. Current + gaps.** No real OMIM handler. `lookup_omim_gene()` only gets **MIM IDs** (via mygene.info, no key) and `lookup_omim_disease_phenotypes()` gets HPO terms **via Monarch, not OMIM**. So BioMate has the ID graph but **not OMIM's clinical synopsis / inheritance / allelic-variant text**.

**6. Integrate.** External: OMIM API (https://omim.org/api) — register for key. Keyless alternatives already wired: mygene.info, Monarch Initiative v3 (`api-v3.monarchinitiative.org`). Skill `clinical-biostatistician.md` / `regulatory-affairs.md` for the clinical framing.

**7. Fixes.**
- **P1** Keep the keyless Monarch+mygene path as the default (no key); add an **optional** real OMIM fetcher gated on `OMIM_API_KEY` env (inheritance pattern, clinical synopsis, allelic variants) — mirror the Paperclip key-gated pattern.
- **P2** Expose inheritance mode (AD/AR/XL) from OMIM geneMap to the variant-interpretation path.

---

## 5. ClinicalTrials.gov

**1. What/URL/key.** Registry of clinical studies. **REST API v2** `https://clinicaltrials.gov/api/v2/` — keyless, JSON. **API v1 was retired (deprecated → removed June 2024)**; must use v2.

**2. Endpoints + use case.** disease→trials: `studies?query.cond=<condition>`; drug→trials: `query.intr=<intervention>`; free text: `query.term=`. Filters that sharpen relevance: `filter.overallStatus=COMPLETED|RECRUITING|TERMINATED`, `query.term=AREA[Phase]PHASE3`, `filter.advanced`, `postFilter.*`, `fields=` to trim payload. Identifier = condition/intervention **free text** or NCT ID (`query.id=NCT…`). A full local mirror (609,551 studies) also exists in S3 per the registry note.

**3. Verified.**
```
curl -A "BioMate/1.0" "https://clinicaltrials.gov/api/v2/studies?query.cond=hypercholesterolemia&query.intr=evolocumab&filter.overallStatus=COMPLETED&pageSize=3&format=json&fields=NCTId,BriefTitle,OverallStatus,Phase"
```
→ 3 studies, all `COMPLETED PHASE3` (NCT01854918, NCT01813422, NCT01879319). Structured `query.cond`/`query.intr`/`filter.overallStatus` is far more precise than a single `query.term`.

**4. Pitfalls.** (a) v1 endpoints dead — never construct `…/api/query/…`. (b) `query.term` alone over-matches; `query.cond` + `query.intr` + status filter is the relevance lever. (c) Registry records ≠ results — `hasResults`/`whyStopped` are the useful trial-outcome proxies, not efficacy data. (d) Phase lives in `designModule.phases` (array, e.g. `['PHASE2','PHASE3']`), not a scalar.

**5. Current + gaps.** `_fetch_clinicaltrials()` is v2, keyless, parses the right modules (status, phase, sponsor, whyStopped, hasResults) — good. **Gap:** uses only `query.term`; ignores `query.cond`/`query.intr`/`filter.overallStatus`/phase filters, so disease→trials and drug→trials queries are coarser than they could be.

**6. Integrate.** External: ClinicalTrials.gov API v2 docs (https://clinicaltrials.gov/data-api/api). Skills `clinical-biostatistician.md`, `regulatory-affairs.md` frame trial-design/endpoint reasoning.

**7. Fixes.**
- **P1** When the entity is a disease, send `query.cond`; when a compound/drug, `query.intr`; keep `query.term` only as fallback. Add `filter.overallStatus` + phase passthrough params.
- **P2** Surface `hasResults`→link to results module; rank RECRUITING/COMPLETED above WITHDRAWN/TERMINATED for a "what trials exist" intent.

---

## 6. Open Targets

**1. What/URL/key.** Target–disease association + genetics (L2G) platform. **GraphQL only**, keyless. Platform API: `https://api.platform.opentargets.org/api/v4/graphql` (the former separate Genetics API is now folded into the Platform `v4` schema). No account.

**2. Endpoints + use case.** target→disease association: `target(ensemblId){associatedDiseases{rows{disease{id name} score datatypeScores}}}` — identifier = **Ensembl gene ID (ENSG…)**. disease→target (target ranking): `disease(efoId){associatedTargets{rows{target{approvedSymbol} score}}}` — identifier = **EFO/MONDO disease ID**. Name→ID resolution: `search(queryString,entityNames:["disease"|"target"]){hits{id name entity}}`. Genetics/L2G: variant & `credibleSets`/`l2g` fields on the v4 schema (variant→gene). Resolution chains: gene symbol → ENSG (via `search` or Ensembl/mygene); disease name → EFO/MONDO (via `search`).

**3. Verified (two queries).**
```
curl -A "BioMate/1.0" -X POST https://api.platform.opentargets.org/api/v4/graphql -H "Content-Type: application/json" \
 -d '{"query":"query($e:String!){target(ensemblId:$e){approvedSymbol associatedDiseases(page:{index:0,size:3}){count rows{disease{id name} score datatypeScores{id score}}}}}","variables":{"e":"ENSG00000169174"}}'
```
→ `PCSK9, count=926, top=[(familial hypercholesterolemia,0.856),(Hypercholesterolemia,0.826),(hypercholesterolemia AD 3,0.816)]`.
```
# disease name → EFO/MONDO
 -d '{"query":"query($q:String!){search(queryString:$q,entityNames:[\"disease\"]){hits{id name entity}}}","variables":{"q":"hypercholesterolemia"}}'
```
→ `[HP_0003124, MONDO_0005439 (familial hypercholesterolemia), MONDO_0007750]` — note top hit is an HP term; must filter to the intended ontology.

**4. Pitfalls.** (a) **GraphQL not REST**, and **not in the keyless fan-out** — only reachable through the target_id engine. (b) target queries want **ENSG**, not a symbol — symbol must be resolved first (the current `data_channels` resolves disease name→EFO via `search` to avoid guessing; same discipline needed for targets). (c) `search` returns mixed ontologies (HP/MONDO/EFO/Orphanet) — pick by entity + ontology prefix. (d) overall `score` blends evidence types; `datatypeScores` (genetic_association, known_drug, literature…) is what you actually want for a specific question. (e) Schema versioned at `/v4/` — older `/v3/` and the standalone Genetics endpoint are gone.

**5. Current + gaps.** `OpenTargetsGeneticsChannel` + `write_ot_snapshot` do disease→associatedTargets well (verified-against-live query, offline snapshot support). `lookup_open_targets_gene()` is a **stub** — its GraphQL L2G query is defined but never POSTed; it only falls back to GWAS Catalog `genomicContexts` for mapped genes. **Gap:** no variant→gene L2G actually hits Open Targets; target→disease direction and `datatypeScores` not exposed to the research agent; Open Targets absent from `ENTITY_SOURCES`, so a gene/disease fan-out never consults it.

**6. Integrate.** In-repo: `target_id/data_channels.py` (`OPENTARGETS_GQL`, `_OT_ASSOC_QUERY`), `snapshot_open_targets.py`, `docs/20261025_TARGETID_DECK_DATA_FOR_CLAUDE_DESIGN.md`. External: Open Targets GraphQL (https://api.platform.opentargets.org/api/v4/graphql, playground + schema). Skill `evidence-source-selection.md` lists Open Targets under Target-biology + Disease facets.

**7. Fixes.**
- **P1** Finish `lookup_open_targets_gene()`: actually POST the L2G/`credibleSets` query against `api.platform.opentargets.org/api/v4/graphql` (the GWAS-Catalog path becomes fallback only).
- **P2** Add a thin `target→associatedDiseases` reader (reuse `_default_http_post`) returning `datatypeScores`, and wire Open Targets into `ENTITY_SOURCES["gene"]`/`["disease"]` via a federation adapter so the keyless fan-out benefits.
- **P3** Centralize symbol→ENSG and disease-name→EFO resolution (via `search`) shared across ClinVar/gnomAD/Open Targets.

---

## Cross-cutting themes
1. **Fan-out underuses rich helpers.** ClinVar & dbSNP federation fetchers return titles only, discarding significance/condition/MAF that the same esummary call already contains (or that `lookup_clinvar_gene` already parses).
2. **gnomAD returns no frequency** — the biggest single defect (generic `search` query instead of `variant`/`gene` with `af`).
3. **Identifier resolution is scattered** — symbol→ENSG, name→EFO, rsID→coordinate each reimplemented; should be one shared resolver feeding ClinVar/gnomAD/Open Targets/dbSNP.
4. **Assembly/dataset discipline** (GRCh37 vs 38, gnomad_r2 vs r4) is not enforced anywhere.
5. **Open Targets is strong but siloed** in the target_id engine and its L2G helper is a stub.
6. **OMIM** is key-gated and correctly stubbed; keyless Monarch+mygene cover the ID/phenotype graph but not OMIM clinical text.
