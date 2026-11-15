#!/usr/bin/env nextflow
/*
 * immunology/surface_epitope_mapping
 *
 * Structure-based (conformational-aware) B-cell surface-epitope mapping. Upgrades
 * the sequence-only immunology/bcell_epitope_immunogen path with REAL geometric
 * surface exposure: given a predicted or experimental antigen structure it computes
 * per-residue solvent-accessible surface area (SASA) with the Shrake-Rupley
 * algorithm (biopython Bio.PDB.SASA), converts it to relative SASA vs the
 * Tien 2013 theoretical maxima, classifies residues exposed/buried, and combines
 * surface exposure with Kolaskar-Tongaonkar antigenicity to call surface epitope
 * patches. Pairs with a structure-prediction step (nf-core/proteinfold ESMFold /
 * AlphaFold, or Boltz-2) upstream.
 *
 * Fans out ONE PROCESS PER STRUCTURE for AWS-Batch parallelism. CPU only.
 *
 * HONEST SCOPE / what this is NOT:
 *   - Surface exposure is REAL (Shrake-Rupley SASA on the actual coordinates), but
 *     epitope patches are called on SEQUENCE-CONTIGUOUS exposed stretches. This is
 *     a geometric surface filter, NOT a trained conformational predictor
 *     (DiscoTope-3) and NOT spatial-neighbour (discontinuous-epitope) clustering —
 *     a true discontinuous epitope spanning distant residues brought together by
 *     the fold is a stated future increment, not silently implied.
 *   - A ranked shortlist to confirm by ELISA / neutralization, never a measured
 *     binding result. SASA is computed, never fabricated: an unparseable structure
 *     fails the task (exit 1).
 *
 * Inputs (params):
 *   params.structures   JSON list of {id, pdb} — pdb is a path/URI to a PDB or CIF
 *                       antigen structure (from a fold step or user-supplied).
 *   params.chain        chain id to analyse, or '' for all chains (default '').
 *   params.rsa_cutoff   relative-SASA cutoff for "exposed" (default 0.25, standard).
 *   params.min_patch    minimum contiguous exposed residues per patch (default 5).
 *   params.target       label (metadata only).
 *   params.outdir       output directory (default 'results').
 *
 * Container: the shared general tools image (biopython Bio.PDB — no new image, no GPU).
 */

nextflow.enable.dsl = 2


// Demo default is intentionally empty — this workflow consumes a real structure
// file; production supplies {id, pdb} (e.g. an ESMFold/AlphaFold model of an EBV
// antigen). With no structure the task fails with a clear message, never fabricates.
params.structures = '[]'
params.chain      = ''
params.rsa_cutoff = '0.25'
params.min_patch  = '5'
params.patch_radius = '12.0'   // CA-CA radius (A) for discontinuous spatial patches
params.target     = 'EBV'
params.outdir     = 'results'

