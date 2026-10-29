# Workstream K rules, batch 1 (permeability / N-methylation / IMHB / size). Every quote is copied from sentences returned by
# fetch_fulltext.py (Europe PMC OA full text) and is re-verified verbatim against the stored text by build_kb.py on EC2.
# feat: computable feature -> sign of association with the stated outcome (+1 raises, -1 lowers); None = text-only context rule.
R = []
def add(**k): R.append(k)

add(id="LIT-NME-001", pmcid="PMC3210067", tier="T1", scope=["cyclic peptide","N-methyl"], outcome="permeability",
    statement="Selective backbone N-methylation of cyclic peptides can give drug-like membrane permeability and oral bioavailability.",
    feat={"n_nme": +1}, direction="+", effect=None,
    quote="a method for the selective, on-resin N-methylation of cyclic peptides to generate compounds with drug-like membrane permeability and oral bioavailability",
    confidence="high", notes="direction holds for selected positions; see LIT-NME-002 for the placement caveat")
add(id="LIT-NME-002", pmcid="PMC3210067", tier="T1", scope=["cyclic peptide","N-methyl","placement"], outcome="permeability",
    statement="N-methyl placement matters: a variant differing by a single N-methyl was predicted much less permeable because it could not form internal hydrogen bonds in a low-dielectric environment.",
    feat=None, direction="context", effect=None,
    quote="7 is significantly less permeable due to its inability to form internal hydrogen bonds in a low dielectric environment",
    confidence="medium", notes="computational prediction in the cited sentence; context rule for prompts")
add(id="LIT-STAB-001", pmcid="PMC3210067", tier="T1", scope=["cyclic peptide","D-residue","macrocyclization"], outcome="proteolytic stability",
    statement="Cyclization (and possibly D-residues) stabilises cyclic peptides toward proteolytic degradation; all studied cyclic hexapeptides were stable in human plasma (t1/2 > 360 min).",
    feat=None, direction="+", effect="t1/2 > 360 min (human plasma)",
    quote="consistent with the stabilizing effect of cyclization (and possibly the presence of D-residues) toward proteolytic degradation",
    confidence="medium", notes="stability rule; no SMILES-computable feature")
add(id="LIT-IMHB-001", pmcid="PMC9490236", tier="T1", scope=["macrocycle","NH","intramolecular hydrogen bond"], outcome="permeability",
    statement="Membrane permeability can be achieved systematically by engaging all backbone amide NH groups in internal hydrogen bonds; fewer exposed NH raises permeability.",
    feat={"exposed_nh": -1}, direction="-", effect="84 designs (6-12 residues) with apparent permeability > 1e-6 cm/s",
    quote="membrane permeability can be systematically achieved by ensuring all amide (NH) groups are engaged in internal hydrogen bonding interactions",
    confidence="high", notes="exposed_nh needs a conformer-based or heuristic estimate; the 2D HBD count is a proxy")
add(id="LIT-IMHB-002", pmcid="PMC9490236", tier="T1", scope=["macrocycle","conformational switching"], outcome="permeability",
    statement="Designs with exposed NH groups can still be permeable if an alternative, fully hydrogen-bonded state is favoured in the lipid membrane (conformational switching).",
    feat=None, direction="context", effect=None,
    quote="Designs with exposed NH groups can be made membrane permeable through the design of an alternative isoenergetic fully hydrogen-bonded state",
    confidence="high", notes="context rule")
add(id="LIT-IMHB-003", pmcid="PMC9490236", tier="T1", scope=["macrocycle","intramolecular hydrogen bond"], outcome="permeability",
    statement="Internal hydrogen-bond satisfaction appears necessary but is not sufficient for permeability (designs with no unsatisfied NH were still not permeable).",
    feat=None, direction="context", effect=None,
    quote="hydrogen bond satisfaction appears necessary for permeability, it is not sufficient",
    confidence="high", notes="limits any NH-count rule")
add(id="LIT-SIZE-001", pmcid="PMC9490236", tier="T2", scope=["peptide","N-methyl","size"], outcome="permeability",
    statement="Purely lipophilic (fully N-methylated) peptides show a steep decrease in permeability with size.",
    feat={"n_heavy_atoms": -1}, direction="-", effect=None,
    quote="purely lipophilic peptides show a steep decrease in permeability with size",
    confidence="medium", notes="cited by the paper from Pye et al. 2017; scope = fully N-methylated 8-10-mers")
add(id="LIT-BRO5-001", pmcid="PMC10150360", tier="T1", scope=["macrocycle","oral bioavailability","HBD","MW","cLogP"], outcome="oral bioavailability",
    statement="Among FDA-approved macrocycles and clinical candidates, HBD <= 7 combined with either MW < 1000 Da or cLogP > 2.5 separated oral from parenteral drugs.",
    feat={"hbd": -1, "mw": -1, "clogp": +1}, direction="window", effect="~90% sensitivity, ~70% specificity",
    window={"hbd_max": 7, "mw_max": 1000, "clogp_min": 2.5, "any_of": ["mw_max", "clogp_min"]},
    quote="Simple bi-descriptor models, i.e., HBD ≤ 7 in combination with either MW < 1000 Da or cLogP > 2.5, distinguished orals from parenterals",
    confidence="high", notes="classification of drugs/candidates, not a mechanistic law; windows usable as soft potentials")
