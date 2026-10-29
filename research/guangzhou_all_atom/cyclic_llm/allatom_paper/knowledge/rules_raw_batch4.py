# Batch 4: structure-property fundamentals, N-methyl position SAR from medicinal-chemistry campaigns, stability/liability determinants,
# clinical-guideline rules. Quotes copied from fetch_fulltext.py extracts (Europe PMC OA) and verified verbatim by build_kb.py on EC2.
from rules_raw_batch1 import add, R  # noqa

add(id="LIT-NMEPOS-001", pmcid="PMC13138696", tier="T1", kind="rule", scope=["macrocyclic peptide","N-methyl","position","lysine"], outcome="MDCK permeability",
    statement="In a macrocyclic Cyclin A/B inhibitor series, N-methylation at the alpha-N of Lys (MDCK Papp 1.1e-6 cm/s) gave much more permeability than at the epsilon-N (0.2e-6), and di-N-methylation of both gave 14.9e-6 cm/s.",
    feat={"n_nme": +1}, direction="+", effect="MDCK Papp 0.2 / 1.1 / 14.9 x1e-6 cm/s (eps-Me / alpha-Me / both)",
    quote="di-N-methylation of both Nα-Lys and Nε-Lys resulted in the highly permeable 5 (MDCK P app = 14.9 × 10-6 cm/s)",
    quotes=["than did the N-methylation of the Nε-Lys (4, MDCK P app = 0.2 × 10-6 cm/s)"],
    confidence="medium", notes="one campaign, matched series; shows position matters more than count")
add(id="LIT-NMEPOS-002", pmcid="PMC13138696", tier="T1", kind="caution", scope=["macrocyclic peptide","N-alkylation","chameleonic position"], outcome="cell permeability",
    statement="N-alkylation at a chameleonic position (an NH that forms an intramolecular H-bond) can lower cell permeability instead of raising it; seen in Cyclin A/B macrocycles and in sanguinamide analogues.",
    feat=None, direction="caution", effect=None,
    quote="N-alkylation at a chameleonic position led to a decrease in cell permeability was previously observed in N-methylated analogues of the cyclic peptide natural product sanguinamide",
    confidence="medium", notes="complements LIT-NME-002; do not apply a monotone 'more N-Me = more permeable' prior")
add(id="LIT-DPRO-001", pmcid="PMC12990038", tier="T1", kind="caution", scope=["macrocyclic peptide","D-proline","HBD count"], outcome="MDCK permeability",
    statement="Replacing a residue with D-proline, which lowered the HBD count by one, counterintuitively reduced MDCK permeability in an orally optimised Cyclin A/B macrocycle series.",
    feat=None, direction="caution", effect=None,
    quote="replacement of this position with D-proline counterintuitively reduced passive permeability as measured by MDCK, even though this side chain reduces the HBD count by one",
    confidence="medium", notes="HBD count alone is not a sufficient permeability predictor")
add(id="LIT-OB-001", pmcid="PMC12990038", tier="T1", kind="fundamental", scope=["macrocyclic peptide","oral bioavailability","design practice"], outcome="oral bioavailability",
    statement="Medicinal-chemistry practice for orally bioavailable macrocyclic peptides: target F >= 20% by modulating TPSA, HBD count and LogD.",
    feat={"tpsa": -1, "hbd": -1}, direction="multi", effect="target F >= 20%",
    quote="improving oral bioavailability with a target of ≥20% by modulating compound properties such as TPSA, HBD count, and LogD",
    confidence="medium", notes="project goal statement, not a measured law")
add(id="LIT-TRADE-001", pmcid="PMC12557401", tier="T2", kind="fundamental", scope=["lipophilicity","solubility","permeability"], outcome="solubility-permeability trade-off",
    statement="Reducing lipophilicity often trades solubility gains against permeability loss.",
    feat=None, direction="context", effect=None,
    quote="a reduction in lipophilicity often results in a trade-off between the solubility increase and permeability decrease",
    confidence="high", notes="review of small-molecule chemical modification strategies")
