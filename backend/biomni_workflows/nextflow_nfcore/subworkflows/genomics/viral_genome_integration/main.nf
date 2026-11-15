#!/usr/bin/env nextflow
/*
 * genomics/viral_genome_integration
 *
 * Tumor-associated (oncovirus) genome characterisation from tumor or plasma
 * sequencing reads. Three outputs:
 *   (a) virus-host INTEGRATION BREAKPOINTS   — where the viral genome has
 *       inserted into the host genome, clustered from host-virus CHIMERIC
 *       (split / discordant) reads, with host gene context.
 *   (b) VIRAL LOAD / copy number             — a viral-genome copies-per-tumor-
 *       cell estimate from the viral-vs-host mapped-read ratio.
 *   (c) SUBTYPE / STRAIN CALL                — which viral strain, from where the
 *       viral side of the chimeric reads maps within a per-strain reference.
 *
 * GENERAL over any configurable oncovirus (params.virus): HPV, HBV, EBV, MCPyV.
 * EBV type-1 / type-2 is the BUILT-IN DEMO.
 *
 * RUNS WITH NO USER INPUT: the DEMO path uses a small built-in synthetic dataset
 * (params.chimeric_reads) — a JSON list of host-virus chimeric read records, each
 * giving host_chrom, host_pos, viral_pos and support_count. That is enough to
 * call integration sites (support-clustered, min-support filtered) and a subtype
 * (from which per-strain marker window the viral_pos falls in). Viral load uses
 * the demo read-count params below. NO real reads / references are needed.
 *
 * REAL path (optional): supply params.reads (a BAM of reads already aligned to a
 * COMBINED host+virus reference). Then the first process runs `samtools idxstats`
 * to split mapped reads into host vs viral contigs for the copy-number estimate.
 * params.viral_ref / params.host_ref are accepted as metadata for a full de-novo
 * aligner path (bwa-mem + split-read extraction) which a production upstream step
 * would run to POPULATE params.chimeric_reads; chimeric-junction extraction from
 * raw reads needs an aligner and is NOT done here — the demo path never touches
 * samtools and never needs an aligner.
 *
 * ------------------------------------------------------------------------------
 * MODELS / ASSUMPTIONS (scientifically honest):
 *
 * INTEGRATION SITES: chimeric reads whose host side maps within params.cluster_window
 *   bp on the same host chromosome are pooled into one candidate integration
 *   locus; the locus is CALLED when its pooled support_count >= params.min_support.
 *   Representative host_pos / viral_pos are support-weighted means. gene_context is
 *   a lookup against a SMALL illustrative set of recurrent oncovirus integration
 *   loci (approximate hg38 coordinates for TERT, MYC, CCND1) — a production run
 *   supplies a full GTF via params.host_genes; "intergenic" when no gene overlaps.
 *
 * VIRAL LOAD (copies per tumor cell), from the viral-vs-host read-depth ratio:
 *   copies_per_cell = (viral_reads / viral_genome_len)
 *                     / (host_reads / host_haploid_len) * tumor_ploidy
 *   Read length cancels (depth = reads*len/genome_len on both sides). This assumes
 *   uniform coverage, pure tumor content, and no episomal-vs-integrated separation
 *   — it is a transparent estimate, NOT a validated clinical viral-load assay. When
 *   read counts are unavailable the estimate is null and a relative viral_load_proxy
 *   (total chimeric support) is reported instead.
 *
 * SUBTYPE / STRAIN: each chimeric read's viral_pos is matched to a per-strain
 *   marker window (params.subtype_markers, else a built-in map keyed by virus);
 *   support_count votes for that strain; the strain with the most votes is called
 *   when its votes >= params.min_support, else "undetermined". For EBV the windows
 *   are the EBNA2 type-1 vs type-2 allele regions within one EBV reference; for
 *   multi-type viruses (HPV / HBV) they are the per-type segments of a concatenated
 *   multi-strain reference. Coordinates are ILLUSTRATIVE — a definitive subtype
 *   call needs viral consensus assembly + phylogenetic placement, which this
 *   lightweight marker heuristic does not perform (stated, not hidden).
 *
 * Outputs: integration_sites.csv (host_chrom, host_pos, viral_pos, support,
 * gene_context), viral_summary.json (load estimate, subtype call, n integration
 * sites + model assumptions), summary.json, qc_metrics.json. The final SUMMARISE
 * process LOUD-FAILS (raise SystemExit) if no chimeric reads were processed, i.e.
 * no output was produced.
 *
 * Container: a bioconda-based image with samtools + python3 (STDLIB ONLY is used
 * here — json/csv/math/statistics; no pandas/numpy). Image = biomate/cfdna (same
 * image as genomics/ebv_cfdna_mrd; build recipe in the DB-spec annotation:
 * micromamba python3.11 + samtools from bioconda; a public pullable equivalent for
 * the samtools-count step is quay.io/biocontainers/samtools). ECR mirror on AWS.
 */

