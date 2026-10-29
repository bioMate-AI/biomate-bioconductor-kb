from rules_raw_batch1 import add, R  # noqa
add(id="LIT-HBD-002", pmcid="PMC13661285", tier="T1", kind="rule", scope=["cyclic peptide","HBD","ring size"], outcome="cell permeability",
    statement="At the same ring size, a cyclic peptide with five H-bond donors was much less cell-permeable than a less polar one (chloroalkane penetration CP50 2.6 vs 0.58 uM; lower CP50 = better).",
    feat={"hbd": -1}, direction="-", effect="CP50 2.6 uM (5 HBD) vs 0.58 uM",
    quote="which has the same ring size but five H-bond donors that impair membrane permeability",
    confidence="medium", notes="two compounds; assay = chloroalkane penetration")
add(id="LIT-NME-004", pmcid="PMC13661285", tier="T1", kind="rule", scope=["cyclic peptide","N-methyl"], outcome="cell permeability",
    statement="N-methylation of an asparagine in a library-derived cyclic peptide lowered CP50 from 0.58 to 0.091 uM (about 6-fold, ratio computed from the two reported values), nearly matching the Trp control.",
    feat={"n_nme": +1}, direction="+", effect="CP50 0.58 -> 0.091 uM (~6.4x)",
    quote="A less polar analog of 23a-CA in which we N-methylated asparagine (23b-CA) showed excellent permeability",
    confidence="medium", notes="single matched pair; the 6.4x is computed by the extractor from CP50 values in neighbouring sentences")
add(id="LIT-SIZE-003", pmcid="PMC13661285", tier="T2", kind="fundamental", scope=["cyclic peptide","size","permeability"], outcome="permeability",
    statement="Size alone does not preclude permeation: natural cyclic peptides such as cyclosporine (1,203 Da) cross membranes efficiently, far above the Ro5 size guideline.",
    feat=None, direction="context", effect="cyclosporine 1,203 Da",
    quote="substantially larger molecules, such as the prototype peptide cyclosporine (1,203 Da), can efficiently cross cell membranes",
    confidence="high", notes="")
add(id="LIT-TPSA-002", pmcid="PMC13531348", tier="T2", kind="fundamental", scope=["TPSA","chameleon"], outcome="permeability",
    statement="Classically molecules with 2D TPSA > 140 A^2 are poorly membrane-permeable; molecular chameleons are exceptions because their conformation adapts to solvent polarity.",
    feat={"tpsa": -1}, direction="window", effect="TPSA > 140 A^2", window={"tpsa_soft_max": 140},
    quote="molecules with TPSA >140 Å2 do not favour membrane permeability though molecular chameleons are exceptions to this rule",
    confidence="medium", notes="review statement; use TPSA as a soft prior, not a hard filter, for chameleonic macrocycles")
add(id="LIT-3DPSA-001", pmcid="PMC13492371", tier="T1", kind="fundamental", scope=["bRo5","3D polar surface area","radius of gyration"], outcome="permeability",
    statement="For bRo5 compounds, solvent-accessible 3D polar surface area, 3D nonpolar surface area and radius of gyration are reported to correlate better with permeability than MW, 2D TPSA and cLogP.",
    feat=None, direction="context", effect=None,
    quote="reported to correlate better to permeability than MW, TPSA, and c log P",
    confidence="high", notes="motivates conformer-based descriptors; our own test (idea A) did not confirm a gain on public data")
add(id="LIT-EPSA-001", pmcid="PMC13492371", tier="T1", kind="rule", scope=["macrocyclic peptide","EPSA"], outcome="permeability",
    statement="An experimental polar surface area (EPSA) below about 90 A^2 has been reported as the limit below which macrocyclic peptides are expected to be membrane permeable (griselimycin EPSA 74 A^2).",
    feat={"epsa": -1}, direction="window", effect="EPSA < 90 A^2", window={"epsa_max": 90},
    quote="well below the 90 Å2 that has been reported as the limit below which macrocyclic peptides are expected to be cell membrane permeable",
    confidence="medium", notes="EPSA is a chromatographic measurement; not computable from SMILES; text/retrieval context only")
add(id="LIT-CHAM-002", pmcid="PMC13492371", tier="T1", kind="fundamental", scope=["PROTAC","chameleonicity"], outcome="permeability",
    statement="A PROTAC behaving as an inverse chameleon had 20-fold lower cellular permeability and nearly 1000-fold lower PAMPA permeability than its chameleonic analogue.",
    feat=None, direction="context", effect="20x (cell), ~1000x (PAMPA)",
    quote="had a substantially reduced permeability (20-fold in a cellular assay, close to 1000-fold in the PAMPA assay)",
    confidence="medium", notes="non-peptide example of the chameleonicity effect size")