add(id="LIT-NMEPOS-003", pmcid="PMC12557401", tier="T2", kind="caution", scope=["methylation","intramolecular hydrogen bond"], outcome="permeability",
    statement="Methylation at a position whose NH is involved in an intramolecular hydrogen bond markedly improved solubility but reduced permeability.",
    feat=None, direction="caution", effect=None,
    quote="methylation at the 2-position (73a), where the NH group is involved in intramolecular HB, markedly improved solubility but reduced permeability",
    confidence="medium", notes="small-molecule examples in a review; same principle as LIT-NME-002")
add(id="LIT-SD-001", pmcid="PMC10673305", tier="T2", kind="fundamental", scope=["passive permeability","lipophilicity","Overton"], outcome="passive permeability mechanism",
    statement="Octanol-water lipophilicity (log Pow) is correlated with passive permeability through Overton's rule: the basis of solubility-diffusion reasoning for membrane crossing.",
    feat={"clogp": +1}, direction="+", effect=None,
    quote="the logarithm of the n-octanol and water partition coefficient, which can be correlated to passive permeability via",
    confidence="medium", notes="bulk-lipophilicity proxy; fails for chameleonic macrocycles (see LIT-CHAM-*, LIT-LIP-*)")
add(id="LIT-SD-002", pmcid="PMC10003141", tier="T1", kind="caution", scope=["peptide","solubility-diffusion model","permeability simulation"], outcome="permeability prediction",
    statement="Inhomogeneous solubility-diffusion (ISDM) estimates of peptide membrane permeability were about one order of magnitude below PAMPA values; kinetic models correlated better for small compounds.",
    feat=None, direction="caution", effect="~10x underestimate vs PAMPA",
    quote="the ISDM-based estimation of the peptide membrane permeability is about one order of magnitude lower than the value found in PAMPA assays",
    confidence="medium", notes="physics-model limitation; a hexadecane PAMPA membrane differs from a lipid bilayer")
add(id="LIT-CHAM-003", pmcid="PMC12929930", tier="T1", kind="fundamental", scope=["molecular chameleon","intramolecular hydrogen bond","grazoprevir"], outcome="conformational change in apolar medium",
    statement="For the macrocyclic drug grazoprevir the conformational changes needed for permeability are driven by multiple IMHBs, raising the hydrogen-bonded population from 11% to 76%.",
    feat=None, direction="context", effect="IMHB population 11% -> 76%",
    quote="The conformational changes required for membrane permeability are driven by the formation of multiple IMHBs, increasing the hydrogen bonded population from 11% to 76%",
    confidence="medium", notes="single drug case study (non-peptide macrocycle)")
add(id="LIT-STER-003", pmcid="PMC13134636", tier="T1", kind="rule", scope=["macrobicycle","stereochemistry"], outcome="permeability",
    statement="In a polar macrobicycle series, inverting the stereochemistry of a residue adjacent to the bridging His (or both) increased permeability about 6-fold.",
    feat=None, direction="context", effect="~6-fold permeability",
    quote="inverting the stereochemistry of the adjacent Ser residue (1c) or inverting both the His and Ser simultaneously resulted in a ∼6-fold increase",
    confidence="medium", notes="direction of a D/L inversion is context-dependent (the His inversion alone was slightly detrimental)")
add(id="LIT-NME-005", pmcid="PMC13134636", tier="T1", kind="rule", scope=["macrobicycle","N-methyl","amide"], outcome="permeability",
    statement="N-methylating the Ser amide and deleting the N-terminal acetamide increased permeability in the macrobicycle series, consistent with removing exposed polar NH.",
    feat={"n_nme": +1, "hbd": -1}, direction="multi", effect=None,
    quote="the permeability increase caused by N-methylating the Ser amide (1d) and deleting the N-terminal acetamide (1f)",
    confidence="medium", notes="")
add(id="LIT-CYC-002", pmcid="PMC8229464", tier="T2", kind="fundamental", scope=["cyclization","linear vs cyclic"], outcome="membrane permeability",
    statement="Cyclization can raise membrane permeability relative to the linear peptide by reducing intermolecular hydrogen bonds, adjusting lipophilicity and reducing hydrodynamic size.",
    feat={"is_cyclic": +1}, direction="+", effect=None,
    quote="Cyclization of a linear peptide may reduce the number of intermolecular hydrogen bonds, adjust the lipophilicity, and reduce the hydrodynamic size",
    confidence="medium", notes="mechanistic background statement from a review")
