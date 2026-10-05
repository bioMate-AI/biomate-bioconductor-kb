# code_harvest — worked samples

Three real catalog pairs (one per provenance tier) and three real fix triples, taken verbatim
from `catalog_pairs.jsonl` / `fix_triples.jsonl` (the JSONL itself is git-ignored; regenerate
with the two scripts). Long fields are truncated here for readability.

---

## Catalog pairs (`catalog_pairs.jsonl`)

### 1. `receipted` — execution-receipt GOLD (`real_exec_status` ∈ ok/ok_warnings)

```jsonc
{
  "id": 10833,
  "name": "abseqr",
  "domain": "genomics",
  "provenance_tier": "receipted",
  "real_exec_status": "ok_warnings",
  "source": "bioconductor",
  "nextflow_path": "nextflow_nfcore/subworkflows/bioconductor/abseqr/main.nf",
  "nf_resolved_path": "backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/abseqr/main.nf",
  "params": {
    "required": [
      {"name": "dataPath", "type": "string", ...},
      {"name": "compare",  "type": "string", ...},
      {"name": "report",   "type": "number", ...},
      {"name": "BPPARAM",  "type": "string", ...},
      {"name": "outputDir","type": "string", ...}
    ],
    "optional": []
  },
  "steps": [{"step": "abseqr — basic_and_comparative_report", "phase": ...}],
  "holdout": false,
  "nf_code": "#!/usr/bin/env nextflow\n// Bioconductor workflow: abseqr ... (full .nf on disk)"
}
```

A known-good `.nf` with an execution receipt → highest-weight positive code-SFT pair and
benchmark-gold anchor. (None of the 1,092 receipted rows are `holdout` against current eval
families.)

### 2. `curated` — real resolvable `.nf`, no receipt yet

```jsonc
{
  "id": 10559,
  "name": "Analyze Circular Dichroism Spectra",
  "domain": "biochemistry",
  "provenance_tier": "curated",
  "real_exec_status": null,
  "source": "biomni_nextflow",
  "nextflow_path": "nextflow_nfcore/subworkflows/biochemistry/analyze_circular_dichroism_spectra/main.nf",
  "nf_resolved_path": "backend/biomni_workflows/.../analyze_circular_dichroism_spectra/main.nf",
  "description": "Analyzes circular dichroism (CD) spectroscopy data ... nf-core style module generated from tested Galaxy wrapper",
  "holdout": false,
  "nf_code": "#!/usr/bin/env nextflow\n/* biochemistry/analyze_circular_dichroism_spectra ... */ (340 lines on disk)"
}
```

Substantive real code (340 lines), no committed receipt → usable for retrieval/adaptation and
pattern-SFT, labelled curated (lower weight than receipted; absence of a receipt ≠ broken).

### 3. `stub` — catalog index entry, no local code

```jsonc
{
  "id": 1495,
  "name": "nf-core/diaproteomics",
  "domain": "proteomics",
  "provenance_tier": "stub",
  "real_exec_status": null,
  "source": "nfcore",
  "nextflow_path": "nfcore/diaproteomics/main.nf",
  "nf_resolved_path": null,
  "description": "RECOMMENDED PIPELINE FOR DIA PROTEOMICS ...",
  "holdout": false,
  "nf_code": null
}
```

The real nf-core pipeline is pulled at runtime and not vendored in this repo, so there is no
local `.nf` to learn from — index metadata (intent/description/domain) only. Usable for routing /
retrieval, **not** for code-SFT (no code).

---

## Fix triples (`fix_triples.jsonl`) — (broken → fixed + rationale)

### 1. `.nf` — parameter-name mismatch repair

- commit `501ea027e` (2026-01-26), +2/−2
- file `backend/biomni_workflows/nextflow_nfcore/subworkflows/biochemistry/one_site_model/main.nf`
- message: *"fix: Align Nextflow workflow parameters with Python function signatures"*

```diff
@@ def one_site_model(x, kd, dh, n):
-        Kd=auto_convert(os.environ.get("PARAM_KD", "")),
-        dH=auto_convert(os.environ.get("PARAM_DH", "")),
+        kd=auto_convert(os.environ.get("PARAM_KD", "")),
+        dh=auto_convert(os.environ.get("PARAM_DH", "")),
```

The triple carries full `before` + `after` file content plus the message rationale — exactly the
(broken code + why → fix) signal repair-SFT needs.

### 2. `.nf` — exp-decay signature alignment

- commit `501ea027e` (2026-01-26), +8/−10
- file `backend/biomni_workflows/nextflow_nfcore/subworkflows/bioengineering/exp_decay/main.nf`
- same fix family (param↔signature alignment across a batch of generated modules)

### 3. `executor` — Nextflow executor path-detection + AWS CLI bind-mount fix

- commit `ca1bd6ebc` (2026-04-09), +12/−7
- file `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
- message: *"fix: Batch18 — tighten EM tolerance + 1fs NVT; fix inline CSV path detection"*

```diff
@@ def _is_path_param(key: str, value: Any) -> bool:
+    # Inline data (CSV, TSV, multi-line text) always contains newlines — never a path.
+    if "\n" in val or "\r" in val:
+        return False
@@ def _generate_executor_config(...):
-            "        cliPath = '/usr/local/bin/aws'",
+            # launch template installs AWS CLI v2 to /opt/aws-cli/bin/aws; mounting its
+            # grandparent does NOT shadow /usr/local/bin, so python3 survives in all containers
+            "        cliPath = '/opt/aws-cli/bin/aws'",
```

An execution-path repair with a detailed rationale — the kind of autofix competence the live
verify-fix loop cannot cheaply manufacture.
