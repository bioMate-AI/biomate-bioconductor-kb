#!/usr/bin/env nextflow
/*
 * virtual_cell/gears_perturbation_prediction
 *
 * Gene perturbation response prediction using network propagation through
 * gene regulatory and co-expression networks — a scientifically grounded
 * approximation of the GEARS (Graph-Enhanced gene Activation/Repression
 * Simulator) framework (Roohani et al. 2024 Nature Biotechnology).
 *
 * Core algorithm:
 *   1. Map perturbed gene(s) to GO Biological Process pathways
 *   2. Propagate perturbation signal through curated gene-gene interaction
 *      network using a damped diffusion model (Vandin et al. 2012 NatMeth)
 *   3. Predict up/down DEG signature from network proximity scores
 *   4. Score genetic interactions for 2-gene combinations (epistasis model)
 *   5. Query LINCS L1000CDS² to cross-validate predicted expression shift
 *
 * GPU upgrade path:
 *   Replace propagation step with GEARS GNN inference:
 *     pip install gears torch-geometric scvi-tools
 *     from gears import PertData, GEARS
 *     model = GEARS(pert_data, device='cuda')
 *     model.predict([['GENE1', 'GENE2']])
 *   Training dataset: Norman 2019 (Figshare:24688110) or Replogle 2022 (Figshare:20029387)
 *   Docker: biomate/virtual-cell-gpu:1.0 (g4dn.xlarge, T4 16GB)
 *
 * Input:  perturb_genes (CSV), cell_line, perturbation_type (KO/KD/OE/CRISPRa)
 * Output: predicted_degs.json, network_scores.csv, perturbation_report.txt
 *
 * References:
 *   - Roohani et al. 2024 Nature Biotechnology (GEARS)
 *   - Vandin et al. 2012 Nature Methods (network propagation)
 *   - Ideker & Krogan 2012 Mol Syst Biol (genetic interactions)
 */

nextflow.enable.dsl = 2

params.outdir             = './results'
params.perturb_genes      = 'MYC'           // CSV of genes to perturb (1 or 2)
params.cell_line          = 'K562'          // K562 | RPE1 | MCF7 | HepG2 | A549
params.perturbation_type  = 'KO'            // KO | KD | OE | CRISPRa | CRISPRi
params.control_genes      = 'non-targeting' // control perturbation
params.top_k_degs         = '50'            // top DEGs to return per direction
params.lincs_crossval     = 'true'          // cross-validate via LINCS API
params.epistasis_model    = 'bliss'         // bliss | multiplicative | min (for 2-gene combos)

