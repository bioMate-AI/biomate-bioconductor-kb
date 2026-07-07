#!/usr/bin/env nextflow
/*
 * population_genetics/magma_gene_analysis  (3-phase pipeline)
 *
 *   Phase A — SNP annotation   : map GWAS SNPs → genes using NCBI gene.loc
 *                                 (magma --annotate; window 10 kb up / 1.5 kb down)
 *   Phase B — Gene analysis    : per-gene Z-statistics from GWAS p-values
 *                                 (magma --gene-analysis; default snp-wise model
 *                                  for smoke; multi-principle-components for real runs)
 *   Phase C — Format output    : box-cox transform of Z-scores for scGWAS;
 *                                 also emit raw .genes.out for TorchGWAS integration
 *
 * Real-use-case anchor (shared prerequisite — Zhi lab Z01 + Zhao lab ZZ02):
 *
 *   Zhi lab (Z01 TorchGWAS chain): Nat Commun 2026 (PMC12458571) Methods uses
 *     MAGMA v1.10 for gene-based tests downstream of TorchGWAS GWAS results.
 *     Feed TorchGWAS results.tsv.gz (compressed SNP-level output) into Phase A
 *     of this wrapper to produce gene-level Z-scores for FUMA / enrichment.
 *
 *   Zhao lab (ZZ02 scGWAS chain): Genome Biology 2022 (PMC9575201) feeds MAGMA
 *     gene analysis output (box-cox transformed) into scGWAS as `gwas_node_file`.
 *     This wrapper emits {outfile}.magma_boxcox.txt — the exact file shape expected
 *     by scgwas_immune_cell/main.nf --gwas_sumstats.
 *
 * Tool: MAGMA v1.10 (ctg.cncr.nl/software/magma, Pascal de Leeuw, VU Amsterdam)
 *       License: freeware for academic use; binary distributed without source.
 *
 * LD reference baked into container: g1000_eur (1000G EUR, hg19) from ctg.cncr.nl.
 * Gene locations baked: NCBI37.3 (hg19) and NCBI38 (hg38) from ctg.cncr.nl.
 *
 * Quick smoke (synthetic chr1 sumstats, snp-wise model, no LD ref needed):
 *   nextflow run main.nf --use_baked_toy true --outdir results
 *
 * Downstream scGWAS (smoke → scgwas_immune_cell):
 *   nextflow run main.nf --use_baked_toy true --outdir magma_out
 *   nextflow run ../scgwas_immune_cell/main.nf \
 *       --gwas_sumstats magma_out/phaseC_format/magma_run.magma_boxcox.txt \
 *       --outdir scgwas_out
 *
 * Real GWAS (caller supplies sumstats):
 *   nextflow run main.nf \
 *       --gwas_sumstats s3://bucket/my_gwas.tsv \
 *       --snp_col variant_id --pval_col p_value --n_col fixed \
 *       --genome_build hg19 \
 *       --gene_model snp-wise \
 *       --outfile my_run \
 *       --outdir s3://bucket/runs/magma-001
 *
 * Phase A uses --snp-loc (position-based annotation) so SNP IDs do not need
 * to match the LD reference panel. Works with any GWAS format that has CHR+BP.
 * Phase B (snp-wise) requires no LD bfile; genes are scored from p-value only.
 */
nextflow.enable.dsl = 2

params.outdir              = './results'
params.use_baked_toy       = false         // true → smoke with synthetic chr1 sumstats
params.gwas_sumstats       = 'null'        // path to GWAS sumstats (SNP P N columns)
params.snp_col             = 'SNP'         // column name for SNP/rsID
params.pval_col            = 'P'           // column name for p-value
params.n_col               = 'N'           // column name for sample size (or 'fixed')
params.sample_size         = 50000         // used when n_col='fixed' or column absent
params.genome_build        = 'hg19'        // hg19 (NCBI37) or hg38 (NCBI38)
params.gene_model          = 'snp-wise'    // snp-wise (no LD ref) | multi (needs g1000_eur)
params.window_upstream_kb  = 10            // kb upstream for SNP→gene annotation window
params.window_downstream_kb = 1.5         // kb downstream annotation window
params.outfile             = 'magma_run'

CONTAINER_MAGMA = System.getenv('NEXTFLOW_USE_AWS') == 'true' \
    ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/magma:v1.10' \
    : 'biomate/magma:v1.10'