add(id="LIT-NME-006", pmcid="PMC8229464", tier="T1", kind="rule", scope=["N-methylated cyclic peptide library","Caco-2"], outcome="intestinal permeability",
    statement="In a 30-member N-methylated cyclic peptide library, the best intestinal permeability (Caco-2 Papp 4e-6 cm/s) came from a triple N-methylated analogue, not the most heavily methylated one.",
    feat=None, direction="context", effect="Caco-2 Papp 4e-6 cm/s",
    quote="analog with triple-N-methylation on D-Trp8, Lys9, and Phe11 showed the highest intestinal permeability (Caco-2, Papp = 4 × 10-6 cm/s)",
    confidence="medium", notes="reported in a review of an earlier study; optimum at specific positions")
add(id="LIT-POL-002", pmcid="PMC12990023", tier="T2", kind="rule", scope=["cyclic peptide","lipophilicity window","ChromLogD"], outcome="permeability + solubility",
    statement="Permeability-optimised lipophilicity (POL) rules: ChromLogD7.4 > 2.2 and cLogP < 4, balancing solubility and permeability.",
    feat={"clogp": 0}, direction="window", effect="cLogP < 4", window={"clogp_max": 4},
    quote="Permeability-optimized lipophilicity (POL) rules, including ChromlogD7.4 (threshold >2.2) and cLogP (threshold <4), balancing solubility and permeability-enhancing features",
    confidence="medium", notes="combine with LIT-BRO5-001 (cLogP > 2.5): joint window 2.5 < cLogP < 4; ChromLogD not computable from SMILES")
add(id="LIT-BRO5-006", pmcid="PMC13243568", tier="T2", kind="rule", scope=["bRo5 macrocycle","physicochemical window"], outcome="favourable physicochemical profile",
    statement="Proposed bRo5 macrocycle window: MW < 1000 Da, fewer than six H-bond donors, cLogP between -2 and 10, polar surface area under 250 A^2.",
    feat={"mw": -1, "hbd": -1, "tpsa": -1}, direction="window", effect=None,
    window={"mw_max": 1000, "hbd_max": 6, "clogp_min": -2, "clogp_max": 10, "tpsa_max": 250},
    quote="bRo5 macrocycles with molecular weight below 1000 Da, fewer than six hydrogen-bond donors, cLogP between -2 and 10, and a polar surface area under 250 Å2",
    confidence="medium", notes="cited by the source from earlier work; wide window")
add(id="LIT-CLIN-001", pmcid="PMC10150360", tier="T1", kind="caution", scope=["cyclic peptide drugs","oral","desmopressin","octreotide"], outcome="oral drug classification",
    statement="Desmopressin and octreotide, cyclic peptides with very low oral bioavailability, were the only oral drugs misclassified by all the macrocycle descriptor models.",
    feat=None, direction="caution", effect=None,
    quote="The cyclic peptides desmopressin and octreotide, which have very low oral bioavailability, constitute the only oral drugs that are misclassified",
    confidence="high", notes="'oral' labels in drug lists can mean low-bioavailability peptides")
add(id="LIT-CLIN-002", pmcid="PMC13492385", tier="T2", kind="fundamental", scope=["cyclic peptide drugs","size","polar surface area"], outcome="polarity determinants",
    statement="In approved/reported cyclic peptides, overall polarity is dictated mainly by peptide size and backbone composition rather than by the cyclization chemistry (PSA clusters at 500-1000 A^2).",
    feat=None, direction="context", effect="PSA 500-1000 A^2 typical",
    quote="overall polarity is primarily dictated by peptide size and backbone composition rather than the specific cyclization chemistry",
    confidence="medium", notes="CAS Content Collection analysis")