add(id="LIT-BRO5-002", pmcid="PMC10150360", tier="T1", scope=["macrocycle","oral bioavailability","TPSA"], outcome="oral bioavailability",
    statement="Guideline for orally available macrocycles: HBD <= 7 together with either MW < 1000 Da, cLogP > 2.5, or TPSA < 300 A^2.",
    feat={"tpsa": -1}, direction="window", effect=None, window={"hbd_max": 7, "mw_max": 1000, "clogp_min": 2.5, "tpsa_max": 300, "any_of": ["mw_max", "clogp_min", "tpsa_max"]},
    quote="HBD ≤ 7 in combination with either of MW < 1000 Da, cLogP > 2.5, or TPSA < 300 Å2 are guidelines that are easy to memorize",
    confidence="high", notes="")
add(id="LIT-BRO5-003", pmcid="PMC10150360", tier="T1", scope=["macrocycle","oral drugs"], outcome="oral bioavailability",
    statement="Orally available macrocyclic drugs are smaller (MW), more lipophilic (cLogP), less polar (TPSA, HBA, HBD) and less flexible (NRotB) than parenteral ones.",
    feat={"mw": -1, "clogp": +1, "tpsa": -1, "hba": -1, "hbd": -1, "nrotb": -1}, direction="multi", effect=None,
    quote="The oral drugs were significantly smaller (MW), more lipophilic (cLogP), less polar (TPSA, HBA, HBD), and less flexible (NRotB)",
    confidence="high", notes="direction vector for six descriptors")
add(id="LIT-BRO5-004", pmcid="PMC10150360", tier="T1", scope=["macrocycle","bRo5"], outcome="chemical space",
    statement="Macrocyclic drugs usually lie in beyond-Rule-of-5 space, yet 30-40% of the drugs and clinical candidates are orally bioavailable.",
    feat=None, direction="context", effect="30-40% oral",
    quote="Macrocycles usually reside in the beyond the Rule of 5 chemical space, but 30-40% of the drugs and clinical candidates are orally bioavailable",
    confidence="high", notes="")
add(id="LIT-BRO5-005", pmcid="PMC10150360", tier="T2", scope=["bRo5","oral bioavailability","AB-MPS"], outcome="oral bioavailability",
    statement="AbbVie multiparameter score AB-MPS = |cLogD - 3| + NAR + NRotB; a score <= 14 separated acceptable (F > 27.3%) from low-moderate oral bioavailability in bRo5 space.",
    feat={"ab_mps": -1}, direction="window", effect="cutoff 14", window={"ab_mps_max": 14},
    quote="An AB-MPS score of ≤14 was found to be a cutoff between acceptable (F > 27.3%) and low-moderate oral bioavailability in the bRo5 space",
    confidence="medium", notes="reported in a review from an earlier AbbVie study (ref 4 in the source); NAR and cLogD definitions need the original")
add(id="LIT-IMHB-004", pmcid="PMC10685455", tier="T2", scope=["macrocycle","intramolecular hydrogen bond"], outcome="permeability",
    statement="The intramolecular hydrogen-bond donor contribution from accelerated MD correlates well with measured PAMPA permeability for peptidic macrocycles.",
    feat={"exposed_nh": -1}, direction="-", effect=None,
    quote="Intramolecular hydrogen bond donor contribution from aMD correlates well with the PAMPA results",
    confidence="medium", notes="computational study on 47 macrocycles")
add(id="LIT-NME-003", pmcid="PMC10685455", tier="T2", scope=["macrocycle","N-methyl"], outcome="permeability",
    statement="In one analysed macrocycle pair, methylation of a hydrogen-bond donor increased cell permeability about two-fold (PAMPA).",
    feat={"n_nme": +1}, direction="+", effect="~2x permeability for one added methyl",
    quote="methylation of D1 in macrocycle 28, which decreases the PAMPA-log Pe, that is, increases the cell permeability by a factor of 2",
    confidence="medium", notes="single-pair observation")
add(id="LIT-SIZE-002", pmcid="PMC11995216", tier="T1", scope=["depsipeptide","macrocyclization","size"], outcome="permeability",
    statement="In oligomeric depsipeptides, permeability decreases with increasing size (231-1488 Da) and increases uniformly on cyclization.",
    feat={"mw": -1, "is_cyclic": +1}, direction="multi", effect="size range 231-1488 Da",
    quote="decreasing permeability with increasing size (231-1488 Da), uniform increase in permeability upon cyclization",
    confidence="medium", notes="depsipeptide series; transfer to peptides is an assumption")
add(id="LIT-RING-001", pmcid="PMC11995216", tier="T1", scope=["depsipeptide","ring size"], outcome="permeability",
    statement="The permeability benefit of cyclization is not monotonic in ring size: specific ring sizes (6 and 24 members in that series) gave unusually large gains.",
    feat=None, direction="context", effect="ring sizes 6 and 24",
    quote="The unusually large increases in permeability at ring sizes of 6 and 24 are more difficult to explain rigorously",
    confidence="medium", notes="series-specific")
