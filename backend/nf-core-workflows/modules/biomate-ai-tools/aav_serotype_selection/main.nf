#!/usr/bin/env nextflow
/*
 * drug_discovery/aav_serotype_selection
 *
 * Rules-based AAV serotype selection for in vivo gene therapy delivery.
 * Maps target tissue to optimal serotypes by transduction efficiency,
 * filters by immunogenicity (human seroprevalence / neutralizing antibodies),
 * checks payload size vs 4.7 kb AAV packaging limit, validates
 * route-of-administration compatibility, and outputs the top-3 serotypes
 * with clinical precedent citations.
 *
 * Serotype library:
 *   AAV1:      muscle (high), CNS (moderate), cardiac (moderate)
 *   AAV2:      retina (high; Luxturna), CNS (moderate), muscle (moderate)
 *   AAV5:      CNS (high), liver (high), lung (moderate)
 *   AAV6:      muscle (very high), cardiac (high), lung (moderate)
 *   AAV8:      liver (very high; Hemgenix-related), muscle (high)
 *   AAV9:      CNS (very high; Zolgensma), cardiac (high), systemic BBB crossing
 *   AAV-DJ:    liver (very high; research), broad tropism
 *   AAVrh10:   CNS (high), liver (moderate), good systemic CNS penetration
 *   AAVrh74:   muscle (very high; Elevidys for Duchenne)
 *   AAV-PHP.B: CNS (exceptional in mouse; human seroprevalence unknown)
 *   AAV-PHP.eB:CNS neurons (exceptional in mouse; human translation uncertain)
 *
 * Immunogenicity (pre-existing neutralizing antibodies, human population):
 *   AAV2:   50-60% (HIGH)  AAV9: 30-50% (MEDIUM)  AAV1: 30-40% (MEDIUM)
 *   AAV8:   20-30% (MEDIUM-LOW)  AAV5: 10-15% (LOW)
 *   AAVrh10: ~15% (LOW)  AAVrh74: 5-10% (LOW — preferred for muscle)
 *
 * Packaging capacity: ~4.7 kb hard limit
 *   Oversized 4.7-8 kb: dual-vector split-intein approach
 *   >8 kb: not feasible — recommend lentivirus or non-viral delivery
 *
 * Input parameters:
 *   target_tissue          — liver | cns | muscle | retina | heart | lung | systemic
 *   payload_size_kb        — size of gene of interest in kb (required)
 *   route_of_administration — iv | intrathecal | intramuscular | subretinal | intravitreal (default: iv)
 *   indication             — free text; used to suggest clinical precedent (optional)
 *
 * Outputs:
 *   aav_selection_report.json  — full serotype evaluation with scores + rationale
 *   serotype_ranking.csv       — ranked table of all evaluated serotypes
 *   delivery_summary.txt       — human-readable delivery recommendation
 *
 * References:
 *   - Nathwani et al. 2011 N Engl J Med (AAV8 hemophilia liver)
 *   - Mendell et al. 2017 N Engl J Med (AAV9 SMA — Zolgensma)
 *   - Russell et al. 2017 Lancet (AAV2 RPE65 — Luxturna)
 *   - Mendell et al. 2023 Nat Med (AAVrh74 Elevidys — Duchenne)
 *   - Al-Zaidy et al. 2019 Mol Ther (AAV9 SMA1 dose escalation)
 *   - Rurik et al. 2022 Science (in vivo CAR-T mRNA LNP, context)
 *   - Deverman et al. 2016 Nature Biotechnol (PHP.B CNS)
 *   - Chan et al. 2017 Nature Neurosci (PHP.eB)
 *   - Boutin et al. 2010 Hum Gene Ther (AAV seroprevalence survey)
 *   - Fitzpatrick et al. 2018 Nat Med (AAV9 seroprevalence + safety)
 */

nextflow.enable.dsl = 2

