#!/usr/bin/env nextflow

/**
 * drug_discovery/antibody_antigen_complex
 *
 * Boltz-2 antibody / antigen co-folding, fanned out ONE PROCESS PER ANTIBODY so
 * AWS Batch folds every antibody in PARALLEL. For each antibody it predicts the
 * Fv-antigen complex and reports Boltz's own interface confidence
 * (pair_chains_iptm between the antibody chains and each antigen chain) — the
 * binding-interface signal, never a fabricated score.
 *
 * This is the structure-prediction primitive the antibody / bispecific / CAR-ADC
 * design paths need:
 *   - mono-specific antibody / scFv  : VH + VL + one antigen
 *   - nanobody / VHH / single-domain : VH only + one antigen
 *   - bispecific (per arm)           : VH + VL + two antigens (A, B); each arm's
 *                                      interface iptm is reported separately so a
 *                                      bispecific's two targets are scored apart.
 *
 * Per antibody the process writes a Boltz YAML:
 *     version: 1
 *     sequences:
 *       - protein: { id: H, sequence: <VH> }
 *       - protein: { id: L, sequence: <VL> }        # omitted for VHH / single-domain
 *       - protein: { id: A, sequence: <antigen 1> }
 *       - protein: { id: B, sequence: <antigen 2> } # optional (bispecific / multi-antigen)
 * then runs:
     *     boltz predict in.yaml --out_dir out --use_msa_server --no_kernels --num_workers 0 --override
 * and emits the predicted complex CIF + Boltz confidence JSON + a per-antibody
 * summary (complex_iptm, and interface_iptm[antigen] = antibody<->antigen iptm).
 *
 * pair_chains_iptm is indexed by 0-based CHAIN POSITION (string), not chain id
 * (convention confirmed in research/guangzhou_all_atom/.../scripts/scoring.py):
 * interface_iptm for an antigen = max over antibody-chain positions i of
 * max(pc[i][antigen_pos], pc[antigen_pos][i]).
 *
 * Inputs (params):
 *   params.antibodies     JSON list of {id, vh, vl?}  -> one parallel fold each
 *   params.antigen_chains JSON map chain_label -> sequence (1+ antigens)
 *   params.target         label for the antigen/target (metadata only)
 *   params.outdir         output directory (default: 'results')
 *
 * Container: the Boltz-2 GPU image shared with cyclic_peptide_cofold /
 * boltz_structure_prediction (boltz + cuequivariance-torch). Session corrections
 * carried over: `--no_kernels` (cuequivariance kernel ImportError without it) and
 * `--use_msa_server` (single-seq folds error without an MSA).
 */

nextflow.enable.dsl = 2

// Demo defaults (overridden by BioMate's executor at launch). VH/VL below are the
// FMC63 anti-CD19 Fv (Kymriah/Yescarta) folded against a short CD19 fragment — a
// wiring demo only, not a validated epitope.
// Note: use fully-qualified groovy.json.JsonSlurper (no top-level import) — Nextflow
// strict/classic parsers reject `import groovy.json.JsonSlurper` as a script compile
// error on some Batch head images (coldstart design-fold-complex-bio-0/1).
params.antibodies      = '[{"id": "fmc63", "vh": "EVKLQESGPGLVAPSQSLSVTCTVSGVSLPDYGVSWIRQPPRKGLEWLGVIWGSETTYYNSALKSRLTIIKDNSKSQVFLKMNSLQTDDTAIYYCAKHYYYGGSYAMDYWGQGTSVTVSS", "vl": "DIQMTQTTSSLSASLGDRVTISCRASQDISKYLNWYQQKPDGTVKLLIYHTSRLHSGVPSRFSGSGSGTDYSLTISNLEQEDIATYFCQQGNTLPYTFGGGTKLEIT"}]'
params.antigen_chains  = '{"A": "PEELGGGGSGGGGSGGGGSQFSVLKMTTIRHWEDIKELGPTPGSEDSLYNNFRGSSHGFPEDIIIGSDIKE"}'
params.target          = 'demo_target'
params.outdir          = 'results'

