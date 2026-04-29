#!/usr/bin/env nextflow
/*
 * pharmacology/polymorph_stability_screening
 *
 * Pharmaceutical polymorph risk scoring and solid-state stability prediction
 * for CMC (Chemistry, Manufacturing & Control) package preparation.
 *
 * Computes:
 *   1. Polymorph risk score (LOW/MEDIUM/HIGH) from H-bond capacity, rotatable
 *      bonds, and conformational flexibility -- Fleming (2010) heuristic +
 *      Blagden/Davey (2003) structural alerts.
 *   2. Solid-state stability assessment per ICH Q1A/Q1B:
 *      hygroscopicity (PSA + H-bond features), photostability risk (UV
 *      chromophore detection), chemical degradation pathways (hydrolysis,
 *      oxidation, isomerisation), and thermal stability (MW + melt heuristic).
 *   3. Excipient compatibility risk: flags Maillard (lactose + amine),
 *      MgSt salt formation, and MCC-moisture-catalysed hydrolysis patterns.
 *   4. ICH Q6A-aligned screening protocol recommendation (solvents, temps,
 *      evaporation methods) scaled to the computed risk tier.
 *   5. Accelerated stability condition recommendations per ICH Q1A(R2)
 *      linked to the stability risk profile.
 *
 * Applications: CMC polymorph control strategy, IND/NDA S3.2.S.3 filing,
 * salt/cocrystal selection, API manufacturing process risk assessment.
 *
 * References:
 *   - ICH Q6A (1999) Specifications: test procedures and acceptance criteria
 *   - ICH Q1A(R2) (2003) Stability testing of new drug substances and products
 *   - ICH Q1B (1996) Photostability testing
 *   - Blagden & Davey, Chem Soc Rev 2003, 32, 495-503
 *   - Fleming et al., Org Process Res Dev 2010, 14, 975-991
 *   - Brittain, Polymorphism in Pharmaceutical Solids, 2nd ed. 2009
 *
 * Input:  smiles (drug SMILES string), drug_name, intended_route,
 *         excipients (comma-separated; optional)
 * Output: polymorph_stability_report.json,
 *         polymorph_stability_summary.txt (ICH Q6A narrative),
 *         screening_protocol_recommendation.json
 */

nextflow.enable.dsl = 2

params.outdir         = './results'
params.smiles         = 'CC(=O)Oc1ccccc1C(=O)O'   // aspirin demo
params.drug_name      = 'compound'
params.intended_route = 'oral'
params.excipients     = ''