process MAP_SURFACE_EPITOPES {
    tag "${struct_id}"
    label 'process_low'
    publishDir { "${params.outdir}/surface_epitopes/${struct_id.replaceAll('[^A-Za-z0-9]', '_')}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/workflow-tools:x86' : 'biomate/workflow-tools:latest'

    input:
    tuple val(struct_id), path(structure)

    output:
    tuple val(struct_id), path("${struct_id}_surface_residues.csv"), emit: residues
    tuple val(struct_id), path("${struct_id}_surface_epitopes.csv"), emit: epitopes
    tuple val(struct_id), path("${struct_id}_discontinuous_epitopes.json"), emit: discontinuous
    tuple val(struct_id), path("${struct_id}_summary.json"),         emit: summary
    path "versions.yml",                                             emit: versions

    script:
    """
    export STRUCT_ID='${struct_id}'
    export STRUCTURE='${structure}'
    export CHAIN='${params.chain}'
    export RSA_CUTOFF='${params.rsa_cutoff}'
    export MIN_PATCH='${params.min_patch}'
    export PATCH_RADIUS='${params.patch_radius}'

    python3 << 'PYEOF'
import os, json, sys, csv, math

sid    = os.environ["STRUCT_ID"].strip()
path   = os.environ["STRUCTURE"].strip()
chain_sel = os.environ.get("CHAIN", "").strip()
rsa_cut = float(os.environ.get("RSA_CUTOFF", "0.25") or 0.25)
min_patch = int(float(os.environ.get("MIN_PATCH", "5") or 5))
patch_r = float(os.environ.get("PATCH_RADIUS", "12.0") or 12.0)

if not path or not os.path.exists(path):
    sys.exit("FATAL: structure file not found for %s (%r)" % (sid, path))

# Tien et al. 2013 theoretical maximum ASA (A^2) for relative-SASA normalisation.
MAXASA = {'A':129.0,'R':274.0,'N':195.0,'D':193.0,'C':167.0,'E':223.0,'Q':225.0,'G':104.0,
 'H':224.0,'I':197.0,'L':201.0,'K':236.0,'M':224.0,'F':240.0,'P':159.0,'S':155.0,
 'T':172.0,'W':285.0,'Y':263.0,'V':174.0}
# Kolaskar-Tongaonkar antigenic propensity (FEBS 1990).
KOL = {'A':1.064,'R':0.873,'N':0.776,'D':0.866,'C':1.412,'Q':1.015,'E':0.851,'G':0.874,'H':1.105,'I':1.152,
 'L':1.250,'K':0.930,'M':0.826,'F':1.091,'P':1.064,'S':1.012,'T':0.909,'W':0.893,'Y':1.161,'V':1.383}
THREE2ONE = {'ALA':'A','ARG':'R','ASN':'N','ASP':'D','CYS':'C','GLU':'E','GLN':'Q','GLY':'G',
 'HIS':'H','ILE':'I','LEU':'L','LYS':'K','MET':'M','PHE':'F','PRO':'P','SER':'S','THR':'T',
 'TRP':'W','TYR':'Y','VAL':'V'}

try:
    from Bio.PDB import PDBParser, MMCIFParser, is_aa
    from Bio.PDB.SASA import ShrakeRupley
except Exception as e:
    sys.exit("FATAL: biopython Bio.PDB/SASA not available in this image (%s)." % e)

parser = MMCIFParser(QUIET=True) if path.lower().endswith((".cif", ".mmcif")) else PDBParser(QUIET=True)
try:
    structure = parser.get_structure(sid, path)
except Exception as e:
    sys.exit("FATAL: could not parse structure %s: %s" % (sid, e))

model = next(structure.get_models())
try:
    ShrakeRupley().compute(model, level="R")  # sets residue.sasa
except Exception as e:
    sys.exit("FATAL: Shrake-Rupley SASA failed for %s: %s" % (sid, e))

rows = []     # ordered residues analysed
coords = []   # CA coordinate per row (None if absent) — for 3D discontinuous clustering
for chain in model:
    if chain_sel and chain.id != chain_sel:
        continue
    for res in chain:
        if not is_aa(res, standard=True):
            continue
        aa = THREE2ONE.get(res.get_resname().upper())
        if aa is None:
            continue
        sasa = float(getattr(res, "sasa", 0.0) or 0.0)
        rsa = sasa / MAXASA[aa] if MAXASA.get(aa) else None
        exposed = (rsa is not None and rsa >= rsa_cut)
        rows.append({
            "chain": chain.id,
            "resseq": res.id[1],
            "aa": aa,
            "sasa": round(sasa, 2),
            "rsa": round(rsa, 4) if rsa is not None else None,
            "exposed": 1 if exposed else 0,
            "antigenicity": round(KOL[aa], 4),
            # surface-epitope score: exposed, antigenic residues score high
            "surface_score": round((rsa if rsa is not None else 0.0) * KOL[aa], 4),
        })
        try:
            c = res["CA"].get_coord()
            coords.append((float(c[0]), float(c[1]), float(c[2])))
        except Exception:
            coords.append(None)

if not rows:
    sys.exit("FATAL: no standard amino-acid residues analysed for %s "
             "(chain filter %r?)" % (sid, chain_sel or "all"))

with open("%s_surface_residues.csv" % sid, "w", newline="") as fh:
    cols = ["chain","resseq","aa","sasa","rsa","exposed","antigenicity","surface_score"]
    w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
    for r in rows:
        w.writerow(r)

# call SEQUENCE-CONTIGUOUS exposed patches (per chain), >= min_patch residues
patches = []
i = 0
while i < len(rows):
    r = rows[i]
    if r["exposed"]:
        j = i
        while (j < len(rows) and rows[j]["exposed"]
               and rows[j]["chain"] == r["chain"]
               and (j == i or rows[j]["resseq"] == rows[j-1]["resseq"] + 1)):
            j += 1
        seg = rows[i:j]
        if len(seg) >= min_patch:
            patches.append({
                "chain": r["chain"],
                "start_resseq": seg[0]["resseq"], "end_resseq": seg[-1]["resseq"],
                "length": len(seg),
                "sequence": "".join(s["aa"] for s in seg),
                "mean_rsa": round(sum(s["rsa"] for s in seg)/len(seg), 4),
                "mean_antigenicity": round(sum(s["antigenicity"] for s in seg)/len(seg), 4),
                "mean_surface_score": round(sum(s["surface_score"] for s in seg)/len(seg), 4),
            })
        i = j
    else:
        i += 1
patches.sort(key=lambda p: p["mean_surface_score"], reverse=True)
for rank, p in enumerate(patches, 1):
    p["rank"] = rank

with open("%s_surface_epitopes.csv" % sid, "w", newline="") as fh:
    cols = ["rank","chain","start_resseq","end_resseq","length","sequence",
            "mean_rsa","mean_antigenicity","mean_surface_score"]
    w = csv.DictWriter(fh, fieldnames=cols); w.writeheader()
    for p in patches:
        w.writerow({k: p.get(k) for k in cols})

# --- DISCONTINUOUS (spatial-neighbour) conformational epitope patches --------
# True conformational B-cell epitopes are residues brought together in 3D by the
# fold, not necessarily adjacent in sequence. Greedily grow patches: seed on the
# most antigenic exposed residue, gather every exposed residue within patch_r (A)
# CA-CA of the seed, mark them used, repeat. n_sequence_segments>1 => genuinely
# discontinuous. Real geometry (actual coordinates), not a trained predictor.
cand = [i for i in range(len(rows)) if rows[i]["exposed"] and coords[i] is not None]
cand.sort(key=lambda i: rows[i]["surface_score"], reverse=True)
used = set()
disc = []
for seed in cand:
    if seed in used:
        continue
    members = [j for j in cand if j not in used and math.dist(coords[seed], coords[j]) <= patch_r]
    if len(members) < min_patch:
        continue
    for j in members:
        used.add(j)
    rseqs = sorted(rows[j]["resseq"] for j in members)
    n_seg = 1 + sum(1 for k in range(1, len(rseqs)) if rseqs[k] != rseqs[k-1] + 1)
    disc.append({
        "seed": {"chain": rows[seed]["chain"], "resseq": rows[seed]["resseq"], "aa": rows[seed]["aa"]},
        "n_residues": len(members),
        "n_sequence_segments": n_seg,           # >1 = truly discontinuous
        "discontinuous": n_seg > 1,
        "mean_rsa": round(sum(rows[j]["rsa"] for j in members)/len(members), 4),
        "mean_surface_score": round(sum(rows[j]["surface_score"] for j in members)/len(members), 4),
        "residues": [{"chain": rows[j]["chain"], "resseq": rows[j]["resseq"], "aa": rows[j]["aa"],
                      "rsa": rows[j]["rsa"], "surface_score": rows[j]["surface_score"]} for j in members],
    })
disc.sort(key=lambda p: p["mean_surface_score"], reverse=True)
for rank, p in enumerate(disc, 1):
    p["rank"] = rank
with open("%s_discontinuous_epitopes.json" % sid, "w") as fh:
    json.dump({"structure_id": sid, "patch_radius_A": patch_r, "n_patches": len(disc),
               "n_truly_discontinuous": sum(1 for p in disc if p["discontinuous"]),
               "note": "Spatial-neighbour conformational B-cell epitope patches from real CA-CA geometry "
                       "(exposed antigenic residues within %.1f A of a seed). n_sequence_segments>1 means the "
                       "patch spans sequence-distant residues brought together by the fold. Geometric, not a "
                       "trained predictor (DiscoTope); confirm by ELISA/neutralization." % patch_r,
               "patches": disc}, fh, indent=2)

n_exposed = sum(r["exposed"] for r in rows)
summary = {
    "structure_id": sid, "target": os.environ.get("TARGET", ""),
    "n_discontinuous_epitopes": len(disc),
    "n_truly_discontinuous": sum(1 for p in disc if p["discontinuous"]),
    "method": "Shrake-Rupley SASA (biopython) + Tien 2013 relative-SASA + Kolaskar antigenicity",
    "n_residues": len(rows),
    "n_exposed": n_exposed,
    "pct_exposed": round(100.0 * n_exposed / len(rows), 1),
    "rsa_cutoff": rsa_cut, "min_patch": min_patch,
    "n_surface_epitopes": len(patches),
    "top_epitopes": [{"rank": p["rank"], "chain": p["chain"],
                      "start": p["start_resseq"], "end": p["end_resseq"],
                      "sequence": p["sequence"], "mean_surface_score": p["mean_surface_score"]}
                     for p in patches[:10]],
    "status": "ok" if patches else "no_surface_patches",
    "note": "Conformational-aware SURFACE exposure (real Shrake-Rupley SASA) + sequence "
            "antigenicity. Patches are sequence-contiguous exposed stretches, NOT a trained "
            "conformational predictor (DiscoTope) or discontinuous spatial clustering. Confirm "
            "by ELISA / neutralization.",
}
with open("%s_summary.json" % sid, "w") as fh:
    json.dump(summary, fh, indent=2)
print(json.dumps({k: summary[k] for k in ("structure_id","n_residues","n_exposed","n_surface_epitopes","n_discontinuous_epitopes","status")}, indent=2))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biopython: \$(python3 -c "import Bio; print(Bio.__version__)" 2>/dev/null || echo unknown)
        method: "Shrake-Rupley SASA + Tien2013 RSA + Kolaskar antigenicity"
    END_VERSIONS
    """
}

workflow SURFACE_EPITOPE_MAPPING {
    take:
    ch_structures   // channel: tuple(struct_id, structure_path) — ONE per structure -> parallel

    main:
    MAP_SURFACE_EPITOPES(ch_structures)

    emit:
    residues = MAP_SURFACE_EPITOPES.out.residues
    epitopes = MAP_SURFACE_EPITOPES.out.epitopes
    discontinuous = MAP_SURFACE_EPITOPES.out.discontinuous
    summary  = MAP_SURFACE_EPITOPES.out.summary
    versions = MAP_SURFACE_EPITOPES.out.versions
}

// Entry workflow for standalone execution.
workflow {
    def structures = params.structures instanceof String
        ? new groovy.json.JsonSlurper().parseText(params.structures)
        : params.structures

    ch_structures = Channel
        .fromList(structures)
        .map { s -> tuple((s.id ?: s.name) as String, file((s.pdb ?: s.structure ?: s.cif) as String)) }

    SURFACE_EPITOPE_MAPPING(ch_structures)

    SURFACE_EPITOPE_MAPPING.out.summary.view { sid, f -> "surface epitopes done: ${sid}" }
}
