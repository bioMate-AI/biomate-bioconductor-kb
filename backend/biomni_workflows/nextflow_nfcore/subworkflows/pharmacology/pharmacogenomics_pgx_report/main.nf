#!/usr/bin/env nextflow
/*
 * pharmacology/pharmacogenomics_pgx_report
 *
 * Generates a pharmacogenomics (PGx) clinical report from pre-called
 * diplotype data for key PGx genes, mapping star alleles to CPIC/DPWG
 * phenotype classifications and drug dosing recommendations.
 *
 * Supported genes: CYP2D6, CYP2C19, CYP2C9, CYP3A5, SLCO1B1, TPMT,
 *                  DPYD, UGT1A1, VKORC1, CYP2B6, NUDT15
 *
 * References:
 *   CPIC Guidelines: cpicpgx.org
 *   PharmCAT: Sangkuhl et al. Clin Pharmacol Ther 2021
 *   DPWG Guidelines: pharmgkb.org
 *
 * Input:  diplotypes JSON ({"CYP2D6": "*1/*4", "CYP2C19": "*2/*17", ...})
 *         OR vcf_path with pre-called star alleles
 * Output: pgx_report.json, drug_recommendations.csv, pgx_summary.txt
 */

nextflow.enable.dsl = 2

params.outdir      = './results'
params.diplotypes  = '{"CYP2D6": "*1/*4", "CYP2C19": "*1/*17", "CYP2C9": "*1/*3", "SLCO1B1": "*1/*5", "DPYD": "*1/*1", "TPMT": "*1/*1", "UGT1A1": "*1/*28"}'
params.drug_list   = 'null'   // comma-separated drug names to filter; null = all applicable
params.guidelines  = 'CPIC'   // CPIC | DPWG | both