process POLYMORPH_STABILITY_SCREENING {
    tag "$meta.id"
    label 'process_low'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)

    output:
    tuple val(meta), path("polymorph_stability_report.json"),           emit: results
    tuple val(meta), path("polymorph_stability_summary.txt"),           emit: output
    tuple val(meta), path("screening_protocol_recommendation.json"),    emit: protocol
    path "versions.yml",                                                emit: versions

    script:
    """
    export PARAM_SMILES='${params.smiles}'
    export PARAM_DRUG_NAME='${params.drug_name}'
    export PARAM_ROUTE='${params.intended_route}'
    export PARAM_EXCIPIENTS='${params.excipients}'

    python3 << 'PYEOF'
import json, os, sys, math, re

# ---------------------------------------------------------------------------
# RDKit imports -- available in biomni-tools image
# ---------------------------------------------------------------------------
try:
    from rdkit import Chem
    from rdkit.Chem import Descriptors, rdMolDescriptors, AllChem
    RDKIT_OK = True
except ImportError:
    RDKIT_OK = False
    print("WARNING: RDKit not available -- using SMILES heuristic fallback", file=sys.stderr)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def ac(v, default=None):
    if v in (None, '', 'null', 'None'): return default
    try: return float(v)
    except: return default

def smiles_heuristic_props(smi):
    """Descriptor estimates from SMILES string when RDKit is absent.
    Uses atom-by-atom MW, ring closure counting, and substructure patterns.
    """
    import re as _re
    # Heavy-atom MW (monoisotopic approx.)
    _aw = {'C': 12.011, 'N': 14.007, 'O': 15.999, 'S': 32.06,
           'F': 19.00, 'P': 30.97, 'I': 126.9, 'B': 10.81}
    _aw2 = {'Cl': 35.45, 'Br': 79.9, 'Si': 28.09}
    clean = smi.replace('[NH]','N').replace('[NH2]','N').replace('[OH]','O')
    mw = 0.0
    i, n_atoms = 0, 0
    while i < len(clean):
        if i+1 < len(clean) and clean[i:i+2] in _aw2:
            mw += _aw2[clean[i:i+2]]; n_atoms += 1; i += 2
        elif clean[i] in _aw:
            mw += _aw[clean[i]]; n_atoms += 1; i += 1
        else:
            i += 1
    # Add implicit H (approx: each N/O gets 1 H; Hs already absent from MW)
    mw += n_atoms * 1.008 * 0.5  # rough H correction

    # H-bond donors: N-H patterns
    hbd = (smi.count('[NH]') + smi.count('[NH2]') + smi.count('[NH3]')
           + smi.count('[nH]') + smi.count('[OH]')
           # unbracketed N followed by H not in ring
           + len(_re.findall(r'(?<![a-z])N(?![(=])', smi)))
    hbd = max(0, hbd)
    # H-bond acceptors: O, N atoms
    hba = smi.count('O') + smi.count('o') + smi.count('N') + smi.count('n')
    hba = max(0, hba)
    # Rotatable bonds: C-C, C-N, C-O single bonds not in ring (approx)
    # Bonds in ring: roughly (ring_atoms * 1); non-ring rotatable ~ open-chain C
    rot_raw = max(0, smi.count('C') + smi.count('c') - 4)
    # Ring systems: each unique digit in SMILES = 1 ring closure pair
    ring_digits = set(_re.findall(r'(?<![0-9])([1-9])(?![0-9])', smi))
    n_rings = len(ring_digits)
    # Deduct ring bonds from rotatable count
    rot = max(0, rot_raw - n_rings * 2)
    # Aromatic rings: rings containing lowercase atoms (aromatic SMILES)
    #   OR kekulized aromatic pattern: C=C-C=C ring (benzene-like)
    n_arom = 0
    if 'c' in smi or 'n' in smi or 's' in smi or 'o' in smi:
        # aromatic SMILES notation
        n_arom = max(1, n_rings)
    else:
        # kekulized: count alternating C=C patterns within rings
        if _re.search(r'C1=C[C=c]*C=C[C=c]*1', smi) or (
                '=C' in smi and n_rings >= 1):
            n_arom = n_rings
    has_aromatic = n_arom > 0
    aromatic_rings = n_arom
    # Functional groups
    has_carbonyl = '=O' in smi
    has_amide = bool(_re.search(r'C\(=O\)N|NC\(=O\)', smi))
    has_lactam = bool(_re.search(r'C1[^)]*C\(=O\)N[^)]*1', smi))
    has_acid = bool(_re.search(r'C\(=O\)O|OC\(=O\)', smi))
    n_chiral_centers = smi.count('@')
    tpsa = hbd * 20 + hba * 10
    flex_index = rot / max(1.0, mw / 100.0)
    return {
        'mw': round(mw, 1), 'hbd': hbd, 'hba': hba, 'rotatable_bonds': rot,
        'tpsa': tpsa, 'rings': n_rings, 'aromatic_rings': aromatic_rings,
        'flex_index': round(flex_index, 3),
        'has_carbonyl': has_carbonyl, 'has_aromatic': has_aromatic,
        'has_amide': has_amide, 'has_lactam': has_lactam, 'has_acid': has_acid,
        'n_chiral_centers': n_chiral_centers, 'source': 'heuristic',
    }

# ---------------------------------------------------------------------------
# Molecular descriptor calculation
# ---------------------------------------------------------------------------
def calc_descriptors(smi):
    if not RDKIT_OK:
        return smiles_heuristic_props(smi)

    mol = Chem.MolFromSmiles(smi)
    if mol is None:
        print(f"WARNING: could not parse SMILES '{smi}', using heuristic fallback", file=sys.stderr)
        return smiles_heuristic_props(smi)

    mw   = Descriptors.ExactMolWt(mol)
    hbd  = rdMolDescriptors.CalcNumHBD(mol)
    hba  = rdMolDescriptors.CalcNumHBA(mol)
    rot  = rdMolDescriptors.CalcNumRotatableBonds(mol)
    tpsa = Descriptors.TPSA(mol)
    rings = rdMolDescriptors.CalcNumRings(mol)
    arom  = rdMolDescriptors.CalcNumAromaticRings(mol)
    n_sp3 = rdMolDescriptors.CalcNumAliphaticCarbocycles(mol)

    # Chiral centres
    chiral_info = Chem.FindMolChiralCenters(mol, includeUnassigned=True)
    n_chiral = len(chiral_info)

    # Detect functional groups via SMARTS
    def has_smarts(smarts_str):
        try:
            p = Chem.MolFromSmarts(smarts_str)
            return mol.HasSubstructMatch(p) if p else False
        except Exception:
            return False

    has_carbonyl    = has_smarts('[C;!R]=[O;!R]') or has_smarts('[C;R]=[O;!R]')
    has_aromatic    = arom > 0
    has_ester       = has_smarts('[#6][C](=O)[O][#6]')
    has_lactam      = has_smarts('[NH][C](=O)[#6]')
    has_amide       = has_smarts('[C](=O)[N]')
    has_prim_amine  = has_smarts('[NH2][#6]')
    has_sec_amine   = has_smarts('[NH]([#6])[#6]')
    has_tert_amine  = has_smarts('[N]([#6])([#6])[#6]')
    has_sulfoxide   = has_smarts('[S;X3](=O)')
    has_thioether   = has_smarts('[S;X2]([#6])[#6]')
    has_benzyl_ch   = has_smarts('[cH0,cH1][CH2][#6]') or has_smarts('[c][CH]')
    has_conj_system = arom > 0 and (has_smarts('[c][C]=O') or has_smarts('[C]=[C][C]=O'))

    # Dihedral diversity proxy: fraction of sp3 carbons in non-ring bonds
    try:
        n_sp3_c = sum(1 for a in mol.GetAtoms()
                      if a.GetAtomicNum() == 6 and a.GetHybridization().name == 'SP3')
    except Exception:
        n_sp3_c = 0

    flex_index = rot / max(1, mw / 100.0)   # rotatable bonds per 100 Da

    return {
        'mw': round(mw, 1),
        'hbd': hbd,
        'hba': hba,
        'rotatable_bonds': rot,
        'tpsa': round(tpsa, 1),
        'rings': rings,
        'aromatic_rings': arom,
        'n_chiral_centers': n_chiral,
        'n_sp3_carbons': n_sp3_c,
        'flex_index': round(flex_index, 3),
        'has_carbonyl': has_carbonyl,
        'has_aromatic': has_aromatic,
        'has_ester': has_ester,
        'has_lactam': has_lactam,
        'has_amide': has_amide,
        'has_prim_amine': has_prim_amine,
        'has_sec_amine': has_sec_amine,
        'has_tert_amine': has_tert_amine,
        'has_sulfoxide': has_sulfoxide,
        'has_thioether': has_thioether,
        'has_benzyl_ch': has_benzyl_ch,
        'has_conjugated_chromophore': has_conj_system,
        'source': 'rdkit'
    }

# ---------------------------------------------------------------------------
# 1. Polymorph risk score  (Fleming 2010 + Blagden & Davey 2003)
# ---------------------------------------------------------------------------
def polymorph_risk(d):
    """
    Score from 0-10; tiers: LOW <3, MEDIUM 3-6, HIGH >6.

    Basis:
      * HBD+HBA  -- H-bond network drives crystal packing diversity
      * Rotatable bonds -- flexible molecules adopt multiple conformations
      * Conformational energy landscape proxy (flex_index)
      * MW -- larger molecules have more packing possibilities
      * Aromatic rings -- pi-stacking competition with H-bonds
      * Chiral centres -- each centre doubles possible packing arrangements
    References: Fleming 2010 Table 2; Blagden & Davey 2003 S2
    """
    score = 0.0
    factors = []

    # H-bond network capacity (max 3.0 pts)
    hb_total = d['hbd'] + d['hba']
    if hb_total >= 6:
        score += 3.0; factors.append(f"High H-bond capacity (HBD+HBA={hb_total}) -- diverse H-bond network drives polymorphism [+3.0]")
    elif hb_total >= 4:
        score += 2.0; factors.append(f"Moderate H-bond capacity (HBD+HBA={hb_total}) [+2.0]")
    elif hb_total >= 2:
        score += 1.0; factors.append(f"Low H-bond capacity (HBD+HBA={hb_total}) [+1.0]")

    # Rotatable bond flexibility (max 2.0 pts)
    rot = d['rotatable_bonds']
    if rot >= 8:
        score += 2.0; factors.append(f"High flexibility (rotatable bonds={rot}) -- broad conformational landscape [+2.0]")
    elif rot >= 5:
        score += 1.5; factors.append(f"Moderate flexibility (rotatable bonds={rot}) [+1.5]")
    elif rot >= 3:
        score += 0.5; factors.append(f"Some flexibility (rotatable bonds={rot}) [+0.5]")

    # Conformational energy landscape proxy (flex_index; max 1.0 pt)
    fi = d.get('flex_index', 0.0)
    if fi > 0.5:
        score += 1.0; factors.append(f"Broad conformational energy landscape (flex_index={fi:.2f}) [+1.0]")
    elif fi > 0.25:
        score += 0.5; factors.append(f"Moderate conformational landscape (flex_index={fi:.2f}) [+0.5]")

    # Molecular weight (max 1.5 pts)
    mw = d['mw']
    if mw > 500:
        score += 1.5; factors.append(f"Large MW ({mw:.0f} Da) -- greater packing complexity [+1.5]")
    elif mw > 300:
        score += 0.5; factors.append(f"Mid-range MW ({mw:.0f} Da) [+0.5]")

    # Aromatic system competition (max 1.0 pt)
    arom = d.get('aromatic_rings', 0)
    if arom >= 3:
        score += 1.0; factors.append(f"Multiple aromatic rings ({arom}) -- pi-stack vs H-bond competition promotes polymorphism [+1.0]")
    elif arom >= 1:
        score += 0.5; factors.append(f"Aromatic ring(s) present ({arom}) [+0.5]")

    # Chiral centres (max 1.0 pt; Blagden & Davey 2003 S3.1)
    nc = d['n_chiral_centers']
    if nc >= 2:
        score += 1.0; factors.append(f"Multiple chiral centres ({nc}) -- diastereomeric packing alternatives [+1.0]")
    elif nc == 1:
        score += 0.5; factors.append(f"One chiral centre -- enantiomeric/racemate packing alternatives [+0.5]")

    # Structural alert: amide/lactam H-bond donor-acceptor bridge (Brittain 2009)
    if d.get('has_amide') or d.get('has_lactam'):
        score += 0.5; factors.append("Amide/lactam group -- N-H...O=C H-bond bridge promotes multiple packing modes [+0.5]")

    score = min(score, 10.0)
    if score >= 6.0:
        risk_tier = 'HIGH'
        risk_summary = 'High polymorph risk -- comprehensive solid-form screening is strongly recommended before IND filing (ICH Q6A, item 3.1.1.5)'
    elif score >= 3.0:
        risk_tier = 'MEDIUM'
        risk_summary = 'Moderate polymorph risk -- targeted polymorph screen covering >=15 solvents recommended'
    else:
        risk_tier = 'LOW'
        risk_summary = 'Low polymorph risk -- standard solvent survey (>=8 solvents) at 25 degC and 50 degC recommended'

    return {
        'risk_score': round(score, 1),
        'risk_tier': risk_tier,
        'risk_summary': risk_summary,
        'contributing_factors': factors
    }

# ---------------------------------------------------------------------------
# 2. Solid-state stability assessment  (ICH Q1A/Q1B)
# ---------------------------------------------------------------------------
def solid_state_stability(d):
    results = {}
    warnings = []

    # 2a. Hygroscopicity -- PSA + H-bond features
    tpsa = d['tpsa']
    hb = d['hbd'] + d['hba']
    if tpsa > 100 or hb >= 5:
        hygro = 'HIGH'
        warnings.append('High hygroscopicity risk: PSA>100 A2 or >=5 H-bond groups -- moisture uptake may promote hydrate formation or accelerate hydrolysis')
    elif tpsa > 60 or hb >= 3:
        hygro = 'MODERATE'
        warnings.append('Moderate hygroscopicity: PSA 60-100 A2 -- controlled humidity storage (<=60% RH) recommended')
    else:
        hygro = 'LOW'
    results['hygroscopicity'] = {'class': hygro, 'tpsa_A2': tpsa, 'hb_groups': hb}

    # 2b. Photostability risk -- ICH Q1B chromophore detection
    # UV absorbers: aromatic ring, carbonyl conjugated to aromatic, extended conjugation
    photo_alerts = []
    if d.get('has_conjugated_chromophore'):
        photo_alerts.append('Conjugated carbonyl adjacent to aromatic ring (chromophore, lambda~300-350 nm)')
    if d.get('has_aromatic') and d.get('aromatic_rings', 0) >= 2:
        photo_alerts.append('Polycyclic aromatic system (extended UV absorption)')
    if d.get('has_aromatic'):
        photo_alerts.append('Aromatic ring (UV-active; ICH Q1B Option 1 photostability study required)')
    if photo_alerts:
        photo_risk = 'ELEVATED'
        warnings.append('Photostability flag: UV-absorbing chromophore detected -- ICH Q1B forced photodegradation study mandatory')
    else:
        photo_risk = 'LOW'
    results['photostability'] = {'risk': photo_risk, 'alerts': photo_alerts}

    # 2c. Chemical degradation pathways
    degradation = []
    if d.get('has_ester') or d.get('has_lactam') or d.get('has_amide'):
        paths = []
        if d.get('has_ester'):  paths.append('ester (hydrolysis, t1/2 pH-dependent)')
        if d.get('has_lactam'): paths.append('lactam (ring-opening hydrolysis)')
        if d.get('has_amide'):  paths.append('amide (hydrolysis under acid/base stress)')
        degradation.append({'pathway': 'hydrolysis', 'groups': paths,
                            'condition': 'ICH Q1A 40 degC/75% RH; stressed: 0.1N HCl/NaOH'})
        warnings.append('Hydrolysis risk: ester/lactam/amide present -- moisture-protected packaging required')

    if d.get('has_thioether') or d.get('has_sulfoxide') or d.get('has_tert_amine') or d.get('has_benzyl_ch'):
        paths = []
        if d.get('has_thioether'):  paths.append('thioether -> sulfoxide (autoxidation)')
        if d.get('has_sulfoxide'):  paths.append('sulfoxide -> sulfone')
        if d.get('has_tert_amine'): paths.append('tertiary amine (N-oxide, Meisenheimer oxidation)')
        if d.get('has_benzyl_ch'):  paths.append('benzylic CH (radical/peroxide oxidation)')
        degradation.append({'pathway': 'oxidation', 'groups': paths,
                            'condition': 'stress with 3% H2O2; N2 headspace in final container'})
        warnings.append('Oxidation risk: sulfur/amine/benzylic functionality detected -- antioxidant excipients and inert atmosphere recommended')

    if d['n_chiral_centers'] >= 1 and (d.get('has_carbonyl') or d.get('has_amide')):
        degradation.append({'pathway': 'epimerization / racemization',
                            'groups': ['chiral centre alpha to carbonyl/amide'],
                            'condition': 'ICH Q1A stressed (60 degC, pH 1 and 9)'})
        warnings.append('Epimerisation risk: chiral centre adjacent to electron-withdrawing group -- chiral HPLC in stability spec required')

    results['degradation_pathways'] = degradation

    # 2d. Thermal stability -- MW + melting point heuristic
    # High-MW or highly flexible molecules typically have lower melt points -> lower thermal stability
    mw = d['mw']
    rot = d['rotatable_bonds']
    if mw > 500 and rot >= 6:
        thermal = 'MODERATE_RISK'
        warnings.append('Thermal stability concern: high MW + high flexibility may correlate with low melting point (<150 degC); DSC characterisation recommended')
    elif mw < 200:
        thermal = 'MONITOR'
        warnings.append('Small MW -- verify melting point by DSC; low-MW APIs can have multiple polymorphs with closely spaced melting points')
    else:
        thermal = 'LOW_RISK'
    results['thermal_stability'] = {'assessment': thermal, 'mw_Da': mw, 'rotatable_bonds': rot}

    # Summary risk level
    n_warn = len(warnings)
    if n_warn >= 4:
        stability_class = 'CHALLENGING'
    elif n_warn >= 2:
        stability_class = 'MODERATE'
    else:
        stability_class = 'ACCEPTABLE'

    return {
        'overall_stability_class': stability_class,
        'warnings': warnings,
        'details': results
    }

# ---------------------------------------------------------------------------
# 3. Excipient compatibility risk
# ---------------------------------------------------------------------------
def excipient_compatibility(d, excipients_list):
    flags = []
    if not excipients_list:
        return {'flags': [], 'note': 'No excipients provided; compatibility check skipped'}

    excipients_lower = [e.strip().lower() for e in excipients_list]

    # Maillard reaction: reducing sugar + amine
    reducing_sugars = {'lactose', 'glucose', 'fructose', 'maltose', 'sucrose'}
    has_amine = d.get('has_prim_amine') or d.get('has_sec_amine')
    for exc in excipients_lower:
        for sugar in reducing_sugars:
            if sugar in exc and has_amine:
                flags.append({
                    'excipient': exc,
                    'reaction': 'Maillard browning (reducing sugar + primary/secondary amine)',
                    'risk': 'HIGH',
                    'mitigation': 'Replace lactose/glucose with mannitol or DCPD; or use enteric coating; monitor API degradant by HPLC'
                })

    # Magnesium stearate + acidic API -> salt formation
    mg_st_names = {'magnesium stearate', 'mg stearate', 'mg-stearate', 'magnesium stearate (vegetable)'}
    has_acid = d['tpsa'] > 40 and (d.get('has_ester') or d.get('has_amide') or d['hbd'] >= 1)
    for exc in excipients_lower:
        if exc in mg_st_names and has_acid and d['mw'] < 600:
            flags.append({
                'excipient': 'magnesium stearate',
                'reaction': 'Salt bridge / lubricant-acid interaction -> softening of crystal lattice',
                'risk': 'MODERATE',
                'mitigation': 'Use reduced MgSt level (<=0.5% w/w) or switch to sodium stearyl fumarate (Pruv); minimise blend time'
            })

    # MCC + moisture -> hydrolysis acceleration
    mcc_names = {'microcrystalline cellulose', 'mcc', 'avicel', 'prosolv'}
    if d.get('has_ester') or d.get('has_lactam'):
        for exc in excipients_lower:
            for mcc in mcc_names:
                if mcc in exc:
                    flags.append({
                        'excipient': exc,
                        'reaction': 'MCC moisture (3-5% w/w) accelerates ester/lactam hydrolysis in solid state',
                        'risk': 'MODERATE',
                        'mitigation': 'Dry MCC to <1% moisture before granulation; consider HPMC or calcium phosphate dibasic as filler alternative'
                    })

    # Polyvinylpyrrolidone (PVP) + peroxide impurities -> oxidation
    pvp_names = {'pvp', 'povidone', 'polyvinylpyrrolidone', 'crospovidone', 'plasdone'}
    if d.get('has_thioether') or d.get('has_tert_amine') or d.get('has_benzyl_ch'):
        for exc in excipients_lower:
            for pvp in pvp_names:
                if pvp in exc:
                    flags.append({
                        'excipient': exc,
                        'reaction': 'Peroxide impurities in PVP catalyse oxidation of thioether/amine/benzylic functionality',
                        'risk': 'MODERATE',
                        'mitigation': 'Source low-peroxide PVP (<=400 ppm) and add BHT/BHA antioxidant; consider HPMC as binder replacement'
                    })

    if not flags:
        flags = [{'excipient': 'all listed', 'reaction': 'No high-risk incompatibilities detected',
                  'risk': 'LOW', 'mitigation': 'Standard compatibility confirmation by DSC and XRPD at 25 degC/60%RH and 40 degC/75%RH'}]

    return {'flags': flags}

# ---------------------------------------------------------------------------
# 4. ICH Q6A screening protocol recommendation
# ---------------------------------------------------------------------------
def screening_protocol(poly_result, stab_result, route):
    risk_tier  = poly_result['risk_tier']
    stab_class = stab_result['overall_stability_class']

    # Number of crystallisation solvents -- ICH Q6A Table 1 guidance
    if risk_tier == 'HIGH':
        n_solvents       = 25
        n_temp_points    = 4     # 25, 50, 70 degC + slurry
        methods          = ['slow evaporation', 'anti-solvent addition', 'cooling crystallisation',
                            'vapour diffusion', 'melt-quench recrystallisation', 'slurry equilibration',
                            'mechanical grinding / cogrinding', 'spray drying', 'supercritical CO2']
        priority         = 'CRITICAL -- complete polymorph screen before GMP manufacture; document per ICH Q6A S3.1.1.5'
        n_characterisation = ['XRPD (mandatory)', 'DSC (melting point, Tg)', 'TGA (thermal events)',
                               'DVS (hygroscopicity)', 'hot-stage microscopy', 'Raman/IR solid-state',
                               'solid-state NMR (if ambiguous XRPD)', 'single-crystal X-ray (for novel forms)']
    elif risk_tier == 'MEDIUM':
        n_solvents       = 15
        n_temp_points    = 3     # 25, 50 degC + slurry
        methods          = ['slow evaporation', 'anti-solvent addition', 'cooling crystallisation',
                            'vapour diffusion', 'slurry equilibration']
        priority         = 'RECOMMENDED -- perform polymorph screen during pre-Phase II; update ICH Q6A filing with any new forms'
        n_characterisation = ['XRPD', 'DSC', 'TGA', 'DVS if hygro risk MODERATE+', 'IR']
    else:
        n_solvents       = 8
        n_temp_points    = 2     # 25 degC + 50 degC
        methods          = ['slow evaporation', 'anti-solvent addition', 'slurry equilibration']
        priority         = 'STANDARD -- document in ICH Q6A; confirmatory XRPD on batch-release specification'
        n_characterisation = ['XRPD (batch release)', 'DSC (identity confirmation)', 'TGA if hydrate suspected']

    # Stability programme per ICH Q1A(R2)
    stability_conditions = [
        {'condition': '25 degC / 60% RH', 'duration_months': 24, 'zone': 'Long-term (ICH Zone I/II)'},
        {'condition': '30 degC / 65% RH', 'duration_months': 12, 'zone': 'Intermediate (ICH Zone IVa/b)'},
        {'condition': '40 degC / 75% RH', 'duration_months': 6,  'zone': 'Accelerated (ICH Q1A)'},
    ]
    if stab_class == 'CHALLENGING':
        stability_conditions.append({'condition': '60 degC / 80% RH, 1 month', 'duration_months': 1, 'zone': 'Stress (API intrinsic stability)'})
        stability_conditions.append({'condition': 'pH 1, 4, 7, 10 forced hydrolysis (ICH Q1A)', 'duration_months': None, 'zone': 'Stress -- hydrolysis'})
        stability_conditions.append({'condition': '1500 lux*h visible + 200 W*h/m2 UV (ICH Q1B)', 'duration_months': None, 'zone': 'Photostability'})

    # Route-specific packaging recommendation
    packaging_map = {
        'oral':        'HDPE bottle with desiccant, child-resistant cap; blister for unit-dose',
        'parenteral':  'Type I glass vial, nitrogen headspace, amber glass if photosensitive',
        'topical':     'Aluminium tube; avoid PVC for ester-containing APIs (plasticiser leach)',
        'inhalation':  'Aluminium blister or HDPE inhaler; strict humidity control (<30% RH manufacturing)',
    }
    packaging = packaging_map.get(route.lower(), 'HDPE bottle with desiccant')

    return {
        'polymorph_screen': {
            'risk_tier': risk_tier,
            'priority': priority,
            'n_solvents_recommended': n_solvents,
            'temperature_points': n_temp_points,
            'crystallisation_methods': methods,
            'characterisation_methods': n_characterisation,
            'ich_reference': 'ICH Q6A S3.1.1.5; FDA Guidance for Industry: ANDAs: Pharmaceutical Solid Polymorphism (2007)'
        },
        'stability_programme': {
            'stability_class': stab_class,
            'conditions': stability_conditions,
            'packaging_recommendation': packaging,
            'ich_reference': 'ICH Q1A(R2) 2003; ICH Q1B 1996 Photostability'
        },
        'downstream_workflow': {
            'name': 'analyze_accelerated_stability_of_pharmaceutical_formulations',
            'trigger': 'Run after solid-form selection to confirm stability under ICH Q1A conditions',
            'note': 'Use formulation with confirmed polymorph to generate shelf-life predictions'
        }
    }

# ---------------------------------------------------------------------------
# 5. Generate ICH Q6A narrative text
# ---------------------------------------------------------------------------
def generate_narrative(drug_name, route, d, poly_result, stab_result, excip_result, protocol):
    lines = [
        f"=== POLYMORPH RISK AND SOLID-STATE STABILITY ASSESSMENT ===",
        f"Compound:           {drug_name}",
        f"Intended Route:     {route}",
        f"MW:                 {d['mw']} Da",
        f"HBD / HBA:          {d['hbd']} / {d['hba']}",
        f"Rotatable Bonds:    {d['rotatable_bonds']}",
        f"TPSA:               {d['tpsa']} A2",
        f"Chiral Centres:     {d['n_chiral_centers']}",
        f"Descriptor Source:  {d['source']}",
        "",
        "--- 1. POLYMORPH RISK (Fleming 2010; Blagden & Davey Chem Soc Rev 2003) ---",
        f"Risk Score:   {poly_result['risk_score']} / 10  ->  {poly_result['risk_tier']}",
        poly_result['risk_summary'],
        "",
        "Contributing factors:",
    ]
    for f in poly_result['contributing_factors']:
        lines.append(f"  * {f}")
    lines += [
        "",
        "--- 2. SOLID-STATE STABILITY (ICH Q1A/Q1B) ---",
        f"Overall stability class: {stab_result['overall_stability_class']}",
        "",
        "Stability risks identified:",
    ]
    for w in stab_result['warnings'] or ['None identified']:
        lines.append(f"  (!!)  {w}")
    lines += [
        "",
        f"  Hygroscopicity:     {stab_result['details']['hygroscopicity']['class']}",
        f"  Photostability:     {stab_result['details']['photostability']['risk']}",
        f"  Thermal stability:  {stab_result['details']['thermal_stability']['assessment']}",
        "",
        "  Degradation pathways:",
    ]
    for dp in stab_result['details']['degradation_pathways'] or [{'pathway': 'None identified', 'groups': [], 'condition': ''}]:
        lines.append(f"    * {dp['pathway']}: {', '.join(dp['groups'])} [{dp.get('condition','')}]")

    lines += [
        "",
        "--- 3. EXCIPIENT COMPATIBILITY ---",
    ]
    for fl in excip_result['flags']:
        lines.append(f"  [{fl['risk']}] {fl['excipient']} -- {fl['reaction']}")
        if fl['risk'] != 'LOW':
            lines.append(f"        Mitigation: {fl['mitigation']}")

    ps = protocol['polymorph_screen']
    sp = protocol['stability_programme']
    lines += [
        "",
        "--- 4. RECOMMENDED ICH Q6A SCREENING PROTOCOL ---",
        f"Priority: {ps['priority']}",
        f"Solvents:  {ps['n_solvents_recommended']} systems; {ps['temperature_points']} temperature points",
        "Methods:   " + ', '.join(ps['crystallisation_methods']),
        "Characterisation: " + ', '.join(ps['characterisation_methods']),
        f"Reference: {ps['ich_reference']}",
        "",
        "--- 5. ICH Q1A(R2) ACCELERATED STABILITY PROGRAMME ---",
        f"Stability class: {sp['stability_class']}",
        "Conditions:",
    ]
    for cond in sp['conditions']:
        dur = f", {cond['duration_months']} months" if cond.get('duration_months') else ""
        lines.append(f"  * {cond['zone']}: {cond['condition']}{dur}")
    lines += [
        f"Packaging: {sp['packaging_recommendation']}",
        f"Reference: {sp['ich_reference']}",
        "",
        "--- 6. DOWNSTREAM WORKFLOWS ---",
        f"  -> {protocol['downstream_workflow']['name']}",
        f"     {protocol['downstream_workflow']['trigger']}",
        "",
        "References:",
        "  ICH Q6A (1999) Specifications: test procedures and acceptance criteria",
        "  ICH Q1A(R2) (2003) Stability testing of new drug substances and products",
        "  ICH Q1B (1996) Photostability testing of new drug substances and products",
        "  Blagden N, Davey RJ. Chem Soc Rev 2003;32(6):495-503",
        "  Fleming PE et al. Org Process Res Dev 2010;14(4):975-991",
        "  Brittain HG. Polymorphism in Pharmaceutical Solids, 2nd ed. 2009",
    ]
    return '\n'.join(lines)

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------
smiles      = os.environ.get('PARAM_SMILES', 'CC(=O)Oc1ccccc1C(=O)O').strip()
drug_name   = os.environ.get('PARAM_DRUG_NAME', 'compound').strip()
route       = os.environ.get('PARAM_ROUTE', 'oral').strip().lower()
excip_raw   = os.environ.get('PARAM_EXCIPIENTS', '').strip()
excipients  = [e.strip() for e in excip_raw.split(',') if e.strip()] if excip_raw else []

print(f"[polymorph_screening] compound={drug_name} smiles={smiles[:60]} route={route}", file=sys.stderr)

d          = calc_descriptors(smiles)
poly       = polymorph_risk(d)
stab       = solid_state_stability(d)
excip      = excipient_compatibility(d, excipients)
protocol   = screening_protocol(poly, stab, route)
narrative  = generate_narrative(drug_name, route, d, poly, stab, excip, protocol)

# --- output files ---
report = {
    'compound': drug_name,
    'smiles': smiles,
    'intended_route': route,
    'excipients_checked': excipients,
    'molecular_descriptors': d,
    'polymorph_risk_stratification': poly,   # renamed: risk flag, NOT crystal structure prediction
    'solid_state_stability': stab,
    'excipient_compatibility': excip,
    'scope_statement': (
        "RISK STRATIFICATION ONLY — This tool assesses molecular risk factors for "
        "polymorphism using structure-activity heuristics (Fleming 2010, Blagden & Davey 2003). "
        "It does NOT predict crystal structures, confirm polymorph existence, or replace "
        "experimental screening. High-risk or medium-risk compounds require experimental "
        "XRPD, DSC, and solvent-diversity crystallisation screening per ICH Q6A."
    ),
    'status': 'completed',
}

with open('polymorph_stability_report.json', 'w') as f:
    json.dump(report, f, indent=2)

with open('polymorph_stability_summary.txt', 'w') as f:
    f.write(narrative)

with open('screening_protocol_recommendation.json', 'w') as f:
    json.dump(protocol, f, indent=2)

print(narrative)
print(f"\n[polymorph_screening] risk_tier={poly['risk_tier']} stability_class={stab['overall_stability_class']}", file=sys.stderr)
PYEOF

    cat << 'EOF' > versions.yml
polymorph_stability_screening:
  python: "3.10"
  rdkit: ">=2022.09"
  numpy: ">=1.24"
  references: >
    ICH Q6A 1999; ICH Q1A(R2) 2003; ICH Q1B 1996;
    Blagden & Davey Chem Soc Rev 2003;
    Fleming et al. Org Process Res Dev 2010
EOF
    """
}

workflow POLYMORPH_STABILITY_WORKFLOW {
    take: meta_ch
    main: POLYMORPH_STABILITY_SCREENING(meta_ch)
    emit:
        results  = POLYMORPH_STABILITY_SCREENING.out.results
        output   = POLYMORPH_STABILITY_SCREENING.out.output
        protocol = POLYMORPH_STABILITY_SCREENING.out.protocol
}

workflow {
    meta = [id: 'polymorph_screen_run', single_end: false]
    Channel.value(meta) | POLYMORPH_STABILITY_WORKFLOW
}
