#!/usr/bin/env nextflow
// ============================================================
// Bioconductor-style workflow: multiomics_benchmark — one dataset, MANY methods, one report
// The BioMate BENCHMARK capability: given a multi-omics dataset, run several integration
// methods on the SAME input in ONE execution, then score + rank them into a single
// comparison report. Turns the previously-ad-hoc "run each method + score externally"
// loop into a first-class platform feature.
//
// Runs (all via the shared universal CSV interface): SNF, intNMF, MCIA, iClusterPlus,
// JIVE, MFA (the hard-clustering methods). A COMPARE step scores every method's
// clusters.csv against an optional ground-truth label (ARI + NMI, ranked) OR, with no
// label, computes pairwise inter-method agreement (a consensus ranking).
//
// MOFA2 is factor-output (not hard clusters), so it is NOT included here — benchmarking
// it means k-means-ing its factors, a follow-up (the COMPARE step would grow a factors
// branch). This workflow covers the six clustering methods.
// Input: omics
// Params: omics (list), n_clusters, labels (optional S3 CSV: sample,<label>),
//         benchmark_methods (optional comma-list subset; default = all six)
// Container: bioc-domain-general:3.20-slim (python3 for COMPARE; methods self-install)
// ============================================================

nextflow.enable.dsl = 2

include { BIOC_SNF_MULTIOMICS }          from '../snf_multiomics/main.nf'
include { BIOC_INTNMF_MULTIOMICS }       from '../intnmf_multiomics/main.nf'
include { BIOC_MCIA_MULTIOMICS }         from '../mcia_multiomics/main.nf'
include { BIOC_ICLUSTERPLUS_MULTIOMICS } from '../iclusterplus_multiomics/main.nf'
include { BIOC_JIVE_MULTIOMICS }         from '../jive_multiomics/main.nf'
include { BIOC_RGCCA_MULTIOMICS }        from '../rgcca_multiomics/main.nf'   // method = MFA

process BENCHMARK_COMPARE {
    tag "benchmark"
    label 'process_low'

    publishDir "${params.outdir}", mode: 'copy'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

    input:
    path cluster_files
    path labels

    output:
    path "benchmark_report.csv",    emit: report,    optional: true
    path "benchmark_agreement.csv", emit: agreement, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    """
    #!/usr/bin/env python3
    import csv, glob, os
    from collections import Counter
    from itertools import combinations
    from math import comb, log

    def strip(s): return s.strip().strip('"').strip("'")

    def read_clusters(path):
        out = {}
        with open(path) as fh:
            r = list(csv.reader(fh))
        if not r: return out
        for row in r[1:]:
            if len(row) >= 2 and strip(row[0]):
                out[strip(row[0])] = strip(row[1])
        return out

    def read_labels(path):
        out = {}
        if not path or not os.path.exists(path): return out
        with open(path) as fh:
            r = list(csv.reader(fh))
        if len(r) < 2: return out                      # header only -> no-label mode
        for row in r[1:]:
            if len(row) >= 2 and strip(row[0]) and strip(row[1]) not in ('', 'NA', 'NaN'):
                out[strip(row[0])] = strip(row[1])
        return out

    def ari(a, b):
        tab = Counter(zip(a, b)); ai = Counter(a); bj = Counter(b); n = len(a)
        if n < 2: return float('nan')
        idx = sum(comb(v, 2) for v in tab.values())
        sa = sum(comb(v, 2) for v in ai.values()); sb = sum(comb(v, 2) for v in bj.values())
        exp = sa * sb / comb(n, 2); mx = (sa + sb) / 2
        return (idx - exp) / (mx - exp) if mx != exp else 0.0

    def nmi(a, b):
        n = len(a); tab = Counter(zip(a, b)); ai = Counter(a); bj = Counter(b)
        H = lambda c: -sum((v / n) * log(v / n) for v in c.values() if v)
        Ha, Hb = H(ai), H(bj); mi = 0.0
        for (x, y), nxy in tab.items():
            mi += (nxy / n) * log((nxy * n) / (ai[x] * bj[y]))
        denom = (Ha + Hb) / 2
        return mi / denom if denom else 0.0

    # --- collect every method's clusters (basename prefix before _clusters = method) ---
    methods = {}
    for f in sorted(glob.glob('*_clusters.csv')):
        name = os.path.basename(f).replace('_clusters.csv', '')
        c = read_clusters(f)
        if c: methods[name] = c
    print('[benchmark] methods found:', list(methods.keys()))

    labels = read_labels('${labels}')

    if labels:
        # ---- ground-truth mode: ARI + NMI per method, ranked ----
        rows = []
        for m, clu in methods.items():
            common = [s for s in clu if s in labels]
            if len(common) < 2:
                rows.append((m, float('nan'), float('nan'), len(common))); continue
            a = [clu[s] for s in common]; b = [labels[s] for s in common]
            rows.append((m, ari(a, b), nmi(a, b), len(common)))
        rows.sort(key=lambda r: (r[1] if r[1] == r[1] else -9))
        rows.reverse()
        with open('benchmark_report.csv', 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['method', 'ARI', 'NMI', 'n', 'rank'])
            for i, (m, a, nm, n) in enumerate(rows, 1):
                w.writerow([m, ('%.4f' % a) if a == a else 'NA', ('%.4f' % nm) if nm == nm else 'NA', n, i])
        best = rows[0][0] if rows else 'none'
        print('[benchmark] ground-truth ranking (by ARI):')
        for i, (m, a, nm, n) in enumerate(rows, 1):
            print('  %d. %-14s ARI=%s NMI=%s (n=%d)' % (i, m, ('%.4f' % a) if a == a else 'NA', ('%.4f' % nm) if nm == nm else 'NA', n))
        print('[benchmark] winner:', best)
    else:
        # ---- no label: pairwise inter-method agreement + consensus ranking ----
        names = list(methods.keys())
        pair = {}
        with open('benchmark_agreement.csv', 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['method_a', 'method_b', 'ARI'])
            for x, y in combinations(names, 2):
                common = [s for s in methods[x] if s in methods[y]]
                if len(common) < 2: continue
                v = ari([methods[x][s] for s in common], [methods[y][s] for s in common])
                pair[(x, y)] = v; pair[(y, x)] = v
                w.writerow([x, y, '%.4f' % v])
        meanag = {m: (sum(pair.get((m, o), 0.0) for o in names if o != m) / max(1, len(names) - 1)) for m in names}
        ranked = sorted(names, key=lambda m: meanag[m], reverse=True)
        print('[benchmark] no labels -> consensus ranking (mean pairwise ARI):')
        for i, m in enumerate(ranked, 1):
            print('  %d. %-14s mean_agreement=%.4f' % (i, m, meanag[m]))
        # also emit a report so the panel always has one file
        with open('benchmark_report.csv', 'w', newline='') as fh:
            w = csv.writer(fh); w.writerow(['method', 'mean_agreement', 'rank'])
            for i, m in enumerate(ranked, 1): w.writerow([m, '%.4f' % meanag[m], i])

    with open('versions.yml', 'w') as fh:
        fh.write('"BENCHMARK_COMPARE":\\n    python: "' + os.popen('python3 --version').read().strip() + '"\\n')
    """

    stub:
    """
    touch benchmark_report.csv versions.yml
    """
}