nextflow.enable.dsl = 2

// Note: do NOT add `import groovy.json.JsonSlurper` here — unused and rejected as a
// script compile error on some Batch Nextflow heads (same class as antibody_antigen_complex).

// ---- Demo defaults so the workflow runs with NO inputs --------------------
// Synthetic oncovirus (EBV) chimeric-read dataset (illustrative, NOT patient
// data). Two support-clustered integration loci clear min_support (near TERT and
// MYC); one low-support locus (near CCND1) is filtered. All viral_pos land in the
// EBV type-1 (EBNA2 type-1 allele) marker window -> subtype call EBV-1.
params.chimeric_reads = '[{"host_chrom":"chr5","host_pos":1260000,"viral_pos":48500,"support_count":7},{"host_chrom":"chr5","host_pos":1260180,"viral_pos":48650,"support_count":5},{"host_chrom":"chr8","host_pos":127739800,"viral_pos":48800,"support_count":3},{"host_chrom":"chr8","host_pos":127740000,"viral_pos":49050,"support_count":4},{"host_chrom":"chr11","host_pos":69645000,"viral_pos":49300,"support_count":2}]'

// Optional real inputs (demo does not need them).
params.reads     = ''   // BAM aligned to a COMBINED host+virus reference
params.viral_ref = ''   // viral (multi-strain) reference FASTA — metadata for de-novo path
params.host_ref  = ''   // host reference FASTA — metadata for de-novo path

// Virus + calling parameters.
params.virus         = 'EBV'   // EBV | HPV | HBV | MCPyV (configurable)
params.min_support   = '3'     // min pooled chimeric support to call a site / strain
params.cluster_window = '500'  // bp window to pool chimeric reads into one locus

// Viral-load read counts (demo values; on the real path viral/host read counts
// come from samtools idxstats over the combined-reference BAM).
params.viral_reads      = '15000'        // reads mapping to viral contig(s)
params.host_reads       = '30000000'     // reads mapping to host contig(s)
params.viral_genome_len = '0'            // 0 -> look up by virus (EBV 171823, ...)
params.host_haploid_len = '3100000000'   // ~3.1 Gb haploid human genome
params.tumor_ploidy     = '2'            // host haploid genomes per cell

// Optional JSON overrides (empty -> built-in maps).
params.subtype_markers = ''    // {"EBV":[{"subtype":..,"start":..,"end":..,"locus":..}], ...}
params.host_genes      = ''    // {"chr8":[{"gene":"MYC","start":..,"end":..}], ...}

params.outdir = 'results'