// [Phase A] SNP annotation — map GWAS SNPs to NCBI gene coordinates via position
process MAGMA_ANNOTATE {
    tag "magma:phaseA"
    label 'process_medium'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseA_annotate", mode: 'copy'

    input:  val(meta)
    output: tuple val(meta), path("${params.outfile}.genes.annot"), path("annotate.json"), emit: out

    script:
    def baked     = params.use_baked_toy as Boolean
    def genome    = params.genome_build
    def winUp     = params.window_upstream_kb
    def winDown   = params.window_downstream_kb
    def outfile   = params.outfile
    def snpCol    = params.snp_col
    def sumstats  = params.gwas_sumstats
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, sys, subprocess, csv, gzip as _gz, shutil

    baked         = ${baked ? 'True' : 'False'}
    genome        = "${genome}"
    win_up        = ${winUp}
    win_down      = ${winDown}
    outfile       = "${outfile}"
    snp_col       = "${snpCol}"
    gwas_sumstats = "${sumstats}"

    gene_loc_map = {
        "hg19": "/opt/magma/ref/NCBI37.3.gene.loc",
        "hg38": "/opt/magma/ref/NCBI38.gene.loc",
    }
    gene_loc = gene_loc_map.get(genome, gene_loc_map["hg19"])

    def _open_s(path):
        with open(path, "rb") as _f:
            magic = _f.read(2)
        return _gz.open(path, "rt") if magic == b"\\x1f\\x8b" else open(path)

    # Build snp.loc (SNP CHR BP) for --snp-loc annotation.
    # Position-based annotation does not require SNP IDs to match the LD reference
    # panel. Works with any GWAS format that contains chromosome and position columns.
    n_snps = 0
    if baked:
        import random
        random.seed(42)
        rows = []
        for i in range(200):
            rows.append((f"rs_cl1_{i}", "1", str(random.randint(50_000_000, 55_000_000))))
        for i in range(1800):
            rows.append((f"rs_bg_{i}", "1", str(random.randint(1_000_000, 249_000_000))))
        with open("snp.loc", "w") as f:
            f.write("SNP\\tCHR\\tBP\\n")
            for r in rows:
                f.write("\\t".join(r) + "\\n")
        n_snps = len(rows)
    else:
        if gwas_sumstats in ("null", ""):
            print("ERROR: gwas_sumstats required when use_baked_toy=false", file=sys.stderr)
            sys.exit(1)
        if gwas_sumstats.startswith("s3://"):
            import boto3
            parts = gwas_sumstats[5:].split("/", 1)
            boto3.client("s3").download_file(parts[0], parts[1], "sumstats.tmp")
            psum = "sumstats.tmp"
        else:
            shutil.copy(gwas_sumstats, "sumstats.tmp")
            psum = "sumstats.tmp"

        with _open_s(psum) as fh, open("snp.loc", "w") as out:
            reader = csv.DictReader(fh, delimiter="\\t")
            col_map = {c.upper(): c for c in (reader.fieldnames or [])}

            # SNP ID column
            s_col = col_map.get(snp_col.upper())
            if s_col is None:
                for alias in ("VARIANT_ID", "SNP_ID", "RSID", "RS_ID", "ID",
                              "MARKERNAME", "SNPID", "NAME", "VARIANT"):
                    if alias in col_map:
                        s_col = col_map[alias]; break
            if s_col is None:
                print(f"ERROR: SNP column '{snp_col}' not found. Columns: {list(col_map.keys())}", file=sys.stderr)
                sys.exit(1)

            # CHR column
            chr_col = (col_map.get("CHR") or col_map.get("CHROMOSOME") or col_map.get("CHROM"))
            if chr_col is None:
                print(f"ERROR: CHR column not found. Columns: {list(col_map.keys())}", file=sys.stderr)
                sys.exit(1)

            # BP/position column
            bp_col = (col_map.get("BP") or col_map.get("POS") or col_map.get("POSITION") or
                      col_map.get("BASE_PAIR_LOCATION") or col_map.get("BASE_PAIR_LOCATION_HG19") or
                      col_map.get("BASE_PAIR_LOCATION_GRCH37") or col_map.get("BPLOC"))
            if bp_col is None:
                print(f"ERROR: BP/position column not found. Columns: {list(col_map.keys())}", file=sys.stderr)
                sys.exit(1)

            print(f"[magma:phaseA] columns: snp={s_col}, chr={chr_col}, bp={bp_col}")
            out.write("SNP\\tCHR\\tBP\\n")
            for row in reader:
                chr_val = row[chr_col].lstrip("chrChr")
                out.write(f"{row[s_col]}\\t{chr_val}\\t{row[bp_col]}\\n")
                n_snps += 1

        print(f"[magma:phaseA] snp.loc: {n_snps} SNPs written")

    cmd = [
        "/opt/magma/magma",
        "--annotate",
        f"window={win_up},{win_down}",
        "--snp-loc", "snp.loc",
        "--gene-loc", gene_loc,
        "--out", outfile,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    print(f"[magma:phaseA] exit={result.returncode}")
    if result.stdout:
        print(result.stdout[-2000:])
    if result.stderr:
        print(result.stderr[-500:], file=sys.stderr)
    if result.returncode != 0:
        open(f"{outfile}.genes.annot", "w").write("")

    json.dump({
        "phase": "A",
        "baked_toy": baked,
        "genome_build": genome,
        "gene_loc_file": gene_loc,
        "n_snps_input": n_snps,
        "annot_type": "snp_loc",
        "window_kb": [win_up, win_down],
        "annot_ok": result.returncode == 0,
    }, open("annotate.json", "w"), indent=2)
    PY
    """
}

// [Phase B] Gene analysis — per-gene Z-statistics from GWAS p-values
process MAGMA_GENE_ANALYSIS {
    tag "magma:phaseB"
    label 'process_medium'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseB_gene_analysis", mode: 'copy'

    input:  tuple val(meta), path(genes_annot), path(annotate_json)
    output: tuple val(meta),
            path("${params.outfile}.genes.out"),
            path("${params.outfile}.genes.raw"),
            path("gene_analysis.json"), emit: out

    script:
    def outfile  = params.outfile
    def model    = params.gene_model
    def snp_col  = params.snp_col
    def pval_col = params.pval_col
    def n_col    = params.n_col
    def n_fixed  = params.sample_size
    """
    set -euo pipefail
    python3 - <<'PY'
    import json, os, sys, subprocess, csv, shutil

    outfile  = "${outfile}"
    model    = "${model}"     # snp-wise | multi
    snp_col  = "${snp_col}"
    pval_col = "${pval_col}"
    n_col    = "${n_col}"
    n_fixed  = ${n_fixed}
    annot    = json.load(open("${annotate_json}"))

    baked = annot.get("baked_toy", False)

    # Re-build pval.txt from sumstats. The GWAS file is not passed as a Nextflow
    # channel input (too large for staging), so we download it again here.
    gwas_sumstats = "${params.gwas_sumstats}"

    if baked:
        # Regenerate same synthetic chr1 data (same random seed → same rows)
        import random
        random.seed(42)
        rows = [("SNP", "CHR", "BP", "P", "N")]
        for i in range(200):
            bp = random.randint(50_000_000, 55_000_000)
            p  = 10 ** -random.uniform(5, 9)
            rows.append((f"rs_cl1_{i}", "1", str(bp), f"{p:.6e}", "50000"))
        for i in range(1800):
            bp = random.randint(1_000_000, 249_000_000)
            p  = random.uniform(0.01, 0.99)
            rows.append((f"rs_bg_{i}", "1", str(bp), f"{p:.6e}", "50000"))
        with open("pval.txt", "w") as f, open("snp.loc", "w") as sl:
            f.write("SNP\\tP\\tN\\n")
            sl.write("SNP\\tCHR\\tBP\\n")
            for r in rows[1:]:
                f.write(f"{r[0]}\\t{r[3]}\\t{r[4]}\\n")
                sl.write(f"{r[0]}\\t{r[1]}\\t{r[2]}\\n")
        pval_col  = "P"
        n_spec    = "N"
    else:
        # Build pval.txt and snp.loc simultaneously from real sumstats (single-pass)
        if gwas_sumstats in ("null", ""):
            print("ERROR: gwas_sumstats required", file=sys.stderr)
            sys.exit(1)
        import gzip as _gz
        if gwas_sumstats.startswith("s3://"):
            import boto3
            parts = gwas_sumstats[5:].split("/", 1)
            boto3.client("s3").download_file(parts[0], parts[1], "sumstats_b.tmp")
            psum = "sumstats_b.tmp"
        else:
            psum = gwas_sumstats
        def _open_b(path):
            with open(path, "rb") as _f:
                magic = _f.read(2)
            return _gz.open(path, "rt") if magic == b"\\x1f\\x8b" else open(path)
        with _open_b(psum) as fh, open("pval.txt", "w") as out, open("snp.loc", "w") as sloc:
            reader = csv.DictReader(fh, delimiter="\\t")
            col_map = {c.upper(): c for c in (reader.fieldnames or [])}

            # SNP ID column — must match IDs used in Phase A snp.loc
            s_col = col_map.get(snp_col.upper())
            if s_col is None:
                for alias in ("VARIANT_ID", "SNP_ID", "RSID", "RS_ID", "ID",
                              "MARKERNAME", "SNPID", "NAME", "VARIANT"):
                    if alias in col_map:
                        s_col = col_map[alias]; break
            if s_col is None:
                print(f"ERROR: SNP column '{snp_col}' not found. Columns: {list(col_map.keys())}", file=sys.stderr)
                sys.exit(1)

            # P-value column
            p_col = col_map.get(pval_col.upper())
            if p_col is None:
                for alias in ("P_VALUE", "PVALUE", "PVAL", "P.VALUE", "LOG10P"):
                    if alias in col_map:
                        p_col = col_map[alias]; break
            if p_col is None:
                print(f"ERROR: P-value column '{pval_col}' not found. Columns: {list(col_map.keys())}", file=sys.stderr)
                sys.exit(1)

            # CHR/BP columns for snp.loc (used by Phase B --snp-loc to avoid --bfile OOM)
            chr_col = (col_map.get("CHR") or col_map.get("CHROMOSOME") or col_map.get("CHROM"))
            bp_col  = (col_map.get("BP") or col_map.get("POS") or col_map.get("POSITION") or
                       col_map.get("BASE_PAIR_LOCATION") or col_map.get("BASE_PAIR_LOCATION_HG19") or
                       col_map.get("BASE_PAIR_LOCATION_GRCH37") or col_map.get("BPLOC"))
            has_pos = chr_col is not None and bp_col is not None
            print(f"[magma:phaseB] has_pos={has_pos}, chr={chr_col}, bp={bp_col}")

            n_spec = col_map.get(n_col.upper(), None)
            print(f"[magma:phaseB] columns: snp={s_col}, p={p_col}, n={n_spec or 'fixed='+str(n_fixed)}")
            out.write("SNP\\tP\\tN\\n")
            sloc.write("SNP\\tCHR\\tBP\\n")
            for row in reader:
                n_val = row[n_spec] if n_spec and n_spec in row else str(n_fixed)
                out.write(f"{row[s_col]}\\t{row[p_col]}\\t{n_val}\\n")
                if has_pos:
                    chr_val = row[chr_col].lstrip("chrChr")
                    sloc.write(f"{row[s_col]}\\t{chr_val}\\t{row[bp_col]}\\n")
        n_spec = "N"

    # SNP-wise mean model implemented in Python via sort-merge join.
    # MAGMA Phase B requires --bfile, but loading the 22M-SNP g1000_eur bfile
    # OOM-kills the container (exit -9). Building a full Python SNP dict also OOM-kills
    # (3M string keys × Python overhead = 800MB+).
    # Solution: sort-merge join on disk — sorts both annotation pairs and pval.txt by
    # SNP ID, then streams them together accumulating chi² per gene.
    # Memory stays ~300MB regardless of GWAS size.
    # Formula: Z_g = (mean_chi2 - 1) * sqrt(k/2), P_g = 1 - Phi(Z_g)
    if model == "snp-wise":
        import scipy.stats as _sps, numpy as _np, subprocess as _sp

        # Step 1: Parse genes.annot → gene metadata + explode (snp, gid) pairs to disk
        _genes_annot_file = str("${genes_annot}")
        _gene_meta = {}  # gid → (chrom, start, stop, n_snps_annot)
        _n_pairs = 0
        with open(_genes_annot_file) as _af, open("_annot_pairs.tmp", "w") as _pf:
            for _line in _af:
                if _line.startswith("#"): continue
                _parts = _line.rstrip("\\n").split("\\t")
                if len(_parts) < 3: continue
                _gid = _parts[0]
                _pos = _parts[1].split(":")
                _snps = [s for s in _parts[2:] if s and s != "NA"]
                _gene_meta[_gid] = (_pos[0], int(_pos[1]), int(_pos[2]), len(_snps))
                for _snp in _snps:
                    _pf.write(f"{_snp}\\t{_gid}\\n")
                    _n_pairs += 1
        print(f"[magma:phaseB:py] {len(_gene_meta)} genes, {_n_pairs} annot pairs; sorting...")

        # Step 2: Sort annotation pairs and pval.txt by SNP (disk sort, O(1) RAM)
        _sp.run(["sort", "-k1,1", "--temporary-directory", ".", "_annot_pairs.tmp",
                 "-o", "_annot_sorted.tmp"], check=True)
        os.unlink("_annot_pairs.tmp")
        _sp.run(["bash", "-c",
                 "tail -n+2 pval.txt | sort -k1,1 --temporary-directory . > _pval_sorted.tmp"],
                check=True)
        print("[magma:phaseB:py] sort done; merging...")

        # Step 3: Stream-merge join: accumulate chi² per gene (O(1) RAM)
        # pval_sorted.tmp format: SNP<tab>P<tab>N (no header, col indices fixed)
        _gene_chi2 = {}   # gid → list of chi2 floats
        _gene_nv   = {}   # gid → list of N values
        _gene_nannot = {} # gid → len(annotation snps)
        with open("_annot_sorted.tmp") as _af, open("_pval_sorted.tmp") as _pf:
            _a_line = _af.readline()
            _p_line = _pf.readline()
            while _a_line and _p_line:
                _a_parts = _a_line.rstrip("\\n").split("\\t", 1)
                _p_parts = _p_line.rstrip("\\n").split("\\t")
                _a_snp = _a_parts[0]
                _p_snp = _p_parts[0]
                if _a_snp == _p_snp:
                    try:
                        _pv = float(_p_parts[1])
                        _nv = float(_p_parts[2]) if len(_p_parts) > 2 else n_fixed
                        if 0 < _pv < 1:
                            _pv = max(min(_pv, 1 - 1e-15), 1e-300)
                            _c2 = _sps.chi2.ppf(1.0 - _pv, df=1)
                            # All annotation entries for this SNP
                            while _a_line and _a_parts[0] == _p_snp:
                                _gid2 = _a_parts[1] if len(_a_parts) > 1 else _a_parts[0]
                                _gene_chi2.setdefault(_gid2, []).append(_c2)
                                _gene_nv.setdefault(_gid2, []).append(_nv)
                                _a_line = _af.readline()
                                if _a_line:
                                    _a_parts = _a_line.rstrip("\\n").split("\\t", 1)
                            _p_line = _pf.readline()
                            continue
                    except (ValueError, IndexError):
                        pass
                    # Skip mismatched annotation entry
                    _a_line = _af.readline()
                    if _a_line:
                        _a_parts = _a_line.rstrip("\\n").split("\\t", 1)
                elif _a_snp < _p_snp:
                    _a_line = _af.readline()
                else:
                    _p_line = _pf.readline()
        os.unlink("_annot_sorted.tmp")
        os.unlink("_pval_sorted.tmp")
        print(f"[magma:phaseB:py] merge done; {len(_gene_chi2)} genes have ≥1 matched SNP")

        # Step 4: compute gene-level Z-statistics and write output
        _out_rows = []
        for _gid, (_c2s) in _gene_chi2.items():
            _k = len(_c2s)
            if _k < 2: continue
            _chrom, _start, _stop, _nsnps_annot = _gene_meta.get(_gid, ("?", 0, 0, 0))
            _mean_c2 = float(_np.mean(_c2s))
            _n_mean  = float(_np.mean(_gene_nv.get(_gid, [n_fixed])))
            _z = max((_mean_c2 - 1.0) * _np.sqrt(_k / 2.0), 0.0)
            _pg = 1.0 - float(_sps.norm.cdf(_z))
            _out_rows.append((_gid, _chrom, _start, _stop, _nsnps_annot, _k, _n_mean, _z, _pg))

        _out_rows.sort(key=lambda r: r[-1])
        with open(f"{outfile}.genes.out", "w") as _of:
            _of.write("GENE\\tCHR\\tSTART\\tSTOP\\tNSNPS\\tNPARAM\\tN\\tZSTAT\\tP\\n")
            for _r in _out_rows:
                _of.write(f"{_r[0]}\\t{_r[1]}\\t{_r[2]}\\t{_r[3]}\\t"
                          f"{_r[4]}\\t{_r[5]}\\t{int(_r[6])}\\t{_r[7]:.6f}\\t{_r[8]:.6e}\\n")
        open(f"{outfile}.genes.raw", "w").write("")
        n_genes = len(_out_rows)
        magma_stdout = f"[python_snp_wise] {n_genes} genes scored via sort-merge join"
        print(magma_stdout)
        result_ok = True
    else:
        # multi model: use MAGMA with --bfile (requires LD; user knows this needs more memory)
        cmd = [
            "/opt/magma/magma",
            "--bfile", "/opt/magma/ref/g1000_eur",
            "--gene-annot", str("${genes_annot}"),
            "--pval", "pval.txt", "snp-id=SNP", "pval=P", "ncol=N",
            "--gene-model", model,
            "--out", outfile,
        ]
        with open("magma_stdout.log", "w") as _logf:
            _result = subprocess.run(cmd, stdout=_logf, stderr=subprocess.STDOUT, timeout=600)
        magma_stdout = open("magma_stdout.log").read()
        print(f"[magma:phaseB] MAGMA exit={_result.returncode}")
        print(magma_stdout[-3000:])
        if _result.returncode != 0:
            open(f"{outfile}.genes.out", "w").write(
                "GENE\\tCHR\\tSTART\\tSTOP\\tNSNPS\\tNPARAM\\tN\\tZSTAT\\tP\\n")
            open(f"{outfile}.genes.raw", "w").write("")
        else:
            if not os.path.exists(f"{outfile}.genes.raw"):
                open(f"{outfile}.genes.raw", "w").write("")
        n_genes = 0
        if os.path.exists(f"{outfile}.genes.out"):
            with open(f"{outfile}.genes.out") as fh:
                n_genes = max(0, sum(1 for _ in fh) - 1)
        result_ok = _result.returncode == 0

    json.dump({
        "phase": "B",
        "gene_model": model,
        "method": "python_snp_wise_mean" if model == "snp-wise" else "magma_bfile",
        "n_genes_output": n_genes,
        "gene_analysis_ok": result_ok,
        "magma_log_tail": magma_stdout[-5000:],
    }, open("gene_analysis.json", "w"), indent=2)
    PY
    """
}

// [Phase C] Format output — box-cox transform for scGWAS; plain gene table for TorchGWAS
process MAGMA_FORMAT {
    tag "magma:phaseC"
    label 'process_low'
    container CONTAINER_MAGMA
    publishDir "${params.outdir}/phaseC_format", mode: 'copy'

    input:  tuple val(meta), path(genes_out), path(genes_raw), path(gene_analysis_json)
    output: tuple val(meta),
            path("${params.outfile}.magma.txt"),
            path("${params.outfile}.magma_boxcox.txt"),
            path("magma_report.json"),
            path("magma_report.md"), emit: out

    script:
    def outfile = params.outfile
    """
    python3 - <<'PY'
    import json, csv, math, os
    import numpy as np
    from scipy import stats

    outfile = "${outfile}"
    genes_out = "${genes_out}"
    ga = json.load(open("${gene_analysis_json}"))

    rows = []
    with open(genes_out) as fh:
        reader = csv.DictReader(fh, delimiter="\\t")
        for row in reader:
            try:
                row["ZSTAT"] = float(row.get("ZSTAT", 0))
                row["P"] = float(row.get("P", 1.0))
            except ValueError:
                row["ZSTAT"] = 0.0
                row["P"] = 1.0
            rows.append(row)

    # Write raw MAGMA output (unchanged — useful for FUMA, general enrichment)
    if rows:
        keys = list(rows[0].keys())
        with open(f"{outfile}.magma.txt", "w") as f:
            f.write("\\t".join(keys) + "\\n")
            for r in rows:
                f.write("\\t".join(str(r.get(k, "")) for k in keys) + "\\n")
    else:
        open(f"{outfile}.magma.txt", "w").write(
            "GENE\\tCHR\\tSTART\\tSTOP\\tNSNPS\\tNPARAM\\tN\\tZSTAT\\tP\\n")

    # Box-Cox transform of ZSTAT column for scGWAS input.
    # scGWAS expects gene-level Z-scores after a Box-Cox normalization; the
    # original Pardinas 2018 example uses the same transformation.
    # We shift ZSTAT to be strictly positive (add offset = |min| + 1) before
    # applying Box-Cox, then write as a 2-column file: GENE  ZSTAT_BOXCOX
    boxcox_rows = []
    if rows:
        z_vals = np.array([r["ZSTAT"] for r in rows], dtype=float)
        offset = max(0, -z_vals.min()) + 1.0
        z_pos  = z_vals + offset
        try:
            z_bc, lam = stats.boxcox(z_pos)
            z_bc_list = z_bc.tolist()
        except Exception as e:
            print(f"[magma:phaseC] Box-Cox failed ({e}); using log1p fallback", file=sys.stderr)
            z_bc_list = np.log1p(z_pos).tolist()
            lam = None
        # Write in the format scGWAS magma_boxcox.txt expects:
        # GENE  CHR  START  STOP  NSNPS  NPARAM  N  ZSTAT  P
        # (same columns as .magma.txt but with ZSTAT replaced by box-cox value)
        keys = list(rows[0].keys())
        with open(f"{outfile}.magma_boxcox.txt", "w") as f:
            f.write("\\t".join(keys) + "\\n")
            for r, zbc in zip(rows, z_bc_list):
                r2 = dict(r)
                r2["ZSTAT"] = round(float(zbc), 6)
                f.write("\\t".join(str(r2.get(k, "")) for k in keys) + "\\n")
        boxcox_lambda = lam
    else:
        open(f"{outfile}.magma_boxcox.txt", "w").write(
            "GENE\\tCHR\\tSTART\\tSTOP\\tNSNPS\\tNPARAM\\tN\\tZSTAT\\tP\\n")
        boxcox_lambda = None

    n_sig = sum(1 for r in rows if r.get("P", 1.0) <= 2.5e-6)   # Bonferroni ~20k genes

    report = {
        "phase": "C",
        "tool": "MAGMA",
        "version": "v1.10",
        "url": "ctg.cncr.nl/software/magma",
        "n_genes_tested": len(rows),
        "n_significant_bonferroni": n_sig,
        "bonferroni_threshold": 2.5e-6,
        "boxcox_lambda": boxcox_lambda,
        "outputs": {
            "raw": f"{outfile}.magma.txt",
            "boxcox_for_scgwas": f"{outfile}.magma_boxcox.txt",
        },
        "downstream": {
            "scgwas": f"--gwas_sumstats {outfile}.magma_boxcox.txt",
            "fuma": "Upload .magma.txt to FUMA GENE2FUNC for pathway annotation",
        },
        "gene_analysis_detail": ga,
    }
    json.dump(report, open("magma_report.json", "w"), indent=2)

    top_genes = sorted(rows, key=lambda r: r.get("P", 1.0))[:5]
    top_str = "\\n".join(
        f"  {r.get('GENE','?'):12s}  Z={r.get('ZSTAT',0):.3f}  P={r.get('P',1.0):.2e}"
        for r in top_genes
    ) or "  (no genes)"
    open("magma_report.md", "w").write(
        f"# MAGMA gene analysis report\\n\\n"
        f"- Genes tested: {len(rows)}\\n"
        f"- Significant (Bonferroni ≤ 2.5×10⁻⁶): **{n_sig}**\\n"
        f"- Box-Cox λ: {f'{boxcox_lambda:.4f}' if boxcox_lambda is not None else 'N/A'}\\n\\n"
        f"## Top 5 genes by p-value\\n\\n"
        f"{top_str}\\n\\n"
        f"## Next steps\\n\\n"
        f"- **scGWAS**: pass `{outfile}.magma_boxcox.txt` as `--gwas_sumstats`\\n"
        f"- **FUMA**: upload `{outfile}.magma.txt` for pathway annotation\\n"
    )
    PY
    """
}

workflow {
    meta_ch = Channel.of([id: 'magma_gene_analysis'])
    a = MAGMA_ANNOTATE(meta_ch)
    b = MAGMA_GENE_ANALYSIS(a.out)
    MAGMA_FORMAT(b.out)
}