workflow BIOC_MULTIOMICS_BENCHMARK_WORKFLOW {
    take:
    ch_input   // channel: [ val(meta), [ omics matrices ] ]

    main:
    // Run every clustering method on the SAME omics input.
    // Optional subset via params.benchmark_methods (comma list); default = all six.
    def _sel = (params.benchmark_methods ?: 'snf,intnmf,mcia,iclusterplus,jive,mfa')
                   .toString().toLowerCase().split(',').collect { it.trim() }
    def want = { String m -> _sel.contains(m) }

    def outs = []
    if (want('snf'))          { BIOC_SNF_MULTIOMICS(ch_input);          outs << BIOC_SNF_MULTIOMICS.out.tables }
    if (want('intnmf'))       { BIOC_INTNMF_MULTIOMICS(ch_input);       outs << BIOC_INTNMF_MULTIOMICS.out.tables }
    if (want('mcia'))         { BIOC_MCIA_MULTIOMICS(ch_input);         outs << BIOC_MCIA_MULTIOMICS.out.tables }
    if (want('iclusterplus')) { BIOC_ICLUSTERPLUS_MULTIOMICS(ch_input); outs << BIOC_ICLUSTERPLUS_MULTIOMICS.out.tables }
    if (want('jive'))         { BIOC_JIVE_MULTIOMICS(ch_input);         outs << BIOC_JIVE_MULTIOMICS.out.tables }
    if (want('mfa'))          { BIOC_RGCCA_MULTIOMICS(ch_input);        outs << BIOC_RGCCA_MULTIOMICS.out.tables }

    // Gather every method's output CSVs (clusters + views) into one list for COMPARE.
    // COMPARE only reads *_clusters.csv, so *_views.csv are harmless.
    ch_clusters = Channel.empty()
    outs.each { ch_clusters = ch_clusters.mix(it.map { it[1] }) }
    ch_clusters = ch_clusters.flatten().collect()

    // Labels flow ONLY here — a SEPARATE channel, never in the omics list the methods see,
    // so no method ever globs the ground-truth as a modality. Sentinel when absent.
    def _lab = params.labels ? file(params.labels) : file("${moduleDir}/no_labels.csv")
    ch_labels = Channel.value(_lab)

    BENCHMARK_COMPARE(ch_clusters, ch_labels)

    emit:
    report    = BENCHMARK_COMPARE.out.report
    agreement = BENCHMARK_COMPARE.out.agreement
    versions  = BENCHMARK_COMPARE.out.versions
}

// --- Anonymous entry: makes the file runnable DIRECTLY by BioMate's executor ---------------
// The executor's `_build_bioc_entry_wrapper` returns None for any .nf that already has an
// anonymous `workflow {` and runs it via plain `nextflow run file.nf` with params — so we
// self-stage the omics here instead of relying on the single-process wrapper (which would
// mis-target the composed BENCHMARK_COMPARE process). params.omics is a LIST of s3:// (or
// local) CSV paths; `file()` turns each into a Nextflow Path (the S3 plugin downloads s3://).
// The whole file list is bound to ONE stageAs slot (tuple[ meta, [files] ]), exactly the
// shape each method process expects. Labels are NOT handled here — the named workflow reads
// params.labels internally and routes it only to COMPARE, so the ground-truth never enters
// the omics list the methods glob.
workflow {
    def _omics = (params.omics instanceof List) ? params.omics
               : (params.omics ? [params.omics] : [])
    if (!_omics) error "multiomics_benchmark: params.omics is required (a list of omics CSV paths)"
    ch_input = Channel.fromList(_omics)
                      .map { file(it) }
                      .collect()
                      .map { fs -> tuple([id: 'sample'], fs) }
    BIOC_MULTIOMICS_BENCHMARK_WORKFLOW(ch_input)
}