process PHARMACOGENOMICS_PGX_REPORT {
    tag "$meta.id"
    label 'process_low'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("pgx_results.json"),          emit: results
    tuple val(meta), path("pgx_report.json"),           emit: report
    tuple val(meta), path("drug_recommendations.csv"),  emit: recommendations
    tuple val(meta), path("pgx_summary.txt"),           emit: summary
    path "versions.yml",                                emit: versions

    script:
    """
    export PARAM_DIPLOTYPES='${params.diplotypes}'
    export PARAM_DRUGS='${params.drug_list}'
    export PARAM_GUIDELINES='${params.guidelines}'

    python3 << 'PYEOF'
import json, os, csv, sys

# -- CPIC phenotype classification tables -------------------------------------
# Activity values per allele (0 = no function, 0.5 = decreased, 1 = normal)
# Source: CPIC allele functionality tables (cpicpgx.org/genes)

ALLELE_ACTIVITY = {
    'CYP2D6': {
        '*1':1.0,'*2':1.0,'*3':0,'*4':0,'*5':0,'*6':0,'*7':0,'*8':0,
        '*9':0.5,'*10':0.5,'*17':0.5,'*29':0.5,'*41':0.5,
        '*1xN':2.0,'*2xN':2.0,  # gene duplication
    },
    'CYP2C19': {
        '*1':1.0,'*2':0,'*3':0,'*4':0,'*5':0,'*6':0,'*7':0,'*8':0,
        '*9':0.5,'*10':0.5,'*11':0.5,'*12':0.5,'*13':0.5,
        '*17':1.5,'*18':1.5,  # rapid metabolizer alleles
    },
    'CYP2C9': {
        '*1':1.0,'*2':0.5,'*3':0,'*4':0,'*5':0,'*6':0,'*11':0.5,'*13':0.5,
    },
    'CYP3A5': {
        '*1':1.0,'*3':0,'*6':0,'*7':0,
    },
    'CYP2B6': {
        '*1':1.0,'*2':1.0,'*4':1.5,'*5':0.5,'*6':0.5,'*9':0.5,
        '*11':0.5,'*12':0,'*13':0,'*15':0,'*16':0,'*18':0,
    },
    'DPYD': {
        '*1':1.0,'*2A':0,'*13':0,
        'c.2846A>T':0.5,'c.1129-5923C>G':0.5,
        'c.1236G>A/HapB3':0.5,
    },
    'TPMT': {
        '*1':1.0,'*2':0,'*3A':0,'*3B':0,'*3C':0,'*4':0,'*6':0,
    },
    'NUDT15': {
        '*1':1.0,'*2':0,'*3':0,'*4':0.5,'*5':0.5,'*6':0.5,
    },
    'UGT1A1': {
        '*1':1.0,'*6':0.5,'*28':0.5,'*37':0,'*80':0.5,
    },
    'SLCO1B1': {
        '*1':1.0,'*1a':1.0,'*1b':1.0,'*4':0.5,'*5':0,'*14':0,'*15':0,'*17':0,
        '*2':0.5,'*3':0.5,'*10':0.5,
    },
    'VKORC1': {
        '-1639G>A': 0.5,  # reduced expression -> warfarin sensitive
        '-1639G>G': 1.0,  # normal
        '-1639A>A': 0.25, # very sensitive
    },
}

# -- CPIC Phenotype assignment (from activity score) ------------------------
def get_phenotype(gene, allele1, allele2):
    '''Assign CPIC metabolizer/functional phenotype from two alleles.'''
    act = ALLELE_ACTIVITY.get(gene, {})
    a1 = act.get(allele1, 1.0)  # unknown alleles assumed normal
    a2 = act.get(allele2, 1.0)
    total = a1 + a2

    if gene in ('CYP2D6', 'CYP2C19', 'CYP2C9', 'CYP3A5', 'CYP2B6'):
        if total == 0:            return 'Poor Metabolizer (PM)', total
        elif total < 1.0:         return 'Intermediate Metabolizer (IM)', total
        elif total <= 2.0:        return 'Normal Metabolizer (NM)', total
        else:                     return 'Ultrarapid Metabolizer (UM)', total

    elif gene in ('DPYD', 'TPMT', 'NUDT15'):
        if total == 0:            return 'Poor Function', total
        elif total < 2.0:         return 'Intermediate Function', total
        else:                     return 'Normal Function', total

    elif gene == 'UGT1A1':
        if total == 0:            return 'Poor Function', total
        elif total < 2.0:         return 'Decreased Function', total
        else:                     return 'Normal Function', total

    elif gene == 'SLCO1B1':
        if total == 0:            return 'Poor Function', total
        elif total < 1.5:         return 'Decreased Function', total
        else:                     return 'Normal Function', total

    elif gene == 'VKORC1':
        if total <= 0.5:          return 'Sensitive', total
        elif total <= 1.0:        return 'Intermediate Sensitive', total
        else:                     return 'Normal Sensitive', total

    return 'Indeterminate', total

def parse_diplotype(dip):
    '''Split "*1/*4" -> ("*1","*4"). Handle duplications like "*2xN".'''
    if '/' not in dip:
        return dip, dip
    parts = dip.split('/')
    return parts[0].strip(), parts[1].strip()

# -- CPIC Drug-Gene recommendations ------------------------------------------
# Source: CPIC guideline PDFs + PharmGKB annotations (manually curated subset)
# Format: gene -> phenotype substring -> {drug: recommendation}
CPIC_RECOMMENDATIONS = {
    'CYP2D6': {
        'Poor Metabolizer': {
            'codeine':     ('CONTRAINDICATED', 'Avoid due to lack of efficacy; use non-opioids or morphine'),
            'tramadol':    ('CONTRAINDICATED', 'Avoid; use non-opioid alternatives'),
            'ondansetron': ('Use as directed', 'Normal dosing -- PM may have higher exposure but no dose change required'),
            'tamoxifen':   ('CONTRAINDICATED', 'Use aromatase inhibitor instead; poor endoxifen formation'),
            'amitriptyline':('Reduce dose 50%', 'Select alternative TCA or reduce dose'),
            'nortriptyline':('Reduce dose 50%', 'Select alternative or reduce dose'),
            'metoprolol':  ('Reduce dose 50-75%', 'Increased exposure; use lowest effective dose'),
            'paroxetine':  ('Use with caution', 'PM is the target population; titrate carefully'),
            'venlafaxine': ('Use with caution', 'Reduced conversion to active metabolite'),
        },
        'Ultrarapid Metabolizer': {
            'codeine':     ('CONTRAINDICATED', 'Risk of morphine toxicity; use non-opioids'),
            'tramadol':    ('CONTRAINDICATED', 'Risk of serotonin syndrome/toxicity'),
            'tamoxifen':   ('Use as directed', 'UM produces more endoxifen -- may be beneficial but monitor'),
            'amitriptyline':('Increase dose', 'May need 25-50% higher dose; monitor serum levels'),
            'paroxetine':  ('Increase dose', 'Significantly reduced efficacy; consider alternative SSRI'),
        },
        'Intermediate Metabolizer': {
            'codeine':     ('Use with caution', 'Lower analgesic efficacy; consider dose increase or alternative'),
            'tamoxifen':   ('Recommend alternative', 'Reduced endoxifen; consider aromatase inhibitor'),
        },
    },
    'CYP2C19': {
        'Poor Metabolizer': {
            'clopidogrel':  ('CONTRAINDICATED', 'Avoid; use prasugrel or ticagrelor'),
            'omeprazole':   ('Use as directed', 'Higher exposure but generally safe; consider dose reduction'),
            'pantoprazole': ('Use as directed', 'Higher exposure; standard dosing acceptable'),
            'escitalopram': ('Reduce dose 50%', 'Higher exposure; use lowest effective dose'),
            'citalopram':   ('Reduce dose 50%', 'Higher exposure; max dose 20 mg/day'),
            'voriconazole': ('Reduce dose', 'Higher exposure; monitor for toxicity'),
            'amitriptyline':('Reduce dose 50%', 'Higher TCA exposure; select alternative'),
        },
        'Ultrarapid Metabolizer': {
            'clopidogrel':  ('Use as directed', 'Standard dosing; may have enhanced effect'),
            'voriconazole': ('Increase dose', 'Lower exposure; risk of treatment failure'),
            'omeprazole':   ('Increase dose', 'Reduced efficacy for H. pylori eradication'),
            'escitalopram': ('Use as directed', 'Consider dose increase if subtherapeutic'),
        },
        'Intermediate Metabolizer': {
            'clopidogrel':  ('Use with caution', 'Reduced platelet inhibition; consider alternative'),
            'voriconazole': ('Use with caution', 'Increased variability; therapeutic drug monitoring'),
        },
    },
    'CYP2C9': {
        'Poor Metabolizer': {
            'warfarin':     ('Reduce dose 50-75%', 'Very high bleeding risk; use < 25% usual dose'),
            'phenytoin':    ('Reduce dose 25-50%', 'High toxicity risk; use plasma level monitoring'),
            'celecoxib':    ('Reduce dose 25%', 'Increased exposure; use lowest effective dose'),
            'flurbiprofen': ('Reduce dose', 'Higher NSAID exposure; use caution'),
        },
        'Intermediate Metabolizer': {
            'warfarin':     ('Reduce dose 25-50%', 'Elevated bleeding risk; INR monitoring essential'),
            'phenytoin':    ('Use with caution', 'Monitor plasma levels; may need dose reduction'),
        },
    },
    'CYP3A5': {
        'Poor Function': {
            'tacrolimus':   ('Increase dose 1.5-2x', 'CYP3A5 non-expressors need higher dose; TDM recommended'),
        },
        'Normal Function': {
            'tacrolimus':   ('Reduce dose vs CYP3A5 PM', 'CYP3A5 expressors metabolize faster; usual dose'),
        },
    },
    'DPYD': {
        'Poor Function': {
            '5-fluorouracil':  ('CONTRAINDICATED', 'Severe/fatal toxicity risk; select alternative'),
            'capecitabine':    ('CONTRAINDICATED', 'Prodrug of 5-FU; avoid entirely'),
            'tegafur':         ('CONTRAINDICATED', 'Avoid; severe DPD deficiency'),
        },
        'Intermediate Function': {
            '5-fluorouracil':  ('Reduce dose 50%', 'Start at 50% dose; increase based on tolerance'),
            'capecitabine':    ('Reduce dose 50%', 'Start at 50% dose; monitor for toxicity'),
        },
    },
    'TPMT': {
        'Poor Function': {
            'azathioprine':    ('Reduce dose 10-fold or avoid', 'Bone marrow toxicity; use 10% of usual dose'),
            '6-mercaptopurine':('Reduce dose 10-fold', 'Severe myelosuppression risk'),
            'thioguanine':     ('Reduce dose or avoid', 'Extreme hematologic toxicity risk'),
        },
        'Intermediate Function': {
            'azathioprine':    ('Reduce dose 30-70%', 'Moderate toxicity risk; monitor CBC'),
            '6-mercaptopurine':('Reduce dose 30-50%', 'Monitor CBC; adjust to tolerated dose'),
        },
    },
    'NUDT15': {
        'Poor Function': {
            'azathioprine':    ('Reduce dose or avoid', 'Myelosuppression; combine with TPMT status'),
            '6-mercaptopurine':('Reduce dose 10-fold', 'Severe toxicity; similar to TPMT PM'),
        },
    },
    'UGT1A1': {
        'Poor Function': {
            'irinotecan':   ('Reduce starting dose', 'High risk of severe neutropenia/diarrhea'),
            'atazanavir':   ('Use with caution', 'Hyperbilirubinemia risk; consider alternative PI'),
        },
        'Decreased Function': {
            'irinotecan':   ('Use with caution', 'Moderate neutropenia risk; consider dose reduction'),
        },
    },
    'SLCO1B1': {
        'Poor Function': {
            'simvastatin':  ('Avoid 80 mg; limit to 20 mg', 'High myopathy risk; rosuvastatin preferred'),
            'atorvastatin': ('Use with caution', 'Increased statin exposure; monitor CK'),
            'pravastatin':  ('Use with caution', 'Higher exposure; lower starting dose preferred'),
            'rosuvastatin': ('Use with caution', 'Preferred statin but monitor at high doses'),
        },
        'Decreased Function': {
            'simvastatin':  ('Avoid 80 mg', 'Moderate myopathy risk; limit to 40 mg/day'),
        },
    },
    'VKORC1': {
        'Sensitive': {
            'warfarin':     ('Reduce starting dose 25-50%', 'Very low warfarin dose requirement; INR monitoring critical'),
        },
        'Intermediate Sensitive': {
            'warfarin':     ('Reduce starting dose 10-25%', 'Lower warfarin dose; monitor INR closely'),
        },
    },
}

# -- Main processing -----------------------------------------------------------
raw_dip     = os.environ.get('PARAM_DIPLOTYPES', '{}')
drug_filter = os.environ.get('PARAM_DRUGS', 'null')
guidelines  = os.environ.get('PARAM_GUIDELINES', 'CPIC')

try:
    diplotypes = json.loads(raw_dip)
except:
    print(f"ERROR: Could not parse diplotypes JSON: {raw_dip}", file=sys.stderr)
    diplotypes = {}

drug_filter_list = None
if drug_filter not in ('null','None',''):
    drug_filter_list = [d.strip().lower() for d in drug_filter.split(',')]

# Compute phenotype for each gene
phenotypes = {}
for gene, dip in diplotypes.items():
    a1, a2 = parse_diplotype(dip)
    phenotype, activity_score = get_phenotype(gene, a1, a2)
    phenotypes[gene] = {
        'diplotype': dip,
        'allele1': a1,
        'allele2': a2,
        'activity_score': round(activity_score, 2),
        'phenotype': phenotype,
    }

# Collect drug recommendations
rec_rows    = []
gene_flags  = {}
for gene, pheno_data in phenotypes.items():
    pheno = pheno_data['phenotype']
    gene_recs = CPIC_RECOMMENDATIONS.get(gene, {})
    matched_recs = {}
    for pheno_key, drug_recs in gene_recs.items():
        if pheno_key in pheno:  # substring match (e.g. "Poor" matches "Poor Metabolizer")
            matched_recs.update(drug_recs)

    action_flags = []
    for drug, (action, rationale) in matched_recs.items():
        if drug_filter_list and drug.lower() not in drug_filter_list:
            continue
        is_critical = 'CONTRAINDICATED' in action or 'Reduce dose' in action or 'Avoid' in action
        rec_rows.append({
            'gene': gene,
            'diplotype': pheno_data['diplotype'],
            'phenotype': pheno,
            'drug': drug,
            'recommendation': action,
            'rationale': rationale,
            'cpic_guideline': guidelines,
            'actionable': 'YES' if is_critical else 'INFORMATIONAL',
        })
        if is_critical:
            action_flags.append(f"{drug}: {action}")
    if action_flags:
        gene_flags[gene] = action_flags

# Write recommendations CSV
with open('drug_recommendations.csv', 'w', newline='') as f:
    fn = ['gene','diplotype','phenotype','drug','recommendation','rationale','cpic_guideline','actionable']
    w = csv.DictWriter(f, fieldnames=fn)
    w.writeheader()
    w.writerows(rec_rows)

# Write PGx report JSON
report = {
    'guidelines': guidelines,
    'n_genes_tested': len(phenotypes),
    'phenotypes': phenotypes,
    'n_drug_gene_pairs': len(rec_rows),
    'n_actionable': sum(1 for r in rec_rows if r['actionable'] == 'YES'),
    'n_contraindications': sum(1 for r in rec_rows if 'CONTRAINDICATED' in r['recommendation']),
    'actionable_flags': gene_flags,
}
with open('pgx_report.json', 'w') as f:
    json.dump(report, f, indent=2)

# Full results
full = {**report, 'recommendations': rec_rows, 'status': 'completed'}
with open('pgx_results.json', 'w') as f:
    json.dump(full, f, indent=2)

# Text summary
lines = ["=== PHARMACOGENOMICS (PGx) REPORT ===",
         f"Guidelines: {guidelines}", ""]
for gene, pd in phenotypes.items():
    flag = ' *** ACTIONABLE ***' if gene in gene_flags else ''
    lines.append(f"{gene}: {pd['diplotype']} -> {pd['phenotype']} (AS={pd['activity_score']}){flag}")
    if gene in gene_flags:
        for f_ in gene_flags[gene]:
            lines.append(f"  ! {f_}")
lines += ["", f"Total drug-gene pairs: {len(rec_rows)}",
          f"Actionable pairs: {sum(1 for r in rec_rows if r['actionable']=='YES')}",
          f"Contraindications: {sum(1 for r in rec_rows if 'CONTRAINDICATED' in r['recommendation'])}"]

with open('pgx_summary.txt', 'w') as f:
    f.write('\\n'.join(lines))
print('\\n'.join(lines))
PYEOF

    cat << 'EOF' > versions.yml
pharmacogenomics_pgx_report:
  python: "3.10"
  cpic_version: "2024"
  pharmgkb_version: "2024"
EOF
    """
}

workflow PHARMACOGENOMICS_PGX_WORKFLOW {
    take: meta_ch
    main: PHARMACOGENOMICS_PGX_REPORT(meta_ch)
    emit:
        results         = PHARMACOGENOMICS_PGX_REPORT.out.results
        recommendations = PHARMACOGENOMICS_PGX_REPORT.out.recommendations
        report          = PHARMACOGENOMICS_PGX_REPORT.out.report
}

workflow {
    meta = [id: 'pgx_run', single_end: false]
    Channel.value(meta) | PHARMACOGENOMICS_PGX_WORKFLOW
}
