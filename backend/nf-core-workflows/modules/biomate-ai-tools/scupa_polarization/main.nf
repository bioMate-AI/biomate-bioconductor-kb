#!/usr/bin/env nextflow
/*
 * immuno_oncology/scupa_polarization  (BLOCKED — license clarification pending)
 *
 *   Scupa is an R package for immune cell polarization scoring.
 *   Repo: github.com/bsml320/Scupa
 *   License: NOASSERTION — cannot integrate until Zhao lab adds a permissive
 *            license (MIT or Apache-2.0) or grants explicit integration terms.
 *
 * This .nf intentionally fails fast with a clear message so that:
 *   1. The ZZ01 chain can be dispatched and the failure is informative,
 *      not silent.
 *   2. Engineers can track when this becomes unblocked by replacing
 *      the process body below with the real Scupa wrap.
 *
 * When unblocked:
 *   Replace SCUPA_BLOCKED with a real SCUPA_POLARIZE process that:
 *     - Accepts reactive_cells.h5ad from turep Phase C
 *     - Calls Scupa's R API to score Tex/Tem/Trm polarization states
 *     - Emits polarization_scores.tsv + polarized_cells.h5ad
 *     - Feeds ImmuneApp (Step 3) with the polarization metadata
 *
 * Contact: research@biomate.ai → forward to Zhao lab for license ask.
 */
nextflow.enable.dsl = 2

params.outdir              = './results'
params.reactive_cells_h5ad = 'null'   // output from turep Phase C

// [Phase A] License gate — fail fast with informative error
process SCUPA_BLOCKED {
    tag "scupa:license_blocked"
    label 'process_low'
    publishDir "${params.outdir}/scupa_blocked", mode: 'copy'

    input:  val(meta)
    output: path("scupa_blocked.json"), emit: out

    script:
    """
    python3 - <<'PY'
    import json, sys
    msg = {
        "status": "BLOCKED",
        "reason": "Scupa (github.com/bsml320/Scupa) has NOASSERTION license. "
                  "BioMate cannot integrate this tool until the Zhao lab adds a "
                  "permissive open-source license (MIT or Apache-2.0) or grants "
                  "explicit integration terms in writing.",
        "unblock_action": "Email Zhao lab (UTHealth, bsml320 org) requesting MIT license on bsml320/Scupa.",
        "workaround": "turep output (reactive_cells.h5ad) can bypass Scupa and feed "
                      "directly to immuneapp_hla_screen for neoantigen ranking.",
        "tool": "Scupa",
        "repo": "github.com/bsml320/Scupa",
        "license": "NOASSERTION",
        "biomate_ticket": "ZZ01-scupa-license-block",
    }
    json.dump(msg, open("scupa_blocked.json", "w"), indent=2)
    print("[scupa_polarization] BLOCKED — see scupa_blocked.json for details", file=sys.stderr)
    sys.exit(1)
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'scupa_polarization'])
    SCUPA_BLOCKED(meta_ch)
}
