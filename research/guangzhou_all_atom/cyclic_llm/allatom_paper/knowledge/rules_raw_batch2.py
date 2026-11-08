from rules_raw_batch1 import add, R  # noqa  (same registry)
add(id="LIT-IMHB-005", pmcid="PMC13370866", tier="T1", scope=["semipeptidic macrocycle","intramolecular interaction"], outcome="permeability",
    statement="Macrocycles that form intramolecular NH-pi interactions and hydrogen bonds were more permeable than matched pairs unable to form them.",
    feat={"exposed_nh": -1}, direction="-", effect=None,
    quote="Macrocycles that formed intramolecular NH-π interactions and hydrogen bonds were more permeable than matched pairs unable to form such interactions",
    confidence="high", notes="Caco-2; four semipeptidic series")
add(id="LIT-IMHB-006", pmcid="PMC13370866", tier="T1", scope=["18-membered macrocycle","NH shielding"], outcome="permeability",
    statement="Shielding of one amide NH through chameleonic intramolecular interaction with a side chain raised permeability by 0.55 log units on average (3.5-fold) in some 18-membered macrocycles.",
    feat={"exposed_nh": -1}, direction="-", effect="+0.55 log units (3.5-fold)",
    quote="led to a permeability increase that, on average, amounted to 0.55 logarithmic units, i.e., a 3.5-fold increase",
    confidence="high", notes="series 1 only")
add(id="LIT-CHAM-001", pmcid="PMC13370866", tier="T2", scope=["bRo5","chameleonicity","oral absorption"], outcome="oral absorption",
    statement="Molecular chameleonicity was reported to give up to 2-fold better oral absorption for compounds of 800-1000 Da.",
    feat=None, direction="+", effect="up to 2-fold",
    quote="up to a 2-fold improvement in oral absorption for compounds in the 800-1000 Da MW range",
    confidence="medium", notes="cited by the paper from earlier work")
add(id="LIT-TPSA-001", pmcid="PMC12670408", tier="T1", scope=["Sanguinamide A analogues","TPSA"], outcome="permeability",
    statement="Within a congeneric cyclic-peptide series, static topological polar surface area was a poor predictor of permeability while cLogP correlated somewhat.",
    feat=None, direction="caution", effect=None,
    quote="topological polar surface area (tPSA) was found to be a poor predictor of permeability for these compounds",
    confidence="medium", notes="counter-evidence to a global TPSA rule inside congeneric series")
add(id="LIT-HBD-001", pmcid="PMC12670408", tier="T2", scope=["cyclic peptide","HBD","size"], outcome="permeability",
    statement="Adding a hydrogen-bond donor and enlarging the macrocycle are generally expected to lower membrane permeability.",
    feat={"hbd": -1, "n_heavy_atoms": -1}, direction="-", effect=None,
    quote="an extra HBD as well as increased the macrocycle size, both of which are often detrimental for membrane permeability",
    confidence="medium", notes="background statement by the authors")
add(id="LIT-LIP-001", pmcid="PMC13173399", tier="T1", scope=["cyclic heptapeptide","lipophilicity"], outcome="permeability",
    statement="Permeability is non-monotonic in lipophilicity: beyond an optimum, cyclic heptapeptides lose permeability by falling off a solubility cliff.",
    feat={"alogp": 0}, direction="window", effect=None,
    quote="many cyclic heptapeptides showed dramatically lower permeability, suggesting that these compounds had fallen off a 'solubility cliff'",
    confidence="high", notes="use as a window (peak) potential, not a monotone one")
add(id="LIT-SEQ-001", pmcid="PMC13173399", tier="T1", scope=["cyclic heptapeptide","sequence order"], outcome="permeability",
    statement="Side-chain rearrangement among isomers of the same composition changed permeability up to 30-fold.",
    feat=None, direction="context", effect="up to 30-fold",
    quote="showed up to 30-fold increases in permeability relative to the lowest rate",
    confidence="high", notes="composition-only descriptors cannot capture this")
add(id="LIT-STER-001", pmcid="PMC13173399", tier="T1", scope=["cyclic heptapeptide","stereochemistry","lipophilicity"], outcome="lipophilicity",
    statement="Among all stereoisomeric backbones of the mortiamide heptapeptide, the natural scaffold was among the two most lipophilic by hydrocarbon-water partition.",
    feat=None, direction="context", effect=None,
    quote="the natural product's scaffold was among the two most lipophilic as measured by hydrocarbon-water partition coefficients",
    confidence="medium", notes="stereochemical inversion changes lipophilicity")
add(id="LIT-STER-002", pmcid="PMC13173399", tier="T1", scope=["cyclic heptapeptide","epimer","solubility"], outcome="aqueous solubility",
    statement="Epimers of mortiamides A and D had over 100-fold greater aqueous solubility than the natural isomers.",
    feat={"n_dres": +1}, direction="context", effect=">100-fold solubility",
    quote="the epimers of mortiamides A and D exhibited over 100-fold greater aqueous solubility than their natural isomers",
    confidence="medium", notes="two compounds; direction not generalisable to every D-substitution")