add(id="LIT-CLIN-003", pmcid="PMC13492385", tier="T2", kind="fundamental", scope=["cyclic peptide drugs","molecular weight"], outcome="chemical space",
    statement="Most reported cyclic peptides lie in the 1,000-2,500 Da range; older approved cyclic peptide drugs include extreme high-MW and high-PSA outliers.",
    feat=None, direction="context", effect="MW 1000-2500 Da",
    quote="Most reported cyclic peptides cluster in the 1,000-2500 Da range, with macrocyclic peptides constituting the dominant class",
    confidence="medium", notes="")
add(id="LIT-NME-007", pmcid="PMC13492385", tier="T2", kind="fundamental", scope=["N-methylation","head-to-tail cyclization","oral absorption"], outcome="oral absorption",
    statement="Combining N-methylation with head-to-tail cyclization has yielded cyclic peptides with improved oral absorption.",
    feat={"n_nme": +1, "is_cyclic": +1}, direction="+", effect=None,
    quote="Combining N-methylation with head-to-tail cyclization has yielded peptides with improved oral absorption profiles",
    confidence="medium", notes="")
add(id="LIT-STAB-002", pmcid="PMC13492385", tier="T2", kind="fundamental", scope=["N-methylation","D-amino acids","beta-amino acids","proteolysis"], outcome="proteolytic stability + permeability",
    statement="N-methylation, D-amino acids, beta-amino acids and peptidomimetic linkers reduce hydrogen-bond donors and proteolytic susceptibility.",
    feat={"n_nme": +1, "n_dres": +1}, direction="+", effect=None,
    quote="N-methylation, incorporation of d-amino acids, β-amino acids, and peptidomimetic linkers (e.g., azapeptides, amide isosteres) reduce hydrogen bond donors and proteolytic susceptibility",
    confidence="medium", notes="stability rule: weight applies to the stability outcome, not permeability alone")
add(id="LIT-STAB-003", pmcid="PMC13492385", tier="T2", kind="caution", scope=["cyclization","rigidity","permeability"], outcome="permeability",
    statement="Cyclization masks polar groups through intramolecular hydrogen bonding and improves proteolytic stability, but residual polarity, size and excessive rigidity still hinder permeation.",
    feat=None, direction="caution", effect=None,
    quote="cyclization can reduce conformational flexibility and mask polar groups through intramolecular hydrogen bonding, improving proteolytic stability and sometimes permeability",
    confidence="medium", notes="")
add(id="LIT-STAB-004", pmcid="PMC8708026", tier="T2", kind="fundamental", scope=["head-to-tail cyclization","acetylation","serum half-life"], outcome="serum stability",
    statement="A head-to-tail cyclized peptide had a serum half-life beyond 24 h whereas a C-acetylated linear version was fully degraded within 8 h.",
    feat=None, direction="+", effect="t1/2 > 24 h vs < 8 h",
    quote="a C-acetylated version (AcM2pep(RY), which was fully degraded within 8 h, and a head-to-tail cyclized variant (M2pep(RY)) with a half-life beyond 24 h in serum",
    confidence="medium", notes="example from a review")
add(id="LIT-STAB-005", pmcid="PMC8708026", tier="T2", kind="fundamental", scope=["disulfide","lactam bridge","serum half-life"], outcome="serum stability",
    statement="Replacing a disulfide by a lactam bridge between Dap and Asp side chains raised an apamin-type peptide's half-life beyond 24 h.",
    feat=None, direction="+", effect="t1/2 > 24 h",
    quote="by simply replacing the disulfide by a lactam bridge, bridging the side chains of an N-terminal diaminopropionic acid and a C-terminal aspartic acid, the half-life increased beyond 24 h",
    confidence="medium", notes="reducible disulfides are a liability in plasma (see LIT-CARD romidepsin counter-example)")
add(id="LIT-STAB-006", pmcid="PMC8708026", tier="T2", kind="caution", scope=["cyclization","affinity","protease resistance"], outcome="affinity vs stability",
    statement="Cyclization often enhances target affinity when the right conformation is favoured, whereas the gain in protease resistance may be more limited.",
    feat=None, direction="caution", effect=None,
    quote="cyclization often enhances peptide affinity for its target if the adequate conformation is favored, although increase in protease-resistance may be more limited",
    confidence="medium", notes="")