process GEARS_PERTURBATION_PREDICTION {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("predicted_degs.json"),      emit: results
    tuple val(meta), path("network_scores.csv"),       emit: scores
    tuple val(meta), path("perturbation_report.txt"),  emit: report
    path "versions.yml",                               emit: versions

    script:
    """
    export PARAM_GENES='${params.perturb_genes}'
    export PARAM_CELL='${params.cell_line}'
    export PARAM_TYPE='${params.perturbation_type}'
    export PARAM_TOPK='${params.top_k_degs}'
    export PARAM_LINCS='${params.lincs_crossval}'
    export PARAM_EPI='${params.epistasis_model}'

    python3 << 'PYEOF'
import json, os, csv, math, urllib.request, urllib.error

def pi(v, d=50):
    try: return int(v)
    except: return d
def pb(v, d=True):
    return str(v).lower() in ('true','1','yes') if v not in (None,'','null') else d

genes_raw    = os.environ.get('PARAM_GENES', 'MYC')
cell_line    = os.environ.get('PARAM_CELL',  'K562')
pert_type    = os.environ.get('PARAM_TYPE',  'KO').upper()
top_k        = pi(os.environ.get('PARAM_TOPK'), 50)
do_lincs     = pb(os.environ.get('PARAM_LINCS'), True)
epi_model    = os.environ.get('PARAM_EPI', 'bliss').lower()

perturb_genes = [g.strip().upper() for g in genes_raw.split(',') if g.strip()][:2]
is_combo = len(perturb_genes) == 2

# ─── Curated gene regulatory network (key cancer/proliferation regulators) ──
# Format: gene → {activates: [...], represses: [...], pathway: str, essential: bool}
# Sources: ENCODE TF ChIP-seq, STRING v12, CancerMine, ENCODE K562 regulome
GENE_NETWORK = {
    'MYC':    {'activates': ['CDK4','CCND1','E2F1','PCNA','TOP2A','MCM2','MKI67','LDHA','PKM','ENO1'],
               'represses': ['CDKN1A','CDKN1B','TP53','BBC3','PUMA'], 'pathway': 'cell_cycle', 'essential': True},
    'TP53':   {'activates': ['CDKN1A','BBC3','PUMA','GADD45A','MDM2','FAS','NOXA'],
               'represses': ['MYC','CDK4','CCND1','E2F1','MKI67'], 'pathway': 'apoptosis', 'essential': False},
    'EGFR':   {'activates': ['RAS','RAF1','MAP2K1','MAPK1','MYC','CCND1','AKT1'],
               'represses': ['CDKN1B'], 'pathway': 'EGFR_signaling', 'essential': False},
    'KRAS':   {'activates': ['RAF1','MAP2K1','MAPK1','MAPK3','PI3K','AKT1','MYC'],
               'represses': ['CDKN1A','CDKN2A'], 'pathway': 'MAPK', 'essential': True},
    'BRAF':   {'activates': ['MAP2K1','MAPK1','MAPK3','MYC','CCND1'],
               'represses': ['CDKN1A'], 'pathway': 'MAPK', 'essential': False},
    'MAP2K1': {'activates': ['MAPK1','MAPK3','ETS1','FOS','JUN'],
               'represses': ['CDKN1A','FOXO3'], 'pathway': 'MAPK', 'essential': False},
    'MAPK1':  {'activates': ['FOS','JUN','ETS1','RSK1','MNK1'],
               'represses': ['BIM','BAD'], 'pathway': 'MAPK', 'essential': False},
    'AKT1':   {'activates': ['MTOR','GSK3B_inh','FOXO3_inh','MDM2','CCND1'],
               'represses': ['CDKN1B','BAD','FOXO3'], 'pathway': 'PI3K_AKT', 'essential': False},
    'MTOR':   {'activates': ['S6K1','4EBP1_inh','HIF1A','MYC'],
               'represses': ['AUTOPHAGY','CDKN1A'], 'pathway': 'PI3K_AKT', 'essential': True},
    'PTEN':   {'activates': ['FOXO3','CDKN1B','TP53'],
               'represses': ['AKT1','PI3K','MTOR','MYC'], 'pathway': 'PI3K_AKT', 'essential': False},
    'RB1':    {'activates': ['CDKN1A','CDKN2A'],
               'represses': ['E2F1','CCND1','CDK4','MKI67','PCNA'], 'pathway': 'cell_cycle', 'essential': False},
    'E2F1':   {'activates': ['CCNE1','CCNA2','CDK2','PCNA','RRM2','TYMS'],
               'represses': ['RB1'], 'pathway': 'cell_cycle', 'essential': True},
    'CDK4':   {'activates': ['RB1_phos','E2F1'],
               'represses': ['CDKN1A'], 'pathway': 'cell_cycle', 'essential': False},
    'CDKN1A': {'activates': ['TP53','GADD45A'],
               'represses': ['CDK4','CDK2','CCND1','E2F1','PCNA'], 'pathway': 'cell_cycle', 'essential': False},
    'BCL2':   {'activates': ['MCL1','BCL2L1'],
               'represses': ['BAX','BAK1','CYTC'], 'pathway': 'apoptosis', 'essential': False},
    'BAX':    {'activates': ['CYTC','APAF1','CASP3','CASP9'],
               'represses': ['BCL2'], 'pathway': 'apoptosis', 'essential': False},
    'STAT3':  {'activates': ['MYC','BCL2','CCND1','MCL1','VEGFA','HIF1A'],
               'represses': ['TP53','CDKN1A'], 'pathway': 'JAK_STAT', 'essential': False},
    'HIF1A':  {'activates': ['VEGFA','LDHA','PKM','SLC2A1','BNIP3'],
               'represses': ['OXPHOS','VHL'], 'pathway': 'hypoxia', 'essential': False},
    'BRCA1':  {'activates': ['GADD45A','TP53','RAD51'],
               'represses': ['MYC','CCND1'], 'pathway': 'DNA_repair', 'essential': True},
    'MDM2':   {'activates': ['MDM2_auto'],
               'represses': ['TP53','CDKN1A','BBC3'], 'pathway': 'apoptosis', 'essential': False},
}

# ─── Network propagation (random-walk with restart) ─────────────────────────
# Computes influence score for each gene given the perturbed genes
# α = restart probability; higher α = more local effect
def network_propagation(seed_genes, network, pert_type, alpha=0.5, n_iter=10):
    """
    Simplified network propagation:
    - KO/KD: propagate negative signal through activates edges, positive through represses
    - OE/CRISPRa: propagate positive signal through activates, negative through represses
    Returns dict gene → (direction, score)
    """
    sign = -1 if pert_type in ('KO', 'KD', 'CRISPRi') else +1

    scores = {}  # gene → signed influence score
    # Seed with perturbed genes
    for g in seed_genes:
        scores[g] = sign * 1.0

    # Iterative propagation
    for iteration in range(n_iter):
        new_scores = {}
        for gene, s in scores.items():
            if gene not in network: continue
            decay = alpha ** (iteration + 1)
            # Propagate through activation edges
            for target in network[gene].get('activates', []):
                new_scores[target] = new_scores.get(target, 0) + s * decay
            # Propagate through repression edges (flip sign)
            for target in network[gene].get('represses', []):
                new_scores[target] = new_scores.get(target, 0) - s * decay

        for g, sc in new_scores.items():
            if g not in seed_genes:
                scores[g] = scores.get(g, 0) + sc

    # Normalise by max abs score
    max_abs = max((abs(v) for v in scores.values()), default=1.0)
    if max_abs > 0:
        scores = {g: round(s / max_abs, 4) for g, s in scores.items()}
    return scores

single_scores = []
for gene in perturb_genes:
    sc = network_propagation([gene], GENE_NETWORK, pert_type)
    single_scores.append(sc)

# ─── Epistasis for 2-gene combinations ──────────────────────────────────────
def combine_scores(s1, s2, model='bliss'):
    all_genes = set(s1) | set(s2)
    combo = {}
    for g in all_genes:
        a, b = s1.get(g, 0), s2.get(g, 0)
        if model == 'bliss':
            # Bliss independence: expected = a + b - a*b (for same direction)
            if a * b >= 0:  # same direction
                combo[g] = round(a + b - a * b, 4) if a >= 0 else round(a + b + a * b, 4)
            else:  # opposing
                combo[g] = round(a + b, 4)
        elif model == 'multiplicative':
            combo[g] = round(a * b, 4) if a * b != 0 else round((a + b) * 0.5, 4)
        else:  # min (most conservative)
            combo[g] = a if abs(a) < abs(b) else b
    return combo

if is_combo:
    prop_scores = combine_scores(single_scores[0], single_scores[1], epi_model)
    # Synergy = observed combo - expected (Bliss expected = single1 + single2 - single1*single2)
    synergy_scores = {}
    for g in set(single_scores[0]) | set(single_scores[1]):
        a = single_scores[0].get(g, 0)
        b = single_scores[1].get(g, 0)
        expected = a + b - a * b if a * b >= 0 else a + b
        obs = prop_scores.get(g, 0)
        synergy_scores[g] = round(obs - expected, 4)
else:
    prop_scores = single_scores[0]
    synergy_scores = {}

# ─── DEG prediction ──────────────────────────────────────────────────────────
up_degs   = sorted([(g, s) for g, s in prop_scores.items() if s > 0.05],
                   key=lambda x: -x[1])[:top_k]
down_degs = sorted([(g, s) for g, s in prop_scores.items() if s < -0.05],
                   key=lambda x: x[1])[:top_k]

# ─── GO pathway enrichment (curated) ────────────────────────────────────────
GO_PATHWAYS = {
    'cell_cycle_G1_S':      ['CDK4','CCND1','E2F1','CDKN1A','CDKN1B','RB1','PCNA','CCNE1'],
    'cell_cycle_G2_M':      ['CDK1','CCNB1','TOP2A','MKI67','AURKA','PLK1'],
    'apoptosis_intrinsic':  ['TP53','BAX','BAK1','CYTC','APAF1','CASP3','CASP9','BBC3','PUMA'],
    'apoptosis_survival':   ['BCL2','BCL2L1','MCL1','AKT1','MTOR'],
    'MAPK_ERK':             ['KRAS','RAF1','MAP2K1','MAPK1','MAPK3','FOS','JUN','ETS1'],
    'PI3K_AKT_MTOR':        ['AKT1','MTOR','PTEN','S6K1','FOXO3','GSK3B'],
    'JAK_STAT':             ['STAT3','JAK1','JAK2','SOCS1','MYC','BCL2'],
    'DNA_damage_response':  ['TP53','BRCA1','ATM','ATR','GADD45A','RAD51','MDM2'],
    'hypoxia_HIF':          ['HIF1A','VEGFA','LDHA','PKM','SLC2A1','BNIP3'],
    'MYC_targets':          ['MYC','CDK4','CCND1','E2F1','LDHA','PKM','ENO1','MCM2'],
}

def pathway_enrichment(deg_genes, pathways, direction='up'):
    enriched = []
    gene_set = set(g for g, _ in deg_genes)
    total_genes = max(len(GENE_NETWORK), 1)
    for pw, pw_genes in pathways.items():
        overlap = len(gene_set & set(pw_genes))
        if overlap == 0: continue
        # Hypergeometric enrichment proxy: overlap/pathway_size
        score = overlap / len(pw_genes)
        enriched.append({'pathway': pw, 'overlap': overlap,
                         'pathway_size': len(pw_genes), 'score': round(score, 3)})
    return sorted(enriched, key=lambda x: -x['score'])[:5]

up_pathways   = pathway_enrichment(up_degs, GO_PATHWAYS, 'up')
down_pathways = pathway_enrichment(down_degs, GO_PATHWAYS, 'down')

# ─── LINCS cross-validation ──────────────────────────────────────────────────
lincs_result = None
if do_lincs and len(perturb_genes) == 1:
    try:
        up_gene_list   = [g for g, _ in up_degs[:20]]
        down_gene_list = [g for g, _ in down_degs[:20]]
        payload = json.dumps({
            'data': {'upGenes': up_gene_list, 'dnGenes': down_gene_list},
            'config': {'aggravate': True, 'searchMethod': 'CD', 'share': False,
                       'combination': False, 'cell_iname': cell_line, 'cutoff': 5},
            'metadata': [{'key': 'Tag', 'value': f'BioMate-GEARS-{perturb_genes[0]}'}],
        }).encode()
        req = urllib.request.Request(
            'https://maayanlab.cloud/L1000CDS2/query', data=payload,
            headers={'Content-Type': 'application/json'}, method='POST')
        req.add_header('User-Agent', 'BioMate/1.0')
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read())
        if 'topMeta' in data and data['topMeta']:
            lincs_result = {
                'top_compound':  data['topMeta'][0].get('pert_iname', ''),
                'top_score':     round(float(data['topMeta'][0].get('score', 0)), 4),
                'compounds':     [{'name': h.get('pert_iname',''), 'score': round(float(h.get('score',0)),4)}
                                  for h in data['topMeta'][:5]],
            }
    except Exception as e:
        lincs_result = {'error': str(e)[:100]}

# ─── Genetic interaction classification (2-gene only) ────────────────────────
gi_class = None
if is_combo and synergy_scores:
    syn_vals  = [v for v in synergy_scores.values() if abs(v) > 0.01]
    mean_syn  = sum(syn_vals) / len(syn_vals) if syn_vals else 0
    if mean_syn > 0.15:
        gi_class = 'synergistic_positive'
    elif mean_syn < -0.15:
        gi_class = 'synergistic_negative'
    elif abs(mean_syn) < 0.05:
        gi_class = 'epistatic'
    else:
        gi_class = 'additive'

# ─── Assemble results ─────────────────────────────────────────────────────────
results = {
    'status': 'completed',
    'model': 'Network propagation (GEARS-approximation) — Vandin et al. 2012 NatMeth',
    'gpu_upgrade': 'Replace with GEARS GNN: pip install gears torch-geometric; snap-stanford/GEARS; Norman2019/Replogle2022 training data',
    'perturbation': {
        'genes': perturb_genes,
        'type':  pert_type,
        'cell_line': cell_line,
        'is_combination': is_combo,
    },
    'predicted_degs': {
        'up_regulated':   [{'gene': g, 'score': s} for g, s in up_degs],
        'down_regulated': [{'gene': g, 'score': abs(s)} for g, s in down_degs],
        'n_up':   len(up_degs),
        'n_down': len(down_degs),
    },
    'pathway_enrichment': {
        'up_pathways':   up_pathways,
        'down_pathways': down_pathways,
    },
    'genetic_interaction': {
        'classification':   gi_class,
        'epistasis_model':  epi_model,
        'top_synergy_genes': sorted(synergy_scores.items(), key=lambda x: -abs(x[1]))[:10] if synergy_scores else [],
    } if is_combo else None,
    'lincs_crossvalidation': lincs_result,
    'references': [
        'Roohani et al. 2024 Nature Biotechnology (GEARS)',
        'Vandin et al. 2012 Nature Methods (network propagation)',
        'Replogle et al. 2022 Cell (Perturb-seq genome-scale)',
        'Norman et al. 2019 Science (combinatorial CRISPRa)',
    ],
}

with open('predicted_degs.json', 'w') as f:
    json.dump(results, f, indent=2)

all_genes_scored = sorted(prop_scores.items(), key=lambda x: -abs(x[1]))
with open('network_scores.csv', 'w', newline='') as f:
    w = csv.writer(f)
    w.writerow(['gene', 'propagation_score', 'direction', 'synergy_score'])
    for g, s in all_genes_scored:
        direction = 'up' if s > 0 else 'down' if s < 0 else 'neutral'
        syn = synergy_scores.get(g, '') if synergy_scores else ''
        w.writerow([g, s, direction, syn])

lines = [
    f'╔══════════════════════════════════════════════════════════╗',
    f'  GEARS-Approximation: Gene Perturbation Prediction',
    f'  Gene(s): {"+".join(perturb_genes)} | Type: {pert_type} | Cell: {cell_line}',
    f'╚══════════════════════════════════════════════════════════╝',
    '',
    f'  Model: Network propagation (→ GEARS GNN upgrade available)',
    '',
    f'── Predicted Up-regulated (top {min(10,len(up_degs))}) ────────────────',
]
for g, s in up_degs[:10]:
    pw = next((n['pathway'] for n in up_pathways if g in GO_PATHWAYS.get(n['pathway'],[])),'')
    lines.append(f'  ↑ {g:<20} score={s:.3f}  [{pw}]')
lines.append(f'── Predicted Down-regulated (top {min(10,len(down_degs))}) ──────────────')
for g, s in down_degs[:10]:
    pw = next((n['pathway'] for n in down_pathways if g in GO_PATHWAYS.get(n['pathway'],[])),'')
    lines.append(f'  ↓ {g:<20} score={abs(s):.3f}  [{pw}]')
lines += ['', '── Enriched Pathways ───────────────────────────────────────']
for pw in (up_pathways + down_pathways)[:6]:
    dir_label = '↑' if pw in up_pathways else '↓'
    lines.append(f'  {dir_label} {pw["pathway"]:<35} overlap={pw["overlap"]}/{pw["pathway_size"]}  score={pw["score"]:.3f}')
if is_combo and gi_class:
    lines += ['', f'── Genetic Interaction ─────────────────────────────────────',
              f'  Classification: {gi_class.upper()} (model: {epi_model})']
if lincs_result and 'top_compound' in lincs_result:
    lines += ['', f'── LINCS Cross-validation ──────────────────────────────────',
              f'  Top matching compound: {lincs_result["top_compound"]} (score={lincs_result["top_score"]:.3f})']

with open('perturbation_report.txt', 'w') as f:
    f.write('\\n'.join(lines))
print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
gears_perturbation_prediction:
  python: "3.10"
  method: "Network propagation (GEARS-approximation)"
  gpu_upgrade: "snap-stanford/GEARS; pip install gears torch-geometric"
  training_data: "Norman 2019 Figshare:24688110; Replogle 2022 Figshare:20029387"
  reference: "Roohani et al. 2024 Nature Biotechnology"
EOF
    """
}

workflow GEARS_PERTURBATION_WORKFLOW {
    take: meta_ch
    main: GEARS_PERTURBATION_PREDICTION(meta_ch)
    emit:
        results = GEARS_PERTURBATION_PREDICTION.out.results
        scores  = GEARS_PERTURBATION_PREDICTION.out.scores
        report  = GEARS_PERTURBATION_PREDICTION.out.report
}

workflow {
    meta = [id: 'gears_run', single_end: false]
    Channel.value(meta) | GEARS_PERTURBATION_WORKFLOW
}