process PREP_INPUTS {
    tag "viral_genome_integration"
    label 'process_low'
    publishDir { "${params.outdir}/viral_genome_integration" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cfdna:x86' : 'biomate/cfdna:latest'

    input:
    tuple val(reads), val(viral_ref), val(host_ref), val(chimeric_json)

    output:
    path "prep.json",    emit: prep
    path "versions.yml", emit: versions

    script:
    """
    export READS='${reads}'
    export VIRAL_REF='${viral_ref}'
    export HOST_REF='${host_ref}'
    export VIRUS='${params.virus}'
    export MIN_SUPPORT='${params.min_support}'
    export CLUSTER_WINDOW='${params.cluster_window}'
    export VIRAL_READS='${params.viral_reads}'
    export HOST_READS='${params.host_reads}'
    export VIRAL_GENOME_LEN='${params.viral_genome_len}'
    export HOST_HAPLOID_LEN='${params.host_haploid_len}'
    export TUMOR_PLOIDY='${params.tumor_ploidy}'
    export CHIMERIC_JSON='${chimeric_json}'

    HAVE_READS=0
    if [ -n "\$READS" ] && [ -f "\$READS" ]; then
        HAVE_READS=1
        samtools index "\$READS" 2>/dev/null || true
        samtools idxstats "\$READS" > idxstats.txt 2>/dev/null || true
    fi
    export HAVE_READS

    python3 << 'PYEOF'
import os, json, sys

virus = (os.environ.get("VIRUS", "EBV") or "EBV").strip()
have_reads = os.environ.get("HAVE_READS", "0") == "1"

def as_int(v, d):
    try:
        return int(float(v))
    except Exception:
        return d

def as_float(v, d):
    try:
        return float(v)
    except Exception:
        return d

min_support = as_int(os.environ.get("MIN_SUPPORT"), 3)
cluster_window = as_int(os.environ.get("CLUSTER_WINDOW"), 500)
host_haploid_len = as_float(os.environ.get("HOST_HAPLOID_LEN"), 3.1e9)
tumor_ploidy = as_float(os.environ.get("TUMOR_PLOIDY"), 2.0)

# Default viral genome lengths (bp) for the copy-number denominator.
VIRAL_GENOME_LEN = {"EBV": 171823, "HPV": 7906, "HBV": 3215, "MCPYV": 5387}
vlen = as_int(os.environ.get("VIRAL_GENOME_LEN"), 0)
if vlen <= 0:
    vlen = VIRAL_GENOME_LEN.get(virus.upper(), 171823)

# Chimeric read records (populated upstream by the aligner on the real path;
# supplied directly in the demo).
try:
    chimeric = json.loads(os.environ.get("CHIMERIC_JSON") or "[]")
except Exception as e:
    sys.exit("FATAL: could not parse params.chimeric_reads JSON: %s" % e)
if not isinstance(chimeric, list):
    sys.exit("FATAL: params.chimeric_reads must be a JSON list of records")

# Host vs viral mapped read counts for the viral-load estimate.
if have_reads:
    # samtools idxstats: refname  reflen  mapped  unmapped (whitespace separated).
    host_names = set()
    for i in range(1, 23):
        host_names.add("chr%d" % i)
        host_names.add("%d" % i)
    for c in ("X", "Y", "M", "MT"):
        host_names.add("chr%s" % c)
        host_names.add(c)
    viral_reads = 0
    host_reads = 0
    try:
        for line in open("idxstats.txt"):
            parts = line.split()
            if len(parts) < 3:
                continue
            name, mapped = parts[0], as_int(parts[2], 0)
            if name == "*":
                continue
            if name in host_names:
                host_reads += mapped
            else:
                viral_reads += mapped
    except Exception as e:
        sys.exit("FATAL: could not parse samtools idxstats output: %s" % e)
    read_source = "bam_idxstats"
else:
    viral_reads = as_int(os.environ.get("VIRAL_READS"), 0)
    host_reads = as_int(os.environ.get("HOST_READS"), 0)
    read_source = "demo_params"

prep = {
    "virus": virus,
    "min_support": min_support,
    "cluster_window": cluster_window,
    "chimeric_reads": chimeric,
    "n_chimeric_reads": len(chimeric),
    "viral_reads": viral_reads,
    "host_reads": host_reads,
    "viral_genome_len": vlen,
    "host_haploid_len": host_haploid_len,
    "tumor_ploidy": tumor_ploidy,
    "read_source": read_source,
    "input_source": "bam" if have_reads else "demo_json",
}
with open("prep.json", "w") as fh:
    json.dump(prep, fh, indent=2)
print("prepared %d chimeric record(s) for virus=%s; read_source=%s" % (len(chimeric), virus, read_source))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        samtools: \$(samtools --version 2>/dev/null | head -1 | cut -d' ' -f2 || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
    END_VERSIONS
    """
}

process CALL_INTEGRATION {
    tag "viral_genome_integration"
    label 'process_low'
    publishDir { "${params.outdir}/viral_genome_integration" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cfdna:x86' : 'biomate/cfdna:latest'

    input:
    path "prep.json"

    output:
    path "integration_sites.csv", emit: sites
    path "viral_summary.json",    emit: summary

    script:
    """
    export SUBTYPE_MARKERS_JSON='${params.subtype_markers}'
    export HOST_GENES_JSON='${params.host_genes}'

    python3 << 'PYEOF'
import os, json, csv, sys

try:
    prep = json.load(open("prep.json"))
except Exception as e:
    sys.exit("FATAL: cannot read prep.json: %s" % e)

virus = prep.get("virus", "EBV")
min_support = int(prep.get("min_support", 3) or 3)
cluster_window = int(prep.get("cluster_window", 500) or 500)
chimeric = prep.get("chimeric_reads") or []

# ---- Per-strain marker windows (built-in; override via params.subtype_markers)
# Coordinates are ILLUSTRATIVE. EBV type-1/2 = EBNA2 allele region within one EBV
# reference; HPV/HBV windows = per-type segments of a concatenated multi-strain ref.
BUILTIN_MARKERS = {
    "EBV": [
        {"subtype": "EBV-1 (type 1)", "start": 48000, "end": 50000, "locus": "EBNA2 type-1 allele"},
        {"subtype": "EBV-2 (type 2)", "start": 50000, "end": 52000, "locus": "EBNA2 type-2 allele"},
    ],
    "HPV": [
        {"subtype": "HPV16", "start": 0, "end": 7906, "locus": "HPV16 segment"},
        {"subtype": "HPV18", "start": 7906, "end": 15681, "locus": "HPV18 segment"},
        {"subtype": "HPV31", "start": 15681, "end": 23593, "locus": "HPV31 segment"},
    ],
    "HBV": [
        {"subtype": "HBV-A", "start": 0, "end": 3221, "locus": "HBV genotype A segment"},
        {"subtype": "HBV-B", "start": 3221, "end": 6436, "locus": "HBV genotype B segment"},
        {"subtype": "HBV-C", "start": 6436, "end": 9651, "locus": "HBV genotype C segment"},
        {"subtype": "HBV-D", "start": 9651, "end": 12833, "locus": "HBV genotype D segment"},
    ],
    "MCPYV": [
        {"subtype": "MCPyV", "start": 0, "end": 5387, "locus": "MCPyV reference"},
    ],
}
markers_override = os.environ.get("SUBTYPE_MARKERS_JSON", "") or ""
if markers_override.strip():
    try:
        markers_map = json.loads(markers_override)
    except Exception as e:
        sys.exit("FATAL: could not parse params.subtype_markers JSON: %s" % e)
else:
    markers_map = BUILTIN_MARKERS
markers = markers_map.get(virus) or markers_map.get(virus.upper()) or []

# ---- Host gene annotation (built-in illustrative subset; override via params.host_genes)
# Approximate hg38 coordinates for recurrent oncovirus integration loci. A
# production run supplies a full GTF; "intergenic" when nothing overlaps.
BUILTIN_GENES = {
    "chr5":  [{"gene": "TERT",  "start": 1253167,   "end": 1295162}],
    "chr8":  [{"gene": "MYC",   "start": 127735434, "end": 127742951}],
    "chr11": [{"gene": "CCND1", "start": 69641156,  "end": 69654474}],
}
genes_override = os.environ.get("HOST_GENES_JSON", "") or ""
if genes_override.strip():
    try:
        host_genes = json.loads(genes_override)
    except Exception as e:
        sys.exit("FATAL: could not parse params.host_genes JSON: %s" % e)
    gene_source = "user_gtf"
else:
    host_genes = BUILTIN_GENES
    gene_source = "builtin_illustrative"

def gene_context(chrom, pos):
    for g in host_genes.get(chrom, []):
        try:
            if int(g["start"]) <= pos <= int(g["end"]):
                return g.get("gene", "gene")
        except Exception:
            continue
    return "intergenic"

def num(v, d=0.0):
    try:
        return float(v)
    except Exception:
        return d

# ---- Cluster chimeric reads into candidate integration loci -----------------
recs = []
for r in chimeric:
    try:
        recs.append({
            "host_chrom": str(r.get("host_chrom", "")).strip(),
            "host_pos": int(num(r.get("host_pos"))),
            "viral_pos": int(num(r.get("viral_pos"))),
            "support": int(num(r.get("support_count"))),
        })
    except Exception:
        continue
recs = [r for r in recs if r["host_chrom"] and r["support"] > 0]
recs.sort(key=lambda r: (r["host_chrom"], r["host_pos"]))

clusters = []
cur = None
for r in recs:
    if cur is not None and r["host_chrom"] == cur["host_chrom"] and (r["host_pos"] - cur["last_pos"]) <= cluster_window:
        cur["members"].append(r)
        cur["last_pos"] = r["host_pos"]
    else:
        cur = {"host_chrom": r["host_chrom"], "last_pos": r["host_pos"], "members": [r]}
        clusters.append(cur)

called_sites = []
all_loci = []
for c in clusters:
    members = c["members"]
    tot = sum(m["support"] for m in members)
    if tot <= 0:
        continue
    hp = int(round(sum(m["host_pos"] * m["support"] for m in members) / tot))
    vp = int(round(sum(m["viral_pos"] * m["support"] for m in members) / tot))
    ctx = gene_context(c["host_chrom"], hp)
    locus = {
        "host_chrom": c["host_chrom"],
        "host_pos": hp,
        "viral_pos": vp,
        "support": tot,
        "gene_context": ctx,
        "n_reads": len(members),
        "called": tot >= min_support,
    }
    all_loci.append(locus)
    if locus["called"]:
        called_sites.append(locus)

# ---- Subtype / strain call (support-weighted votes over marker windows) -----
votes = {}
for r in recs:
    vp = r["viral_pos"]
    for m in markers:
        try:
            if int(m["start"]) <= vp < int(m["end"]):
                votes[m["subtype"]] = votes.get(m["subtype"], 0) + r["support"]
                break
        except Exception:
            continue
if votes:
    best = max(votes.items(), key=lambda kv: kv[1])
    subtype_call = best[0] if best[1] >= min_support else "undetermined"
    subtype_support = best[1]
else:
    subtype_call = "undetermined"
    subtype_support = 0

# ---- Viral load / copy number ----------------------------------------------
viral_reads = num(prep.get("viral_reads"))
host_reads = num(prep.get("host_reads"))
vlen = num(prep.get("viral_genome_len"))
hlen = num(prep.get("host_haploid_len"))
ploidy = num(prep.get("tumor_ploidy"), 2.0)
if viral_reads > 0 and host_reads > 0 and vlen > 0 and hlen > 0:
    copies_per_cell = (viral_reads / vlen) / (host_reads / hlen) * ploidy
    copies_per_cell = round(copies_per_cell, 3)
    load_source = prep.get("read_source", "read_counts")
else:
    copies_per_cell = None
    load_source = "unavailable"
viral_load_proxy = sum(r["support"] for r in recs)

# ---- Write integration_sites.csv (called sites only) ------------------------
cols = ["host_chrom", "host_pos", "viral_pos", "support", "gene_context"]
with open("integration_sites.csv", "w", newline="") as fh:
    w = csv.DictWriter(fh, fieldnames=cols)
    w.writeheader()
    for s in called_sites:
        w.writerow({k: s.get(k) for k in cols})

summary = {
    "virus": virus,
    "subtype_call": subtype_call,
    "subtype_support": subtype_support,
    "subtype_votes": votes,
    "n_integration_sites": len(called_sites),
    "n_candidate_loci": len(all_loci),
    "min_support": min_support,
    "cluster_window_bp": cluster_window,
    "n_chimeric_reads": len(recs),
    "integration_sites": called_sites,
    "candidate_loci": all_loci,
    "estimated_copies_per_cell": copies_per_cell,
    "viral_load_source": load_source,
    "viral_load_proxy_total_support": viral_load_proxy,
    "viral_reads": viral_reads,
    "host_reads": host_reads,
    "viral_genome_len": vlen,
    "gene_annotation_source": gene_source,
    "model_assumptions": [
        "Integration loci: chimeric reads within cluster_window bp on the same host chromosome are pooled; a locus is CALLED when pooled support >= min_support.",
        "Representative host_pos/viral_pos are support-weighted means of the pooled chimeric reads.",
        "gene_context is a lookup against host_genes (built-in illustrative subset: TERT/MYC/CCND1 approximate hg38 coords; supply a full GTF via params.host_genes); 'intergenic' when nothing overlaps.",
        "Viral load copies_per_cell = (viral_reads/viral_genome_len) / (host_reads/host_haploid_len) * tumor_ploidy; read length cancels. Assumes uniform coverage, pure tumor, no episomal/integrated separation. Not a validated clinical viral-load assay.",
        "Subtype: support-weighted votes by which per-strain marker window each viral_pos falls in; called when top votes >= min_support, else undetermined. Marker coordinates are illustrative; a definitive call needs viral consensus assembly + phylogenetic placement.",
    ],
    "status": "ok",
}
with open("viral_summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps({"virus": virus, "subtype_call": subtype_call,
                  "n_integration_sites": len(called_sites),
                  "estimated_copies_per_cell": copies_per_cell}, indent=2))
PYEOF
    """
}

process SUMMARISE {
    tag "viral_genome_integration"
    label 'process_low'
    publishDir { "${params.outdir}/viral_genome_integration" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cfdna:x86' : 'biomate/cfdna:latest'

    input:
    path "viral_summary.json"
    path "integration_sites.csv"

    output:
    path "summary.json",    emit: summary
    path "qc_metrics.json", emit: qc

    script:
    """
    python3 << 'PYEOF'
import json, csv

try:
    rep = json.load(open("viral_summary.json"))
except Exception as e:
    raise SystemExit("FATAL: cannot read viral_summary.json: %s" % e)

n_chimeric = int(rep.get("n_chimeric_reads", 0) or 0)
if n_chimeric <= 0:
    raise SystemExit("FATAL: no chimeric reads were processed; no viral-integration output was produced.")

try:
    with open("integration_sites.csv") as fh:
        rows = list(csv.DictReader(fh))
except Exception as e:
    raise SystemExit("FATAL: cannot read integration_sites.csv: %s" % e)

sites = rep.get("integration_sites") or []
supports = [int(float(s.get("support", 0) or 0)) for s in sites]
genes_hit = sorted({s.get("gene_context") for s in sites if s.get("gene_context") and s.get("gene_context") != "intergenic"})

warnings = []
if rep.get("subtype_call") in (None, "undetermined"):
    warnings.append("subtype undetermined: no marker window reached min_support (strain unresolved)")
if rep.get("estimated_copies_per_cell") is None:
    warnings.append("viral load copies/cell unavailable (no viral/host read counts); only a relative support proxy is reported")
if rep.get("gene_annotation_source") == "builtin_illustrative":
    warnings.append("gene_context from the built-in illustrative loci subset (TERT/MYC/CCND1); supply a full GTF via params.host_genes for complete annotation")
if n_chimeric < 3:
    warnings.append("very few chimeric reads (%d); integration/subtype calls are low-confidence" % n_chimeric)
if len(sites) == 0:
    warnings.append("no integration locus cleared min_support; reported subtype/load only")

summary = {
    "virus": rep.get("virus"),
    "subtype_call": rep.get("subtype_call"),
    "n_integration_sites": rep.get("n_integration_sites"),
    "n_candidate_loci": rep.get("n_candidate_loci"),
    "estimated_copies_per_cell": rep.get("estimated_copies_per_cell"),
    "viral_load_source": rep.get("viral_load_source"),
    "viral_load_proxy_total_support": rep.get("viral_load_proxy_total_support"),
    "genes_with_integration": genes_hit,
    "n_chimeric_reads": n_chimeric,
    "status": "ok",
    "note": "Oncovirus genome characterisation: virus-host integration sites (chimeric-read clustered), viral load copies/cell (viral-vs-host read-depth ratio), and subtype call (per-strain marker voting). Estimates only — not a validated clinical result.",
}
with open("summary.json", "w") as fh:
    json.dump(summary, fh, indent=2)

qc = {
    "virus": rep.get("virus"),
    "n_chimeric_reads": n_chimeric,
    "n_candidate_loci": rep.get("n_candidate_loci"),
    "n_integration_sites": rep.get("n_integration_sites"),
    "max_site_support": max(supports) if supports else 0,
    "min_support_threshold": rep.get("min_support"),
    "subtype_call": rep.get("subtype_call"),
    "subtype_support": rep.get("subtype_support"),
    "estimated_copies_per_cell": rep.get("estimated_copies_per_cell"),
    "viral_load_source": rep.get("viral_load_source"),
    "gene_annotation_source": rep.get("gene_annotation_source"),
    "n_sites_in_csv": len(rows),
    "warnings": warnings,
    "status": "ok",
}
with open("qc_metrics.json", "w") as fh:
    json.dump(qc, fh, indent=2)

print(json.dumps({"virus": rep.get("virus"), "subtype_call": rep.get("subtype_call"),
                  "n_integration_sites": rep.get("n_integration_sites"),
                  "estimated_copies_per_cell": rep.get("estimated_copies_per_cell")}, indent=2))
PYEOF
    """
}

workflow VIRAL_GENOME_INTEGRATION {
    take:
    ch_input   // channel: tuple(reads, viral_ref, host_ref, chimeric_json)

    main:
    PREP_INPUTS(ch_input)
    CALL_INTEGRATION(PREP_INPUTS.out.prep)
    SUMMARISE(CALL_INTEGRATION.out.summary, CALL_INTEGRATION.out.sites)

    emit:
    prep     = PREP_INPUTS.out.prep
    sites    = CALL_INTEGRATION.out.sites
    report   = CALL_INTEGRATION.out.summary
    summary  = SUMMARISE.out.summary
    qc       = SUMMARISE.out.qc
    versions = PREP_INPUTS.out.versions
}

// Entry workflow for standalone execution.
workflow {
    ch_input = Channel.of(
        tuple(params.reads as String, params.viral_ref as String,
              params.host_ref as String, params.chimeric_reads as String)
    )

    VIRAL_GENOME_INTEGRATION(ch_input)

    VIRAL_GENOME_INTEGRATION.out.summary.view { f -> "viral genome integration done: ${f}" }
}