add(id="LIT-STAB-007", pmcid="PMC8708026", tier="T2", kind="fundamental", scope=["N-methylation","lipophilicity"], outcome="mechanism",
    statement="N-methylation decreases hydrogen-bond formation and increases lipophilicity.",
    feat={"n_nme": +1, "hbd": -1}, direction="multi", effect=None,
    quote="N-methylation decreases hydrogen bond formation and increases lipophilicity",
    confidence="high", notes="mechanism-level statement")
add(id="LIT-STAB-008", pmcid="PMC13406010", tier="T2", kind="fundamental", scope=["D-amino acids","lipopeptide","digestive proteases"], outcome="protease stability",
    statement="D-amino acid incorporation in ultra-short lipopeptides raised half-life 2- to 32-fold against pepsin, trypsin and cathepsin K.",
    feat={"n_dres": +1}, direction="+", effect="2- to 32-fold half-life",
    quote="the incorporation of D-amino acids in ultra-short lipopeptides (such as Lip7) led to a 2- to 32-fold increase in half-life when exposed to digestive proteases",
    confidence="medium", notes="lipopeptide example, not cyclic; direction supports D-residue stability benefit")
add(id="LIT-STAB-009", pmcid="PMC13406010", tier="T2", kind="fundamental", scope=["protease mechanism","folded state"], outcome="protease stability",
    statement="Proteases need the substrate to unfold or adopt a transition state, so stabilising the folded/constrained state raises the barrier to proteolysis.",
    feat=None, direction="context", effect=None,
    quote="stabilizing the native folded state significantly increases the thermodynamic barrier for proteolysis",
    confidence="medium", notes="mechanistic rationale for macrocyclization and stapling")
add(id="LIT-STAB-010", pmcid="PMC11141402", tier="T1", kind="rule", scope=["macrocyclic peptide","cyclic beta-amino acid","serum stability"], outcome="serum half-life",
    statement="Replacing cyclic beta-amino acids by alanine in macrocyclic Mpro inhibitors cut human serum half-lives to about 4-5 h, showing the cyclic residues add proteolytic stability.",
    feat=None, direction="context", effect="t1/2 4.6 h and 4.2 h for Ala variants",
    quote="the alanine variants BM3A and BM7A showed substantially lower stabilities with half-lives of 4.6 and 4.2 h, respectively",
    confidence="medium", notes="comparison to the parent half-life not in the quoted sentence")
add(id="LIT-STAB-011", pmcid="PMC11040643", tier="T2", kind="fundamental", scope=["bicyclic peptide","hit-to-lead"], outcome="affinity + stability",
    statement="Adding two stabilising cyclisations to a monocyclic hit raised affinity more than 500-fold while keeping oral-bioavailability-relevant properties and plasma stability.",
    feat=None, direction="context", effect=">500-fold affinity",
    quote="the addition of two stabilizing cyclisations into the monocyclic hit compound synergistically increased the affinity more than 500 fold",
    confidence="medium", notes="cited prior work in the source's introduction")
add(id="LIT-LIAB-001", pmcid="PMC12801052", tier="T2", kind="fundamental", scope=["Gln deamidation","Asn deamidation","glutarimide"], outcome="chemical stability",
    statement="Gln deamidation via a glutarimide intermediate is slower than Asn (succinimide) because the six-membered ring forms less favourably.",
    feat=None, direction="context", effect=None,
    quote="Gln deamidation via a glutarimide intermediate is slower because the formation of the six-membered ring is less favourable kinetically",
    confidence="high", notes="complements the Asn-Gly liability flags in knowledge_liability_flags.py (internal)")
add(id="LIT-LIAB-002", pmcid="PMC12801052", tier="T1", kind="caution", scope=["peptide handling","TFA","deamidation"], outcome="chemical stability during handling",
    statement="Doubling TFA from 0.1% to 0.2% roughly doubled the extent of deamidation during peptide analysis and purification.",
    feat=None, direction="caution", effect="~2x deamidation per 2x TFA",
    quote="Increasing TFA from 0.1% to 0.2% approximately doubled the extent of deamidation",
    confidence="high", notes="process liability; affects labelled stability data, not design")