add(id="LIT-NH-002", pmcid="PMC12392647", tier="T2", kind="fundamental", scope=["cyclic peptide","backbone NH","N-methylation","amide-to-ester","IMHB"], outcome="permeability",
    statement="Strategies to enhance cyclic-peptide permeability reduce exposure of backbone NH groups: N-methylation, amide-to-ester substitution and promotion of internal hydrogen bonds.",
    feat={"exposed_nh": -1}, direction="-", effect=None,
    quote="enhance membrane permeability by reducing the exposure of backbone NH groups, including N-methylation",
    confidence="high", notes="")
add(id="LIT-TPSA-003", pmcid="PMC12392647", tier="T1", kind="caution", scope=["cyclic peptide","permeability prediction","logP","TPSA"], outcome="model benchmarking",
    statement="Adding logP and TPSA as auxiliary tasks to deep-learning permeability models did not significantly improve prediction in a 13-model benchmark, likely because they do not capture conformational features.",
    feat=None, direction="caution", effect=None,
    quote="neither logP nor TPSA, used individually or in combination, significantly improves permeability prediction",
    confidence="medium", notes="prediction-benchmark statement, not a mechanistic claim")
add(id="LIT-DATA-001", pmcid="PMC12990040", tier="T1", kind="caution", scope=["cyclic peptide","permeability data","hydrophobicity bias"], outcome="data bias",
    statement="Public/permeable-peptide training data differ from FDA-like polar peptides along a principal component correlated with high cLogP (Rp 0.54), high N-methylation (Rp 0.63) and lack of HBD (Rp -0.83): data are dominated by hydrophobic, N-methylated peptides.",
    feat=None, direction="caution", effect="Rp 0.54 / 0.63 / -0.83",
    quote="correlated with high cLogP (Rp = 0.54), high N-methylation (Rp = 0.63), and a lack of hydrogen bond donors (Rp = -0.83)",
    confidence="medium", notes="dataset-composition statement; limits extrapolation of N-Me/cLogP rules to polar peptides")
add(id="LIT-POL-001", pmcid="PMC12990040", tier="T1", kind="rule", scope=["cyclic peptide","polar permeable peptides"], outcome="permeability + solubility",
    statement="A model-informed ruleset for polar, soluble, permeable cyclic peptides resembling approved drugs: cLogP < 1, more than 2 OH/charged fragments, N-methylation < 2, #HBD >= 10 (in tension with the usual 'fewer HBD' rules).",
    feat=None, direction="conflict", effect=None,
    quote="FDA-likeness (cLogP < 1, #OH + # Charged Fragments >2, N-methylation <2, #HBD ≥ 10)",
    confidence="low", notes="CONFLICTS with LIT-BRO5-001/003 (HBD <= 7); different regime (polar chameleonic peptides); keep as flagged conflict, no weight")
add(id="LIT-NCAA-001", pmcid="PMC13074632", tier="T2", kind="fundamental", scope=["N-methylation","D-amino acids","backbone alterations"], outcome="permeability + metabolic stability",
    statement="Non-natural modifications such as N-methylation, D-amino acids and backbone alterations are established tools for improving membrane permeability and metabolic stability.",
    feat={"n_nme": +1, "n_dres": +1}, direction="+", effect=None,
    quote="N-methylation, d-amino acids, and backbone alterations are established tools for improving membrane permeability and metabolic stability",
    confidence="medium", notes="author's background statement in a generative-design paper")
add(id="LIT-DATA-002", pmcid="PMC11698989", tier="T1", kind="caution", scope=["macrocycle permeability data","PAMPA"], outcome="data bias",
    statement="In a curated macrocycle permeability database, 67% of records are PAMPA and 91% of those (n = 3,462) come from a single publication.",
    feat=None, direction="caution", effect="91% of 3,767 PAMPA records from one publication",
    quote="among which 91% of the datapoints (n = 3462) are from one publication",
    confidence="high", notes="same single-source dominance we found in CycPeptMPDB (two labs hold most hits)")
add(id="LIT-PEP-001", pmcid="PMC11698989", tier="T2", kind="fundamental", scope=["cyclic peptides vs nonpeptidic macrocycles","descriptors"], outcome="chemical space",
    statement="Cyclic peptides are typically larger, more polar (higher TPSA and HBD) and more flexible than nonpeptidic macrocycles, which are somewhat more lipophilic.",
    feat=None, direction="context", effect=None,
    quote="most cyclic peptides were larger, more polar (higher TPSA and HBD count) and more flexible (higher Kier index, Φ) than the nonpeptidic macrocycles",
    confidence="high", notes="")
add(id="LIT-CYC-001", pmcid="PMC12606850", tier="T2", kind="fundamental", scope=["cyclic vs linear peptide","chameleonicity"], outcome="permeability",
    statement="The increased permeability of cyclic peptides relative to linear peptides is attributed to chameleonic propensity (open conformation in water, closed conformation in lipid).",
    feat={"is_cyclic": +1}, direction="+", effect=None,
    quote="increased permeability relative to linear peptides can be attributed to their chameleonic propensity",
    confidence="medium", notes="")