params.outdir                   = './results'
params.target_tissue            = 'muscle'    // liver | cns | muscle | retina | heart | lung | systemic
params.payload_size_kb          = '3.5'       // gene of interest size in kb
params.route_of_administration  = 'iv'        // iv | intrathecal | intramuscular | subretinal | intravitreal
params.indication               = 'null'      // optional free-text indication

// [Phase A] AAV Serotype Selection
process AAV_SEROTYPE_SELECTION {
    tag "aav_serotype"
    label 'process_low'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' \
        ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' \
        : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("aav_selection_report.json"),  emit: report_json
    tuple val(meta), path("serotype_ranking.csv"),        emit: ranking_csv
    tuple val(meta), path("delivery_summary.txt"),        emit: summary_txt
    path "versions.yml",                                   emit: versions

    script:
    """
    export PARAM_TISSUE='${params.target_tissue}'
    export PARAM_PAYLOAD='${params.payload_size_kb}'
    export PARAM_ROUTE='${params.route_of_administration}'
    export PARAM_INDICATION='${params.indication}'

    python3 << 'PYEOF'
import json, os, csv

# ─── Parameters ──────────────────────────────────────────────────────────────
tissue      = os.environ.get('PARAM_TISSUE', 'muscle').lower().strip()
payload_kb  = float(os.environ.get('PARAM_PAYLOAD', '3.5') or '3.5')
route       = os.environ.get('PARAM_ROUTE', 'iv').lower().strip()
indication  = os.environ.get('PARAM_INDICATION', '').strip()
if indication in ('null', ''):
    indication = None

# ─── Serotype database ────────────────────────────────────────────────────────
# Transduction efficiency: 0=none, 1=low, 2=moderate, 3=high, 4=very high, 5=exceptional
SEROTYPES = {
    'AAV1': {
        'tropism': {
            'muscle': 3, 'cns': 2, 'heart': 2, 'liver': 1, 'lung': 2,
            'retina': 1, 'systemic': 1,
        },
        'seroprevalence_pct': 35,       # ~30-40%
        'immunogenicity': 'MEDIUM',
        'clinical_precedent': 'Glybera (alipogene tiparvovec) — first gene therapy EU approval 2012; muscle LPL deficiency',
        'notes': 'Strong muscle and cardiac tropism. Cross-reacts with AAV6. Intramuscular standard for limb-girdle MDs.',
        'manufacturing': 'Well-established; baculovirus + Sf9 or triple plasmid HEK293',
    },
    'AAV2': {
        'tropism': {
            'retina': 4, 'cns': 2, 'muscle': 2, 'liver': 2,
            'lung': 1, 'heart': 1, 'systemic': 1,
        },
        'seroprevalence_pct': 55,       # ~50-60% — HIGHEST
        'immunogenicity': 'HIGH',
        'clinical_precedent': 'Luxturna (voretigene neparvovec, AAV2-RPE65) — FDA approved 2017 for Leber congenital amaurosis',
        'notes': 'HIGHEST seroprevalence (50-60%). Excellent for subretinal injection (immune-privileged). Avoid IV in seropositive patients.',
        'manufacturing': 'Most studied; triple plasmid HEK293; large-scale validated',
    },
    'AAV5': {
        'tropism': {
            'cns': 3, 'liver': 3, 'lung': 2, 'muscle': 2,
            'retina': 2, 'heart': 1, 'systemic': 2,
        },
        'seroprevalence_pct': 12,       # ~10-15% — LOW
        'immunogenicity': 'LOW',
        'clinical_precedent': 'Hemgenix (etranacogene dezaparvovec, AAV5-FIX) — FDA approved 2022 for Hemophilia B',
        'notes': 'Lowest seroprevalence after rh74. Preferred for systemic delivery. Liver + CNS dual tropism.',
        'manufacturing': 'Baculovirus/Sf9 scalable; Uniqure/uniQure process validated',
    },
    'AAV6': {
        'tropism': {
            'muscle': 4, 'heart': 4, 'lung': 2, 'cns': 1,
            'liver': 1, 'retina': 1, 'systemic': 1,
        },
        'seroprevalence_pct': 25,
        'immunogenicity': 'MEDIUM',
        'clinical_precedent': 'Preclinical cardiac gene therapy (e.g., SERCA2a delivery); muscle ex vivo editing',
        'notes': 'Superior muscle and cardiac transduction. Closely related to AAV1. Very high efficiency for IM delivery.',
        'manufacturing': 'Triple plasmid HEK293; cross-reactive manufacturing with AAV1',
    },
    'AAV8': {
        'tropism': {
            'liver': 4, 'muscle': 3, 'heart': 2, 'cns': 1,
            'retina': 1, 'lung': 1, 'systemic': 2,
        },
        'seroprevalence_pct': 25,       # ~20-30%
        'immunogenicity': 'MEDIUM-LOW',
        'clinical_precedent': 'Nathwani 2011 NEnglJMed (AAV8-FVIII hemophilia A); BioMarin valoctocogene roxaparvovec (Roctavian, 2023)',
        'notes': 'Gold standard for liver-directed gene therapy. ApoE-LDLR uptake. 1e12-1e13 vg/kg IV.',
        'manufacturing': 'Triple plasmid HEK293 or baculovirus; widely available CROs',
    },
    'AAV9': {
        'tropism': {
            'cns': 5, 'heart': 4, 'muscle': 4, 'liver': 3,
            'lung': 2, 'systemic': 4, 'retina': 2,
        },
        'seroprevalence_pct': 40,       # ~30-50%
        'immunogenicity': 'MEDIUM',
        'clinical_precedent': 'Zolgensma (onasemnogene abeparvovec, AAV9-SMN1) — FDA approved 2019 for SMA1; highest priced drug at approval',
        'notes': 'Crosses BBB when delivered IV (especially in neonates/infants). Highest CNS + cardiac tropism. High dose (2e14 vg/kg) toxicity risk.',
        'manufacturing': 'Commercial CROs (AveXis/Novartis, Spark); large-scale HEK293 validated',
    },
    'AAV-DJ': {
        'tropism': {
            'liver': 4, 'muscle': 2, 'cns': 1, 'heart': 2,
            'lung': 1, 'retina': 1, 'systemic': 2,
        },
        'seroprevalence_pct': 20,
        'immunogenicity': 'MEDIUM',
        'clinical_precedent': 'Research use; hybrid capsid (AAV2/8/9). High liver transduction in vitro and mouse.',
        'notes': 'Engineered hybrid. Broad tropism. Limited clinical data. Good for research + proof-of-concept.',
        'manufacturing': 'Stanford-derived; available from Addgene; CRO scale-up limited',
    },
    'AAVrh10': {
        'tropism': {
            'cns': 3, 'liver': 2, 'muscle': 2, 'heart': 2,
            'lung': 1, 'retina': 2, 'systemic': 3,
        },
        'seroprevalence_pct': 15,
        'immunogenicity': 'LOW',
        'clinical_precedent': 'Clinical trials for neuronal ceroid lipofuscinosis (Batten disease), MPS-I CNS; Lysogene LAL-R01',
        'notes': 'Good systemic CNS penetration after IV. Low seroprevalence. Alternative to AAV9 for repeat dosing.',
        'manufacturing': 'Triple plasmid HEK293; several CROs offer production',
    },
    'AAVrh74': {
        'tropism': {
            'muscle': 5, 'heart': 3, 'cns': 1, 'liver': 1,
            'lung': 1, 'retina': 1, 'systemic': 1,
        },
        'seroprevalence_pct': 7,        # ~5-10% — very LOW
        'immunogenicity': 'LOW',
        'clinical_precedent': 'Elevidys (delandistrogene moxeparvovec, AAVrh74-MICRO-DYSTROPHIN) — FDA approved 2023 for Duchenne muscular dystrophy',
        'notes': 'Lowest seroprevalence among commonly used serotypes. Preferred for muscle gene therapy. IV systemic muscle delivery at high titer.',
        'manufacturing': 'Solid Biosciences / Sarepta process; commercial CROs scaling up',
    },
    'AAV-PHP.B': {
        'tropism': {
            'cns': 5, 'muscle': 1, 'liver': 2, 'heart': 1,
            'lung': 1, 'retina': 2, 'systemic': 2,
        },
        'seroprevalence_pct': 30,       # unknown in humans — using conservative estimate
        'immunogenicity': 'UNKNOWN (human data limited)',
        'clinical_precedent': 'Preclinical only (mouse). Deverman et al. 2016 Nature Biotechnol. Exceptional CNS tropism in C57BL/6 mice.',
        'notes': 'CAUTION: LY6A receptor-mediated CNS crossing is mouse-specific (C57BL/6). Does NOT extrapolate to primates or humans. Human clinical use NOT established.',
        'manufacturing': 'Research use; not GMP-validated for human trials',
    },
    'AAV-PHP.eB': {
        'tropism': {
            'cns': 5, 'muscle': 1, 'liver': 1, 'heart': 1,
            'lung': 1, 'retina': 2, 'systemic': 1,
        },
        'seroprevalence_pct': 30,       # unknown in humans
        'immunogenicity': 'UNKNOWN (human data limited)',
        'clinical_precedent': 'Preclinical only (mouse). Chan et al. 2017 Nature Neurosci. Superior neuronal transduction in mice.',
        'notes': 'CAUTION: Same LY6A receptor limitation as PHP.B — mouse-specific. Enhanced neuron vs glia tropism vs PHP.B. Human translation highly uncertain.',
        'manufacturing': 'Research use; not GMP-validated for human trials',
    },
}

# ─── Route compatibility ──────────────────────────────────────────────────────
# {route: {serotype: compatible (True/False/note)}}
ROUTE_COMPAT = {
    'iv': ['AAV8', 'AAV9', 'AAV5', 'AAV-DJ', 'AAVrh10', 'AAVrh74', 'AAV1', 'AAV6',
           'AAV-PHP.B', 'AAV-PHP.eB'],  # all can be delivered IV
    'intrathecal': ['AAV9', 'AAVrh10', 'AAV5', 'AAV1', 'AAV2'],
    'intramuscular': ['AAV1', 'AAV6', 'AAVrh74', 'AAV8', 'AAV9', 'AAV5'],
    'subretinal': ['AAV2', 'AAV5', 'AAV8', 'AAVrh10'],
    'intravitreal': ['AAV2', 'AAV9', 'AAV7M8', 'AAV-DJ'],
}

# ─── Clinical precedent mapping ───────────────────────────────────────────────
INDICATION_HINTS = {
    'sma': {'preferred': 'AAV9', 'note': 'Zolgensma (SMA1) — AAV9-SMN1, FDA 2019'},
    'sma1': {'preferred': 'AAV9', 'note': 'Zolgensma (SMA1) — AAV9-SMN1, FDA 2019'},
    'duchenne': {'preferred': 'AAVrh74', 'note': 'Elevidys — AAVrh74-MICRO-DYSTROPHIN, FDA 2023'},
    'dmd': {'preferred': 'AAVrh74', 'note': 'Elevidys — AAVrh74-MICRO-DYSTROPHIN, FDA 2023'},
    'hemophilia': {'preferred': 'AAV5', 'note': 'Hemgenix (HemB) — AAV5-FIX, FDA 2022; Roctavian (HemA) — AAV5-FVIII'},
    'hemophilia b': {'preferred': 'AAV5', 'note': 'Hemgenix — AAV5-FIX-Padua, FDA 2022'},
    'hemophilia a': {'preferred': 'AAV5', 'note': 'Roctavian — AAV5-FVIII-SQ, BLA 2023'},
    'lca': {'preferred': 'AAV2', 'note': 'Luxturna — AAV2-RPE65, FDA 2017'},
    'rpe65': {'preferred': 'AAV2', 'note': 'Luxturna — AAV2-RPE65, FDA 2017'},
    'retina': {'preferred': 'AAV2', 'note': 'Luxturna (RPE65) — AAV2 gold standard for subretinal'},
    'batten': {'preferred': 'AAVrh10', 'note': 'CLN2/Batten — CNS intrathecal AAVrh10 trials (Lysogene)'},
    'mps': {'preferred': 'AAVrh10', 'note': 'MPS-I/II CNS trials — AAVrh10 intrathecal'},
    'parkinson': {'preferred': 'AAV9', 'note': 'Parkinson/GDNF — AAV9 or AAVrh10 intracranial; Braak staging relevant'},
}

# ─── Step 1: Map tissue → ranked serotypes ────────────────────────────────────
def score_serotype(name, data, tissue, route, payload_kb):
    """Compute composite ranking score for a serotype."""
    # Base tropism score (0-5)
    tropism = data['tropism'].get(tissue, 0)

    # Immunogenicity penalty
    imm_penalty = {
        'HIGH': -3,
        'MEDIUM': -1,
        'MEDIUM-LOW': -0.5,
        'LOW': 0,
        'UNKNOWN (human data limited)': -1,
    }.get(data['immunogenicity'], -1)

    # Route compatibility bonus
    route_compatible = name in ROUTE_COMPAT.get(route, [])
    route_bonus = 1 if route_compatible else -2

    # Payload penalty
    if payload_kb > 8.0:
        payload_penalty = -10  # not feasible
    elif payload_kb > 4.7:
        payload_penalty = -2   # oversized → dual vector needed
    else:
        payload_penalty = 0

    # PHP.B/eB human translation warning penalty
    if 'PHP' in name:
        php_penalty = -3  # mouse-specific; human unknown
    else:
        php_penalty = 0

    total = tropism * 2 + imm_penalty + route_bonus + payload_penalty + php_penalty
    return round(total, 2)

ranked = []
for name, data in SEROTYPES.items():
    score = score_serotype(name, data, tissue, route, payload_kb)
    tropism_val = data['tropism'].get(tissue, 0)
    tropism_label = {0: 'none', 1: 'low', 2: 'moderate', 3: 'high', 4: 'very high', 5: 'exceptional'}.get(tropism_val, '?')
    route_compat = name in ROUTE_COMPAT.get(route, [])
    payload_ok = payload_kb <= 4.7
    payload_note = 'OK' if payload_ok else ('dual-vector required' if payload_kb <= 8.0 else 'NOT FEASIBLE')

    ranked.append({
        'serotype': name,
        'tissue_tropism': tropism_label,
        'tropism_score': tropism_val,
        'seroprevalence_pct': data['seroprevalence_pct'],
        'immunogenicity': data['immunogenicity'],
        'route_compatible': route_compat,
        'payload_note': payload_note,
        'composite_score': score,
        'clinical_precedent': data['clinical_precedent'],
        'notes': data['notes'],
        'manufacturing': data.get('manufacturing', ''),
    })

ranked.sort(key=lambda x: -x['composite_score'])

# Top 3
top3 = [r for r in ranked if r['tissue_tropism'] != 'none'][:3]
if not top3:
    top3 = ranked[:3]

# ─── Step 5: Payload capacity check ──────────────────────────────────────────
if payload_kb > 8.0:
    payload_strategy = {
        'status': 'NOT_FEASIBLE_WITH_AAV',
        'payload_kb': payload_kb,
        'limit_kb': 4.7,
        'recommendation': 'Payload exceeds 8 kb — AAV dual-vector approach not practical. Consider lentiviral vector (8-10 kb), gutless adenovirus (up to 36 kb), or non-viral nanoparticles.',
        'alternatives': ['Lentiviral vector (VSV-G pseudotyped; 8-10 kb insert)', 'Gutless adenovirus (up to 36 kb)', 'LNP-mRNA (no size limit, transient)', 'CRISPR base/prime editor split across two vectors'],
    }
elif payload_kb > 4.7:
    payload_strategy = {
        'status': 'OVERSIZED_DUAL_VECTOR',
        'payload_kb': payload_kb,
        'limit_kb': 4.7,
        'recommendation': f'Payload {payload_kb} kb exceeds 4.7 kb limit. Use dual-vector split-intein approach (Trapani et al. 2014, Colella et al. 2018).',
        'split_intein_options': [
            'Npu DnaE intein (fastest, ~17% efficiency at splice junction)',
            'Ssp DnaE intein (slower but well-characterized)',
            'Trans-splicing: AP + SD/SA signals (for large CDSs)',
        ],
        'references': ['Trapani et al. 2014 EMBO Mol Med', 'Colella et al. 2018 Mol Ther Methods Clin Dev'],
    }
else:
    payload_strategy = {
        'status': 'OK',
        'payload_kb': payload_kb,
        'limit_kb': 4.7,
        'note': f'Payload {payload_kb} kb is within AAV 4.7 kb packaging capacity. Single-vector delivery feasible.',
    }

# ─── Indication hint ──────────────────────────────────────────────────────────
indication_hint = None
if indication:
    for key, hint in INDICATION_HINTS.items():
        if key in indication.lower():
            indication_hint = hint
            break

# ─── Compile report ───────────────────────────────────────────────────────────
report = {
    'status': 'completed',
    'pipeline': 'aav_serotype_selection',
    'inputs': {
        'target_tissue': tissue,
        'payload_size_kb': payload_kb,
        'route_of_administration': route,
        'indication': indication,
    },
    'payload_capacity': payload_strategy,
    'top_3_serotypes': top3,
    'all_serotypes_ranked': ranked,
    'indication_hint': indication_hint,
    'immunogenicity_note': (
        'Pre-existing neutralizing antibodies (NAbs) are common in the human population. '
        'Seroprevalence varies by geography (higher in Asia/Africa). '
        'Patient screening for NAbs (ELISA or cell-based neutralization assay) is required before '
        'systemic administration. Seropositive patients may need empty capsid pretreatment, '
        'immunosuppression, or alternative serotype.'
    ),
    'high_dose_safety_note': (
        'High-dose AAV9 (>1e14 vg/kg) has been associated with acute liver toxicity and thrombotic '
        'microangiopathy in patients and NHP. Zolgensma Black Box Warning (FDA 2021). '
        'Dose escalation with corticosteroid prophylaxis required for systemic CNS delivery.'
    ),
    'references': [
        'Nathwani et al. 2011 N Engl J Med 365:2357 (AAV8 hemophilia)',
        'Mendell et al. 2017 N Engl J Med 377:1713 (AAV9 SMA / Zolgensma)',
        'Russell et al. 2017 Lancet 390:849 (AAV2 RPE65 / Luxturna)',
        'Mendell et al. 2023 Nat Med 29:1173 (AAVrh74 Elevidys / DMD)',
        'Deverman et al. 2016 Nature Biotechnol 34:204 (PHP.B CNS)',
        'Boutin et al. 2010 Hum Gene Ther 21:704 (seroprevalence survey)',
        'Fitzpatrick et al. 2018 Nat Med 24:1804 (AAV9 seroprevalence + clinical)',
        'Trapani et al. 2014 EMBO Mol Med 6:194 (dual-vector split-intein)',
    ],
}

# ─── Write outputs ────────────────────────────────────────────────────────────
with open('aav_selection_report.json', 'w') as f:
    json.dump(report, f, indent=2)

CSV_COLS = ['serotype', 'tissue_tropism', 'seroprevalence_pct', 'immunogenicity',
            'route_compatible', 'payload_note', 'composite_score', 'clinical_precedent']
with open('serotype_ranking.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=CSV_COLS, extrasaction='ignore')
    w.writeheader()
    w.writerows(ranked)

# Human-readable delivery summary
bar = '═' * 66
lines = [
    f'╔{bar}╗',
    f'  AAV Serotype Selection Report',
    f'  Tissue: {tissue.upper()}  |  Payload: {payload_kb} kb  |  Route: {route}',
    f'╚{bar}╝',
    '',
    f'── Payload Capacity ──────────────────────────────────────────────',
    f'  Status: {payload_strategy["status"]}',
    f'  Payload: {payload_kb} kb  |  AAV limit: 4.7 kb',
]
if payload_strategy['status'] != 'OK':
    lines.append(f'  ⚠  {payload_strategy.get("recommendation", "")}')
lines += ['', f'── Top 3 Serotypes for {tissue.upper()} (Route: {route}) ───────────']
for i, s in enumerate(top3, 1):
    lines += [
        f'',
        f'  #{i}: {s["serotype"]}',
        f'     Tropism:         {s["tissue_tropism"]} (score {s["tropism_score"]}/5)',
        f'     Seroprevalence:  ~{s["seroprevalence_pct"]}%  ({s["immunogenicity"]})',
        f'     Route ({route}):  {"compatible" if s["route_compatible"] else "NOT recommended"}',
        f'     Payload:         {s["payload_note"]}',
        f'     Composite score: {s["composite_score"]}',
        f'     Precedent:       {s["clinical_precedent"][:80]}',
        f'     Notes:           {s["notes"][:90]}',
    ]

lines += [
    '',
    f'── Immunogenicity Warning ────────────────────────────────────────',
    f'  Screen patients for pre-existing NAbs before IV administration.',
    f'  AAV2 (50-60%) and AAV9 (30-50%) have highest seroprevalence.',
    f'  Preferred low-seroprevalence options: AAVrh74 (~7%), AAV5 (~12%), AAVrh10 (~15%).',
]
if indication_hint:
    lines += [
        '',
        f'── Indication-Specific Guidance ──────────────────────────────────',
        f'  Preferred serotype: {indication_hint["preferred"]}',
        f'  Note: {indication_hint["note"]}',
    ]
lines += [
    '',
    f'── Full Ranking ──────────────────────────────────────────────────',
    f'  {"Serotype":<14} {"Tropism":<14} {"Seroprv%":<10} {"ImmRisk":<14} {"Score":<8} {"Route"}',
    '  ' + '-' * 66,
]
for r in ranked:
    lines.append(
        f'  {r["serotype"]:<14} {r["tissue_tropism"]:<14} {r["seroprevalence_pct"]:<10} '
        f'{r["immunogenicity"]:<14} {r["composite_score"]:<8} {"ok" if r["route_compatible"] else "not ideal"}'
    )

with open('delivery_summary.txt', 'w') as f:
    f.write('\n'.join(lines) + '\n')

print('\n'.join(lines))
PYEOF

    python3 -c "print('aav_serotype_selection: 1.0')" > versions.yml
    """
}

workflow AAV_SEROTYPE_SELECTION_WORKFLOW {
    take: meta_ch
    main: AAV_SEROTYPE_SELECTION(meta_ch)
    emit:
        report_json  = AAV_SEROTYPE_SELECTION.out.report_json
        ranking_csv  = AAV_SEROTYPE_SELECTION.out.ranking_csv
        summary_txt  = AAV_SEROTYPE_SELECTION.out.summary_txt
}

workflow {
    meta = [id: 'aav_serotype_selection_run']
    Channel.value(meta) | AAV_SEROTYPE_SELECTION_WORKFLOW
}