add(id="LIT-AGG-001", pmcid="PMC13173399", tier="T1", scope=["cyclic heptapeptide","aggregation"], outcome="aggregation liability",
    statement="Lipophilic cyclic heptapeptides of the mortiamide family have very low aqueous solubility and form amyloid-like fibrils; apparent bioactivity can be driven by colloidal aggregation.",
    feat={"alogp": +1}, direction="context", effect=None,
    quote="have very low aqueous solubilities and form amyloid-like fibril aggregates",
    confidence="high", notes="liability flag for highly lipophilic cyclic peptides")
add(id="LIT-LIP-002", pmcid="PMC10885153", tier="T1", scope=["thioether-cyclized 10-mer","lipophilicity"], outcome="permeability",
    statement="Thioether-cyclized 10-mer peptide-peptoid hybrid scaffolds have an optimal lipophilicity (ALogP) range for permeability, and the position of the N-substituted residue shifts the peak.",
    feat={"alogp": 0}, direction="window", effect=None,
    quote="We identified the optimal lipophilicity range for achieving permeability in thioether-cyclized 10-mer cyclic peptide-peptoid hybrid scaffolds",
    confidence="high", notes="peak ALogP differs by scaffold (turn vs strand placement)")
add(id="LIT-SOL-001", pmcid="PMC10885153", tier="T1", scope=["thioether-cyclized 10-mer","solubility"], outcome="aqueous solubility",
    statement="Aqueous solubility of the three scaffolds decreased with increasing ALogP.",
    feat={"alogp": -1}, direction="-", effect=None,
    quote="the aqueous solubilities of all three scaffolds decreased as a function of increasing ALogP",
    confidence="high", notes="")
add(id="LIT-BASE-001", pmcid="PMC10885153", tier="T1", scope=["thioether-cyclized 10-mer","base rate"], outcome="permeability",
    statement="Most of 210 thioether-cyclized 10-mers fell below the conventional Papp ~1e-6 cm/s permeability threshold; few were exceptionally permeable.",
    feat=None, direction="context", effect="Papp threshold ~1e-6 cm/s",
    quote="the bulk of the 210 compounds analyzed in this work falls below the conventional threshold",
    confidence="high", notes="base rate: random cyclic peptides are usually not permeable")
add(id="LIT-RO5-001", pmcid="PMC11411612", tier="T2", scope=["small molecule","oral absorption","Ro5"], outcome="oral absorption",
    statement="Lipinski rule of 5: oral absorption is less likely when two or more of MW > 500, cLogP > 5, HBD > 5, HBA > 10 hold.",
    feat={"mw": -1, "clogp": -1, "hbd": -1, "hba": -1}, direction="window", effect=None, window={"mw_max": 500, "clogp_max": 5, "hbd_max": 5, "hba_max": 10, "max_violations": 1},
    quote="oral absorption is less likely for compounds that have two or more of MWt >500, clog P >5, HBD >5 and HBA >10",
    confidence="high", notes="small-molecule baseline; peptides intentionally violate it")
add(id="LIT-RO5-002", pmcid="PMC11411612", tier="T1", scope=["FDA oral drugs 2000-2022"], outcome="oral drug property limits",
    statement="Limits derived from the 90th percentile of FDA-approved oral drugs 2000-2022 would be MW < 589 Da, cLogP < 5.8, HBD < 4 and HBA < 10.",
    feat={"mw": -1, "clogp": -1, "hbd": -1, "hba": -1}, direction="window", effect=None, window={"mw_max": 589, "clogp_max": 5.8, "hbd_max": 4, "hba_max": 10},
    quote="if they had been derived from this dataset, the rules would be MWt < 589 Da, clog P < 5.8, HBD < 4 and HBA < 10",
    confidence="high", notes="oral drugs, mostly non-peptide")
add(id="LIT-DEPS-001", pmcid="PMC11348715", tier="T1", scope=["cyclic depsipeptide","sequence pattern"], outcome="permeability",
    statement="In ent-verticilide analogues, isomers with adjacent didepsipeptide units were more permeable than alternating isomers.",
    feat=None, direction="context", effect="adjacent >19% vs alternating <16% diffusion",
    quote="all adjacent isomers exhibited higher permeability (>19%), while all alternating isomers exhibited lower permeability (<16%)",
    confidence="medium", notes="series-specific; shows sequence-pattern effects")
add(id="LIT-NH-001", pmcid="PMC11348715", tier="T1", scope=["cyclic depsipeptide","ester","N-H amide"], outcome="permeability",
    statement="In a verticilide-derived series the analogue with highest permeability came from a single ester-to-N-H amide replacement, so ester content alone does not determine permeability.",
    feat=None, direction="context", effect=None,
    quote="the analog with highest Papp was discovered by a single ester-to-N-H amide replacement",
    confidence="medium", notes="counter-example to monotone NH or ester rules")