process FOLD_COMPLEX {
    tag "${ab_id}"
    label 'process_gpu'
    publishDir { "${params.outdir}/antibody_antigen_complex/${ab_id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/boltz:latest' : 'biomate/ai-tools/boltz:latest'

    input:
    tuple val(ab_id), val(vh), val(vl)

    output:
    tuple val(ab_id), path("out/**/*.cif"),             emit: structures, optional: true
    tuple val(ab_id), path("out/**/confidence_*.json"), emit: confidence, optional: true
    tuple val(ab_id), path("${ab_id}_complex.json"),    emit: summary
    path "versions.yml",                                emit: versions

    script:
    """
    export AB_ID='${ab_id}'
    export VH='${vh}'
    export VL='${vl}'
    export PARAM_ANTIGEN_CHAINS='${params.antigen_chains}'
    export TARGET='${params.target}'

    # 1) Build the Boltz YAML and record chain order so the summary can map
    #    pair_chains_iptm (0-based position) to antibody vs antigen chains.
    python3 << 'PYEOF'
import os, json

vh = os.environ.get("VH", "").strip()
vl = os.environ.get("VL", "").strip()
antigens = json.loads(os.environ.get("PARAM_ANTIGEN_CHAINS") or "{}")
if not vh:
    raise SystemExit("FATAL: empty VH sequence")
if not antigens:
    raise SystemExit("FATAL: no antigen_chains supplied (need 1+)")

# Chain ids: antibody H (+ L if VL present), antigens from a pool that excludes
# H/L. Order determines the 0-based position used by pair_chains_iptm.
order = []            # list of (chain_id, role, label)
lines = ["version: 1", "sequences:"]

def add(cid, seq, role, label):
    order.append((cid, role, label))
    lines.append("  - protein:")
    lines.append("      id: %s" % cid)
    lines.append("      sequence: %s" % seq)

add("H", vh, "antibody", "VH")
if vl:
    add("L", vl, "antibody", "VL")

pool = [c for c in "ABCDEFGIJKMNOPQRSTUVWXYZ" if c not in ("H", "L")]
for i, (label, seq) in enumerate(antigens.items()):
    seq = str(seq).strip()
    if not seq:
        raise SystemExit("FATAL: empty antigen sequence for '%s'" % label)
    add(pool[i], seq, "antigen", str(label))

with open("in.yaml", "w") as f:
    f.write("\\n".join(lines) + "\\n")
with open("chain_order.json", "w") as f:
    json.dump(order, f)
print("=== Boltz YAML ===")
print(open("in.yaml").read())
PYEOF

    # 2) Fold the complex. --num_workers 0: the default DataLoader worker subprocess crashes on AWS
    #    Batch ("DataLoader worker exited unexpectedly") for Fv+antigen-sized inputs (small /dev/shm);
    #    loading in-process avoids it (same fix boltz_structure_prediction uses).
    boltz predict in.yaml --out_dir out --use_msa_server --no_kernels --num_workers 0 --override 2>&1 | tee boltz_run.log

    # 2b) FAIL LOUDLY on an OOM-skip / failed example. Boltz exits 0 even when it
    #     skips a batch for GPU OOM ("ran out of memory, skipping batch" /
    #     "Number of failed examples: N>0") and writes no structure — which otherwise
    #     surfaces as a silent "no_structure" success (the summary below runs fine on
    #     0 cifs). A fold that produced no structure must FAIL the task so the run is
    #     not reported as complete. Root cause when this fires: the complex is too
    #     large for this GPU — crop the antigen to the binding domain or use a
    #     larger-memory GPU instance.
    if grep -qiE "ran out of memory|Number of failed examples: [1-9]" boltz_run.log \
       && [ -z "\$(find out -name '*.cif' 2>/dev/null)" ]; then
      echo "[antibody_antigen_complex] Boltz produced NO structure (GPU OOM / failed example). Likely the complex is too large for this GPU — crop the antigen to its binding domain or use a larger-memory GPU." >&2
      exit 42
    fi

    # 3) Summarise: complex confidence + per-antigen antibody<->antigen interface
    #    iptm from pair_chains_iptm (0-based chain position). Null if Boltz did
    #    not emit it — never fabricated.
    python3 << 'PYEOF'
import os, json, glob

ab_id = os.environ["AB_ID"]
order = json.load(open("chain_order.json"))
ab_pos  = [str(i) for i, (_, role, _) in enumerate(order) if role == "antibody"]
ag_pos  = [(str(i), lab) for i, (_, role, lab) in enumerate(order) if role == "antigen"]

cifs = sorted(glob.glob("out/**/*.cif", recursive=True))
conf_files = sorted(glob.glob("out/**/confidence_*.json", recursive=True))

conf = {}
for cj in conf_files:
    try:
        conf = json.load(open(cj))
        break
    except Exception:
        continue

def iface(pc, a_positions, g_pos):
    vals = []
    for i in a_positions:
        for x in (pc.get(i, {}).get(g_pos), pc.get(g_pos, {}).get(i)):
            if x is not None:
                vals.append(float(x))
    return max(vals) if vals else None

pc = conf.get("pair_chains_iptm") or {}
interface_iptm = {lab: iface(pc, ab_pos, gp) for gp, lab in ag_pos}
# For a single antigen, prefer the pair value, else Boltz's global iptm.
if len(ag_pos) == 1 and interface_iptm[ag_pos[0][1]] is None:
    interface_iptm[ag_pos[0][1]] = conf.get("iptm")

best = [v for v in interface_iptm.values() if v is not None]
summary = {
    "antibody_id": ab_id,
    "target": os.environ.get("TARGET"),
    "tool": "Boltz-2",
    "format": "VH+VL" if any(r == "antibody" and l == "VL" for _, r, l in order) else "VH-only (VHH/single-domain)",
    "n_antigens": len(ag_pos),
    "n_structures": len(cifs),
    "structure_files": [os.path.basename(c) for c in cifs],
    "complex_iptm": conf.get("complex_iptm") if conf.get("complex_iptm") is not None else conf.get("iptm"),
    "complex_plddt": conf.get("complex_plddt"),
    "confidence_score": conf.get("confidence_score"),
    "interface_iptm": interface_iptm,
    "best_interface_iptm": max(best) if best else None,
    "status": "ok" if cifs else "no_structure",
    "note": "interface_iptm = antibody<->antigen pair_chains_iptm (Boltz-2 interface "
            "confidence); binding readout, not an affinity. Fv model (VH/VL variable "
            "domains); no constant region, glycans or ncAA.",
}
with open("%s_complex.json" % ab_id, "w") as f:
    json.dump(summary, f, indent=2)
print(json.dumps(summary, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        boltz: \$(python3 -c "import boltz; print(getattr(boltz,'__version__','unknown'))" 2>/dev/null || echo unknown)
        python: \$(python3 --version | cut -d' ' -f2)
END_VERSIONS
    """
}

workflow ANTIBODY_ANTIGEN_COMPLEX {
    take:
    ch_antibodies   // channel: tuple(ab_id, vh, vl) — ONE element per antibody -> parallel folds

    main:
    FOLD_COMPLEX(ch_antibodies)

    emit:
    structures = FOLD_COMPLEX.out.structures
    confidence = FOLD_COMPLEX.out.confidence
    summary    = FOLD_COMPLEX.out.summary
    versions   = FOLD_COMPLEX.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def antibodies = params.antibodies instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.antibodies as String)
        : params.antibodies
    if (!(antibodies instanceof List) || antibodies.isEmpty()) {
        error "params.antibodies must be a non-empty JSON list of {id, vh, vl?}"
    }

    ch_antibodies = Channel
        .fromList(antibodies)
        .map { a -> tuple(a.id as String, a.vh as String, (a.vl ?: '') as String) }

    ANTIBODY_ANTIGEN_COMPLEX(ch_antibodies)

    ANTIBODY_ANTIGEN_COMPLEX.out.summary.view { aid, f -> "antibody-antigen complex done: ${aid}" }
}
