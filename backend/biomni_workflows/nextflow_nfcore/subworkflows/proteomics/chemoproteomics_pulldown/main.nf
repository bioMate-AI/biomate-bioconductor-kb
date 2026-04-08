#!/usr/bin/env nextflow
/*
 * proteomics/chemoproteomics_pulldown
 * Chemoproteomics affinity enrichment (pulldown) QC.
 *
 * Accepts a MaxQuant proteinGroups.txt (or equivalent CSV) from a
 * bead-pulldown experiment (ABPP, drug bead, BioID, etc.) and computes
 * per-protein enrichment ratios (pulldown intensity / input/control intensity).
 *
 * Outputs:
 *   enrichment_ratios.tsv   — per-protein table: protein_id, prey_intensity,
 *                             input_intensity, enrichment_ratio, log2_enrichment
 *   pulldown_summary.json   — aggregate QC metrics for the gate monitor
 *
 * Quality gate (qc_trace_monitor.py):
 *   median_enrichment_ratio < 3× → SILVER blocking (failed/non-specific pulldown)
 *   Golbraikh & Tropsha 2002; community ABPP practice (Cravatt lab).
 *
 * Input CSV/TSV columns expected (case-insensitive, any delimiter):
 *   protein_id, prey_intensity (or pulldown_intensity), input_intensity (or control_intensity)
 *   OR: MaxQuant proteinGroups.txt with "LFQ intensity <sample>" columns
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.input_file         = null             // Path to proteinGroups.txt or CSV
params.pulldown_sample    = null             // Sample name for pulldown column (MaxQuant)
params.control_sample     = null             // Sample name for control/input column (MaxQuant)
params.min_ratio          = 3.0             // Enrichment ratio gate threshold
params.min_proteins       = 50             // Minimum proteins for valid pulldown

process CHEMOPROTEOMICS_PULLDOWN {
    tag "pulldown_qc"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    path input_file

    output:
    path "enrichment_ratios.tsv",   emit: enrichment_table
    path "pulldown_summary.json",   emit: summary
    path "pulldown_report.txt",     emit: report
    path "versions.yml",            emit: versions

    script:
    """
    #!/usr/bin/env python3
    import json
    import csv
    import math
    import sys
    import os

    input_path    = "${input_file}"
    pulldown_col  = "${params.pulldown_sample}" or None
    control_col   = "${params.control_sample}" or None
    min_ratio     = float("${params.min_ratio}")
    min_proteins  = int("${params.min_proteins}")

    # ── 1. Auto-detect delimiter ──────────────────────────────────────────────
    with open(input_path, newline="", errors="replace") as f:
        sample = f.read(4096)
    delim = "\\t" if sample.count("\\t") > sample.count(",") else ","

    # ── 2. Load rows ──────────────────────────────────────────────────────────
    proteins = []
    with open(input_path, newline="", errors="replace") as f:
        reader = csv.DictReader(f, delimiter=delim)
        headers = reader.fieldnames or []

        # Normalise header names (lower, strip)
        h_lower = {h.lower().strip(): h for h in headers}

        # Find protein_id column
        id_col = next((h_lower[k] for k in ("protein id", "protein_id", "id", "majority protein ids",
                                              "gene names", "protein names") if k in h_lower), None)
        if id_col is None and headers:
            id_col = headers[0]

        # Find intensity columns
        def _find_col(candidates):
            for k in candidates:
                if k in h_lower:
                    return h_lower[k]
            return None

        # Try explicit pulldown / input columns
        prey_col = _find_col(["prey_intensity", "pulldown_intensity", "enriched_intensity",
                               "lfq intensity pulldown", "lfq intensity bead",
                               f"lfq intensity {pulldown_col}".lower() if pulldown_col else ""])
        ctrl_col = _find_col(["input_intensity", "control_intensity", "reference_intensity",
                               "lfq intensity input", "lfq intensity control",
                               f"lfq intensity {control_col}".lower() if control_col else ""])

        # MaxQuant: fall back to first two LFQ intensity columns in order
        if prey_col is None or ctrl_col is None:
            lfq_cols = [h for h in headers if "lfq intensity" in h.lower()]
            if len(lfq_cols) >= 2 and prey_col is None:
                prey_col = lfq_cols[0]
            if len(lfq_cols) >= 2 and ctrl_col is None:
                ctrl_col = lfq_cols[1]

        if prey_col is None or ctrl_col is None:
            print(f"ERROR: Cannot find pulldown/control intensity columns in {headers}",
                  file=sys.stderr)
            sys.exit(1)

        for row in reader:
            # Skip reverse/contaminant proteins (MaxQuant convention)
            if row.get("Reverse", "").strip() == "+":
                continue
            if row.get("Potential contaminant", "").strip() == "+":
                continue
            try:
                prey = float(row[prey_col] or 0)
                ctrl = float(row[ctrl_col] or 0)
                pid  = row.get(id_col, f"prot_{len(proteins)}").strip()
            except (ValueError, KeyError):
                continue
            proteins.append({"id": pid, "prey": prey, "ctrl": ctrl})

    n_proteins = len(proteins)
    print(f"Loaded {n_proteins} proteins | pulldown: {prey_col} | control: {ctrl_col}",
          file=sys.stderr)

    if n_proteins == 0:
        summary = {"success": False, "error": "No valid protein rows found", "n_proteins": 0}
        with open("pulldown_summary.json", "w") as f:
            json.dump(summary, f, indent=2)
        with open("enrichment_ratios.tsv", "w") as f:
            f.write("protein_id\\tprey_intensity\\tinput_intensity\\tenrichment_ratio\\tlog2_enrichment\\n")
        with open("pulldown_report.txt", "w") as f:
            f.write("ERROR: No valid protein rows found.\\n")
        sys.exit(1)

    # ── 3. Compute enrichment ratios ─────────────────────────────────────────
    PSEUDO = 1.0  # pseudocount to avoid division by zero
    rows_out = []
    for p in proteins:
        ratio = (p["prey"] + PSEUDO) / (p["ctrl"] + PSEUDO)
        log2  = math.log2(ratio) if ratio > 0 else 0.0
        rows_out.append({
            "protein_id":        p["id"],
            "prey_intensity":    round(p["prey"], 2),
            "input_intensity":   round(p["ctrl"], 2),
            "enrichment_ratio":  round(ratio, 4),
            "log2_enrichment":   round(log2, 4),
        })

    ratios = [r["enrichment_ratio"] for r in rows_out]
    ratios_sorted = sorted(ratios)
    n = len(ratios_sorted)
    median_ratio = ratios_sorted[n // 2] if n % 2 else (ratios_sorted[n//2-1] + ratios_sorted[n//2]) / 2

    # Count "enriched" proteins: ratio > 2× (common ABPP hit threshold)
    n_enriched = sum(1 for r in ratios if r > 2.0)

    # ── 4. Write outputs ──────────────────────────────────────────────────────
    with open("enrichment_ratios.tsv", "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=rows_out[0].keys(), delimiter="\\t")
        writer.writeheader()
        writer.writerows(rows_out)

    summary = {
        "success": True,
        "n_proteins": n_proteins,
        "n_enriched_2x": n_enriched,
        "median_enrichment_ratio": round(median_ratio, 4),
        "pulldown_column": prey_col,
        "control_column": ctrl_col,
        "gate_threshold": min_ratio,
    }

    with open("pulldown_summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    gate_status = "PASS" if median_ratio >= min_ratio else f"FAIL (< {min_ratio}× threshold)"
    with open("pulldown_report.txt", "w") as f:
        f.write("Chemoproteomics Pulldown QC Report\\n")
        f.write("=" * 40 + "\\n")
        f.write(f"Input file      : {input_path}\\n")
        f.write(f"Pulldown column : {prey_col}\\n")
        f.write(f"Control column  : {ctrl_col}\\n")
        f.write(f"Proteins loaded : {n_proteins}\\n")
        f.write(f"Enriched (>2×)  : {n_enriched} ({n_enriched/n_proteins*100:.1f}%)\\n")
        f.write(f"Median ratio    : {median_ratio:.2f}×\\n")
        f.write(f"QC gate (>{min_ratio}×): {gate_status}\\n")

    print(f"✓ Pulldown QC: median enrichment {median_ratio:.2f}× ({n_enriched}/{n_proteins} enriched)",
          file=sys.stderr)
    """
}

workflow CHEMOPROTEOMICS_PULLDOWN_WORKFLOW {
    take:
    ch_input  // channel: path(input_file)

    main:
    CHEMOPROTEOMICS_PULLDOWN(ch_input)

    emit:
    enrichment_table = CHEMOPROTEOMICS_PULLDOWN.out.enrichment_table
    summary          = CHEMOPROTEOMICS_PULLDOWN.out.summary
    report           = CHEMOPROTEOMICS_PULLDOWN.out.report
    versions         = CHEMOPROTEOMICS_PULLDOWN.out.versions
}

workflow {
    if (!params.input_file) {
        error "Please provide --input_file <path to proteinGroups.txt or CSV>"
    }
    ch_input = Channel.fromPath(params.input_file)
    CHEMOPROTEOMICS_PULLDOWN_WORKFLOW(ch_input)
    CHEMOPROTEOMICS_PULLDOWN_WORKFLOW.out.summary.view { "Summary: $it" }
}
