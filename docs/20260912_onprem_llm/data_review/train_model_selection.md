# TRAIN task: model_selection  (330 instances)

## [0] source=multitask_sft_big

**USER:** I have five optimized lead compounds for an oncology target (SMILES provided). Could you run in silico profiling to predict their hERG channel inhibition risk, CYP450 liability (specifically CYP3A4 and CYP2D6 inhibition), and estimated human oral bioavailability to help us prioritize molecules for downstream in vitro validation?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (e.g., Chemprop / ADMET-AI): Can provide rapid, structure-based screening to rank small-molecule candidates by probability of hERG liability, CYP isozyme inhibition, and general oral absorption potential within the model's chemical applicability domain. Cannot provide definitive regulatory safety clearance, simulate dynamic in vivo pharmacokinetic profiles (e.g., exact Cmax, clearance rates, or formulation/food effects), or reliably evaluate non-standard modalities such as macrocycles, PROTACs, or biologics.

---

## [1] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation (p.Val600Glu in BRAF / or a novel VUS p.Arg248Gln in TP53) in an oncology patient with no clear ClinVar entry. Can you predict whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Pretrained missense variant pathogenicity predictor (e.g., AlphaMissense, ESM-1v): Can evaluate the functional impact and relative likelihood of pathogenicity for single nucleotide variants causing missense mutations by leveraging evolutionary conservation and structural context; cannot evaluate non-coding variants, insertions/deletions, or structural variations, nor can it determine clinical penetrance, patient-specific phenotypic severity, or replace clinical ACMG/AMP variant interpretation guidelines.

---

## [2] source=multitask_sft_big

**USER:** We identified a novel missense variant in the BRCA1 gene (c.5095C>T, p.Arg1699Trp) in a patient with early-onset breast cancer. Can you predict the functional impact and clinical pathogenicity of this substitution on the BRCT domain?

**ASSISTANT:** Deep Learning Variant Effect Predictor / Protein Language Model (e.g., AlphaMissense, ESM-1v): Can speak to: The structural tolerance, biochemical disruption, and predicted probability of a single amino acid substitution being deleterious or benign based on evolutionary sequence conservation and predicted 3D protein structure. Cannot speak to: Definitive clinical classification without functional assay validation, patient-specific disease penetrance or expressivity, non-coding/synonymous/splicing alterations, or complex polygenic and environmental risk factors.

---

## [3] source=multitask_sft_big

**USER:** I identified a novel de novo missense mutation in SCN1A (p.Met1522Lys) in a pediatric patient presenting with treatment-resistant focal seizures. Could you run an in silico pathogenicity prediction to determine if this specific amino acid substitution is likely to be disease-causing?

**ASSISTANT:** AlphaMissense (Pretrained deep learning model for missense variant pathogenicity classification): Can: Predict whether missense (single amino acid substitute) variants are likely pathogenic or benign based on structural context and evolutionary conservation; provide calibrated continuous pathogenicity scores. Can't: Evaluate non-coding variants, indels, frameshifts, or synonymous mutations; determine splicing alterations; predict specific clinical phenotypes, penetrance, or functional consequences (e.g., gain-of-function vs. loss-of-function); replace comprehensive ACMG/AMP clinical variant classification guidelines.

---

## [4] source=multitask_sft_big

**USER:** Here is the amino acid sequence of an uncharacterized 320-residue enzyme from an extremophile: [sequence omitted for brevity: MGSSHHHHHHSSGLVPRGSHM...]. Can you predict its static 3D tertiary structure, highlight active-site clefts, and output the PDB coordinates along with confidence metrics?

**ASSISTANT:** Evoformer-based Protein Structure Predictor (e.g., AlphaFold2, OpenFold) or Protein Language Model with Structure Module (e.g., ESMFold): Can predict high-accuracy static 3D Cartesian atomic coordinates, secondary structure motifs, domain folds, and per-residue confidence scores (pLDDT, PAE). Cannot speak to dynamic conformational ensembles, folding kinetics, or structural changes dependent on unmodeled cofactors, metal ions, post-translational modifications, or specific environmental conditions (e.g., pH, temperature, membrane lipid bilayer).

---

## [5] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant, c.1747C>T (p.His583Tyr), in the LDLR gene of a patient with suspected familial hypercholesterolemia. Can you predict whether this amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Pretrained Protein Language Model / Structural Missense Variant Predictor (e.g., AlphaMissense, ESM-1v): Can speak to: The quantitative likelihood that an individual missense substitution disrupts protein structure and function, based on evolutionary conservation and protein 3D structural context. Cannot speak to: Non-coding, synonymous, frameshift, or splicing variants; penetrance and variable expressivity; epigenetic or environmental interactions; and it cannot provide a definitive clinical diagnosis or replace ACMG/AMP classification guidelines without orthogonal clinical and functional evidence.

---

## [6] source=multitask_sft_big

**USER:** I have an AnnData matrix of preprocessed scRNA-seq counts from human peripheral blood mononuclear cells (PBMC). Can you annotate the specific cell types for each barcode based on these expression profiles?

**ASSISTANT:** Pretrained Single-Cell Foundation Transformer (e.g., scGPT or Geneformer fine-tuned for cell type classification): Can speak to: Assigning probabilistic cell-type annotations, mapping latent transcriptomic embeddings, identifying known cell lineages, and handling batch-corrected gene expression patterns seen in reference atlases. Cannot speak to: Reliably identifying novel or rare cell states absent from the pretraining data, determining underlying causal regulatory mechanisms, confirming true post-transcriptional protein abundance, or accurately classifying low-quality cells such as empty droplets or doublets.

---

## [7] source=multitask_sft_big

**USER:** I have sequenced an uncharacterized 245-amino-acid esterase from a metagenomic sample: MVLSEGEWQLVLHVWAKVEADVAGHGQDILIRLFKSHPETLEKFDRFKHLKTEAEMKASEDLKKHGVTVLTALGAILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSRHPGDFGADAQGAMNKALELFRKDIAAKYKELGYQG. Can you predict its 3D atomic coordinates in PDB format and output the per-residue confidence scores?

**ASSISTANT:** AlphaFold2 (Evoformer-based protein structure prediction network) or ESMFold (Language-model-based structural predictor): Can predict static ground-state tertiary (and multimeric) 3D atomic coordinates, backbone and side-chain orientations, and provide per-residue/inter-residue confidence metrics (pLDDT, PAE). Cannot reliably predict dynamic conformational ensembles, folding pathways, the destabilizing free-energy impacts of single-point mutations (ΔΔG), covalent post-translational modifications, or binding affinities with non-protein ligands/cofactors.

---

## [8] source=multitask_sft_big

**USER:** I have a library of 150 small-molecule kinase inhibitor leads formatted as SMILES strings. Can you predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) to help us triage candidates before submitting them to in vitro ADME assays?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Molecular Transformer (e.g., ChemBERTa) fine-tuned on ADME benchmark datasets (such as AqSolDB and ChEMBL logD sets): Can speak to: Relative ranking of drug-like small molecules, quantitative estimation of intrinsic aqueous solubility (logS) and distribution coefficients (logD7.4) based on 2D molecular graph topology or SMILES representations, and flag scaffold-based lipophilicity trends. Can't speak to: Dynamic solid-state/crystal packing forces affecting kinetic solubility, specific buffer effects or ionic strength variations, metallo-organic complexes, macrocycles outside standard chemical space, or downstream in vivo pharmacokinetic behavior (e.g., actual human bioavailability, clearance).

---

## [9] source=multitask_sft_big

**USER:** We have 20 lead optimization analogs (provided as SMILES) for our oncology program. Could you screen these compounds for cardiac safety via hERG channel inhibition risk, determine their inhibition profiles across major CYP isoforms (CYP3A4, CYP2D6, CYP2C9), and predict their likelihood of achieving >30% human oral bioavailability?

**ASSISTANT:** Multitask Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop or ADMET-AI trained on TDC/ChEMBL benchmarks): Can rapidly predict in silico endpoint probabilities for hERG liability (IC50 thresholding), binary CYP450 enzyme inhibition, and categorical/continuous oral bioavailability based on 2D molecular graph features. Cannot simulate complex whole-body physiologically based pharmacokinetics (PBPK), time-dependent or mechanism-based enzyme inactivation, dynamic active transporter interactions (e.g., tissue-specific P-gp/OATP efflux), specific metabolite structures, or reliably generalize to molecular classes far outside its small-molecule training domain (such as PROTACs, large macrocycles, or peptides).

---

## [10] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from a 10x Genomics 3' scRNA-seq dataset of human peripheral blood mononuclear cells (~20,000 cells). Can you use a pretrained model to automatically identify and annotate the specific cell types across our clusters?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer) fine-tuned for cell-type annotation: Can reliably map gene expression profiles to known canonical cell types and fine-grained lineages represented in its pretraining/reference atlas, capturing complex non-linear gene relationships. Cannot reliably identify novel or rare disease-specific cell types absent from the reference data (tends to force-predict closest known classes), infer tissue spatial architecture, or resolve cell states that depend strictly on surface proteomic or epigenetic differences not reflected in transcript abundance.

---

## [11] source=multitask_sft_big

**USER:** I have a batch of novel small-molecule kinase inhibitors provided as SMILES strings. Could you predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) so we can filter out compounds likely to have poor oral bioavailability before synthesis?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) or Molecular Transformer (e.g., Chemprop / ChemBERTa fine-tuned on ADMET benchmarks like TDC): Can speak to: In silico estimates of intrinsic aqueous solubility (logS), lipophilicity and membrane partitioning at neutral pH (logD7.4), and relative property ranking within known chemical spaces. Cannot speak to: Solid-state polymorph stability, vehicle/excipient formulation effects, experimental buffer-specific salt precipitations, or complex dynamic in vivo pharmacokinetic behavior.

---

## [12] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (chr2:166014022, G>A, p.Arg1648His) in a child presenting with early-onset seizures. Can you predict whether this specific variant is likely pathogenic or benign?

**ASSISTANT:** Protein language/structure-informed variant effect predictor (e.g., AlphaMissense, ESM1b/EVE): Can quantify the likelihood that a missense substitution disrupts protein structure and function based on evolutionary constraints and structural biology. Cannot provide a definitive clinical diagnosis, determine clinical penetrance/severity, account for non-coding regulatory effects or complex modifier genes, or replace functional validation and standard ACMG/AMP clinical evaluation guidelines.

---

## [13] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in SCN1A (c.3811G>A, p.Gly1271Arg) in an infant presenting with early-onset seizures. Can you predict whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Protein Language Model / Deep Learning Variant Effect Predictor (e.g., AlphaMissense, ESM-1b/ESM-2 zero-shot variant effect predictor): Can: Predict the structural and biochemical disruption of single amino acid substitutions and score the likelihood of missense variant pathogenicity using evolutionary constraint and structural context. Can't: Evaluate non-coding variants, splicing defects, or indels; determine patient-specific penetrance, inheritance expressivity, or clinical phenotype; or replace empirical functional assays and ACMG/AMP clinical diagnostic criteria.

---

## [14] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix (10x Genomics) from human peripheral blood mononuclear cells with ~15,000 cells. Can you run this through a pretrained model to predict the fine-grained cell type labels for each cell?

**ASSISTANT:** Single-cell foundation transformer fine-tuned for cell-type classification (e.g., scGPT or Geneformer): Can assign high-confidence cell-type identities based on learned gene expression representations, identify canonical cell lineages, and handle batch-effect variations present in reference atlases; cannot reliably classify novel or rare disease states absent from training sets, capture spatial organization, or infer non-transcriptional phenotypes (such as post-translational modifications or surface protein abundance) without multi-omic data.

---

## [15] source=multitask_sft_big

**USER:** Here is the amino acid sequence for an uncharacterized bacterial membrane enzyme: 'MKTIIALSYIFCLVFADYKDDDD...'. Can you generate its predicted 3D atomic coordinates in PDB format and provide per-residue confidence scores to help us locate the active site?

**ASSISTANT:** SE(3)-equivariant transformer-based protein structure prediction model (e.g., AlphaFold2, ESMFold): Can predict static tertiary backbone and side-chain atomic coordinates, domain orientations, and model confidence metrics (such as pLDDT and PAE). Cannot predict non-equilibrium folding kinetics, full conformational ensembles across physiological states, or structural effects mediated by explicit environmental conditions, post-translational modifications, and small-molecule cofactors.

---

## [16] source=multitask_sft_big

**USER:** We recently isolated an uncharacterized 380-amino-acid metalloprotease from a deep-sea hydrothermal vent bacterium. Here is the primary FASTA sequence: 'MKTVILSLAL...'. Can you generate the predicted 3D atomic coordinates (PDB format) along with per-residue confidence scores to evaluate the folding of the active site?

**ASSISTANT:** Evoformer-based structural prediction neural network (e.g., AlphaFold2, ESMFold): Can reliably predict static 3D backbone/side-chain coordinates, secondary structure, and domain topologies from sequence or multiple sequence alignments (MSAs), providing per-residue confidence (pLDDT) and predicted alignment errors (PAE). Cannot accurately capture dynamic conformational ensembles, folding kinetics, energetic stability changes from arbitrary point mutations, or coordinate binding of novel non-covalent cofactors/ligands without specialized complex-modeling inputs.

---

## [17] source=multitask_sft_big

**USER:** I have an AnnData object containing raw count scRNA-seq profiles from human peripheral blood mononuclear cells (PBMCs). Could you identify and predict the specific cell type for each cell barcode using a transfer learning approach?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer): Can accurately assign discrete cell-type labels across diverse tissues, generalize to unseen sequencing batches, and capture non-linear gene-gene regulatory dependencies. Cannot reliably identify novel or non-characterized cell types absent from the reference/training taxonomy, infer temporal or lineage dynamics from a single static snapshot, or overcome severe dropouts and sequencing artifacts in low-quality libraries without proper upstream QC.

---

## [18] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix (10x Genomics) with ~15,000 cells from human peripheral blood mononuclear cells (PBMCs). Could you identify and assign the fine-grained immune cell types (e.g., CD4+ naive T cells, classical monocytes, NK cells) for each individual cell barcode?

**ASSISTANT:** Pretrained single-cell foundation model fine-tuned for cell-type annotation (e.g., scGPT or Geneformer) / CellTypist: Can reliably predict discrete canonical cell-type identities, map cells to standardized reference ontologies, and generalize across standard scRNA-seq platforms for represented cell lineages. Cannot reliably identify novel or rare uncharacterized cell types absent from the reference data, directly infer spatial context or downstream protein abundance, or overcome severe batch effects and low sequencing depth without prior quality control.

---

## [19] source=multitask_sft_big

**USER:** I have identified several novel missense mutations in the BRCA1 and TP53 genes from exome sequencing of a patient cohort, specifically including BRCA1 p.C61G and TP53 p.R248Q. Could you predict the pathogenicity scores for these amino acid substitutions to help prioritize them for functional validation?

**ASSISTANT:** Deep learning-based missense variant effect predictor (e.g., AlphaMissense, EVE, or ESM-1v/ESM-2 zero-shot variant effect predictor): Can speak to the likelihood that a specific single amino acid substitution disrupts protein structure or molecular function based on evolutionary conservation and structural constraints. Cannot speak to definitive clinical diagnosis, disease penetrance, tissue-specific expressivity, non-coding or structural variants (e.g., indels, splicing defects), or patient-specific clinical outcomes without integrated phenotypic and genetic evidence.

---

## [20] source=multitask_sft_big

**USER:** I have a raw count matrix from a 10x Genomics single-cell RNA-seq run of human peripheral blood mononuclear cells (PBMCs). I need to automatically annotate and assign cell-type labels to each individual cell barcode based on their gene expression profiles.

**ASSISTANT:** Pretrained Single-Cell Foundation Model (Transformer-based, e.g., scGPT or Geneformer fine-tuned for cell-type annotation): Can accurately infer discrete cell lineages, canonical cell-type identities, and activation states from transcriptomic counts while generalizing across technical batches. Cannot directly determine spatial tissue context, post-translational protein modifications, epigenetic chromatin accessibility, or clinical disease prognosis without additional multimodal data and clinical metadata.

---

## [21] source=multitask_sft_big

**USER:** I have five optimized lead compounds for an oncology target represented as SMILES strings. Could you run an in silico ADMET panel to predict their potential cardiotoxicity via hERG liability, CYP450 enzyme inhibition profile (specifically CYP3A4 and CYP2D6), and estimate their human oral bioavailability (F > 30%) before we commit to in vitro assays?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN / Chemprop) fine-tuned on ADMET benchmarks (e.g., Therapeutics Data Commons / TDC): Can speak to: Statistical probabilities and binary/regressive predictions for hERG cardiotoxicity, metabolic clearance liabilities across major CYP isoforms, and categorical/percentage human oral bioavailability derived from structural representations within standard drug-like chemical space. Can't speak to: Dynamic in vivo pharmacokinetic/pharmacodynamic (PK/PD) time-course concentration profiles, formulation- or salt-form-dependent solubility effects, systemic multi-organ drug-drug interactions, non-canonical metabolism pathways, or reliable predictions on chemical scaffolds outside the model's training distribution.

---

## [22] source=multitask_sft_big

**USER:** I have docked a library of 50 small-molecule kinase inhibitors into the ATP-binding pocket of EGFR (PDB: 1M17). Could you predict the binding affinity (Kd or pIC50) for each ligand pose and rank the top five candidates for experimental synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (SE(3)/E(3)-GNN) for protein-ligand complexes (e.g., GNINA, TankBind, or EquiBind-derived scoring architectures): Can reliably score and rank relative binding affinities (e.g., pKd/pKi) based on spatial coordination, hydrogen bonding, and shape complementarity from 3D co-complex poses. Cannot account for full thermodynamic entropic penalties, long-timescale induced-fit conformational changes, explicit solvent/desolvation dynamics without explicit simulation, or predict downstream functional efficacy (agonist vs. antagonist behavior).

---

## [23] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix from a human peripheral blood mononuclear cell (PBMC) sample sequenced on the 10x Genomics Chromium platform. Can you run this profile through a pretrained foundation model to classify the cell type for each individual cell barcode?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer) / Geneformer fine-tuned for cell-type classification: Can speak to: Assigning cell-type labels and lineage identities for common, canonical cell states present in the pretraining and fine-tuning reference atlases; robustly modeling gene co-expression patterns and handling technical dropouts/batch variations common in 10x scRNA-seq data. Cannot speak to: Reliably identifying novel or uncharacterized cell types absent from the reference training distribution (often forcing false-positive assignments); determining spatial context or tissue architecture; inferring definitive causal molecular mechanisms or dynamic functional behavior without experimental orthogonal validation.

---

## [24] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human kinase CDK2 (PDB: 1HCK) and a list of 50 SMILES strings for novel ATP-competitive inhibitors. Can you predict the binding affinity (pKd or pIC50) for each protein-ligand pair to help rank candidates for our upcoming synthesis run?

**ASSISTANT:** 3D Equivariant Geometric Deep Learning / Cross-Attention Graph Neural Network (e.g., TankBind, EquiBind, GNINA): Can reliably predict: relative binding ranks, estimated affinity metrics (e.g., pKd, Ki), and residue-level binding site interaction poses. Cannot speak to: binding kinetics (on/off rates), thermodynamic entropy contributions, induced-fit conformational changes beyond rigid/semi-rigid docking, or downstream ADMET properties like membrane permeability and off-target cytotoxicity.

---

## [25] source=multitask_sft_big

**USER:** I have an unannotated 10x Genomics scRNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs) with ~15,000 cells. Can you run an automated model to predict and assign fine-grained cell-type labels (e.g., CD4+ naive T cells, NK cells, classical monocytes) to each single cell barcode?

**ASSISTANT:** scGPT (single-cell Generative Pretrained Transformer): What it can speak to: It can infer discrete cell-type classifications and cell state embeddings by leveraging cross-dataset gene-gene attention and transfer learning from large single-cell atlases, robustly handling dropout and technical batch effects. What it can't speak to: It cannot directly infer surface protein levels (CITE-seq), post-transcriptional modifications, spatial context, or definitively annotate ultra-rare or disease-specific novel subtypes that lie far outside the pretraining distribution without fine-tuning.

---

## [26] source=multitask_sft_big

**USER:** I have the 3D crystal structure of our kinase target (PDB format) and a library of 50 novel small-molecule analog leads in an SDF file. Can you predict the binding affinity (pK_d / IC50) for each complex, rank the compounds, and identify the key interaction hotspots in the binding pocket?

**ASSISTANT:** 3D Equivariant/Geometric Graph Neural Network (e.g., Uni-Mol, GNINA, or PIGNet): Can speak to: Relative binding affinity ranking, quantitative binding energy estimations (pK_d/pK_i), 3D spatial complementarity, and feature importance of specific residue-atom contacts in rigid or semi-rigid binding conformations. Cannot speak to: Induced-fit conformational dynamics over time (dynamic flexibility without explicit MD simulations), complete entropic solvation thermodynamics, covalent inhibition chemistry, or downstream pharmacokinetics and off-target biological toxicity.

---

## [27] source=multitask_sft_big

**USER:** I have an uncharacterized 340-amino-acid sequence for a putative bacterial transglycosylase (starts with MKTIIALSYIFCLVFA...). Can you generate the predicted 3D Cartesian coordinates for this protein, output a PDB file, and provide per-residue confidence metrics so I can assess whether the catalytic pocket is modeled reliably?

**ASSISTANT:** AlphaFold2 / ESMFold (Evoformer- and protein language model-based 3D structure prediction architectures): Can accurately predict static, ground-state 3D atomic coordinates (backbone and side chains) and provide local/global confidence metrics (pLDDT, PAE). Cannot model dynamic conformational landscapes, non-protein ligand/cofactor interactions without specialized extensions, absolute folding kinetics, or the functional enzymatic activity of the predicted site.

---

## [28] source=multitask_sft_big

**USER:** I am working on lead optimization for a series of small-molecule kinase inhibitors. Could you predict the aqueous solubility (LogS) and distribution coefficient at physiological pH (LogD7.4) for this compound: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5?

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN) / Molecular Graph Transformer (e.g., Chemprop or ChemBERTa fine-tuned on ADMET datasets): Can reliably predict intrinsic aqueous solubility (LogS), lipophilicity trends (LogP/LogD), and general ADMET physicochemical properties for small drug-like molecules within the model's chemical training domain. Cannot account for specific solid-state crystal lattice energy, polymorphism, salt forms, kinetic dissolution rates, precipitation dynamics, or matrix effects caused by formulation excipients, buffers, and co-solvents.

---

## [29] source=multitask_sft_big

**USER:** I have the crystal structure of the SARS-CoV-2 main protease (Mpro) in PDB format and a set of 50 newly designed peptidomimetic inhibitor candidates as SMILES strings. Can you predict the binding affinity (pK_d or Delta G) for each candidate in the active site and rank them?

**ASSISTANT:** 3D Structure-Based Protein-Ligand Graph Neural Network (e.g., GNINA, TankBind, EquiBind): Can speak to: quantitative relative binding affinities (e.g., pKd, Ki, or delta G scores), ranking of ligand poses within a designated pocket, and identification of key contact residues. Cannot speak to: functional efficacy (agonist vs. antagonist mechanisms), downstream cellular activity (IC50 in vivo), ADMET properties (toxicity, metabolic stability, membrane permeability), or entropy/water dynamics that require explicit-solvent molecular dynamics.

---

## [30] source=multitask_sft_big

**USER:** I have designed a series of small-molecule lead compounds against a kinase target, with the primary candidate represented by the SMILES string 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'. Could you run an ADMET profiling to predict its cardiotoxicity risk via hERG inhibition, its metabolic liability across major CYP450 enzymes (specifically CYP3A4 and CYP2D6), and its estimated human oral bioavailability percentage?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN / Chemprop) fine-tuned on ADMET benchmarks (e.g., Therapeutics Data Commons / ChEMBL): Can reliably predict qualitative and semi-quantitative in silico endpoints for drug-like small molecules, including probability of hERG-mediated QT prolongation, substrate/inhibitor interaction with specific CYP isoforms, and standard categorical or continuous oral bioavailability (F%) based on structural features. Cannot account for formulation dynamics (e.g., amorphous solid dispersions), food-effect variations, multi-organ physiological clearance, active intestinal transporter saturation (e.g., P-glycoprotein non-linearities), or replace mandatory wet-lab patch-clamp and in vivo pharmacokinetic safety assays.

---

## [31] source=multitask_sft_big

**USER:** We have synthesized five lead analogs (provided as SMILES strings) for our oncology target. Could you run an in silico ADMET panel to predict their potential cardiotoxicity (specifically hERG potassium channel inhibition), CYP profiling (inhibition of CYP3A4, CYP2D6, and CYP2C9), and estimate their human oral bioavailability percentage?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop/ADMET-AI trained on TDC benchmarks): Can provide rapid, early-stage in silico classification of small-molecule cardiotoxicity risk (hERG liability), predict inhibition/substrate status across major CYP450 isoforms, and estimate relative human oral bioavailability (%F) based on molecular graph representations. Cannot account for complex in vivo pharmacokinetic dynamics (such as non-linear clearance, tissue-specific distribution, or carrier-mediated transport), active metabolite toxicity, physiological variability across patient populations, or physical formulation effects (e.g., salt forms, crystal polymorphism, or solubility enhancers) without wet-lab in vitro and in vivo validation.

---

## [32] source=multitask_sft_big

**USER:** We have designed a library of 40 novel small-molecule lead candidates represented as SMILES strings. Could you run an in silico ADMET screen to prioritize them based on cardiotoxicity risk (hERG IC50 liability), metabolic profile (CYP3A4 and CYP2D6 inhibition/clearance), and predicted human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Graph Transformer fine-tuned on benchmark ADMET datasets (e.g., TDC, ChEMBL): Can speak to: Rapid ranking and binary/continuous risk scoring for primary ADMET endpoints (hERG liability, CYP substrate/inhibitor probability, oral absorption classes) based on 2D chemical structure within the model's training applicability domain. Cannot speak to: In vivo physiological complexity (formulation-dependent solubility, active transport/P-gp efflux kinetics, species-specific clearance discrepancies), 3D stereochemical binding dynamics, or safety profiles for novel chemical matter residing outside of the reference chemical space.

---

## [33] source=multitask_sft_big

**USER:** I have an AnnData object containing 10x Genomics scRNA-seq expression counts from human peripheral blood mononuclear cells (PBMCs). Could you identify the cell type label for each individual cell using its transcriptional profile?

**ASSISTANT:** Pretrained Single-Cell Foundation Transformer (e.g., scGPT, Geneformer): Can speak to identifying canonical and high-prevalence cell types represented in reference cell atlases, resolving hierarchical immune lineages, and inferring labels robust to standard technical batch variations. Cannot speak to uncharacterized or novel cell states not present in the pretraining/reference corpora, functional cellular dynamics or causal signaling not captured by steady-state transcript abundance, spatial microenvironment interactions, or non-transcriptomic regulatory mechanisms (e.g., post-translational protein modifications, chromatin accessibility).

---

## [34] source=multitask_sft_big

**USER:** Here is an uncharacterized 145-amino-acid sequence from a marine metagenomic screen: 'MVLSEGEWQLVLHVWAKVEADVAGHGQDILIRLFKSHPETLEKFDRFKHLKTEAEMKASEDLKKHGVTVLTALGAILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSRHPGDFGADAQGAMNKALELFRKDIAAKYKELGYQG'. Can you predict its 3D tertiary structure, output the atomic coordinates in PDB format, and give me the confidence score for each residue?

**ASSISTANT:** AlphaFold2 / ESMFold (Transformer-based Protein Structure Prediction Model): Can reliably predict static 3D atomic coordinates (PDB/mmCIF), backbone and side-chain conformations, domain interactions, and provide per-residue confidence scores (pLDDT) and pairwise alignment errors (PAE). Cannot simulate dynamic folding kinetics, time-resolved conformational changes, non-covalent interactions with unmodeled small-molecule ligands/cofactors, or structural distortions caused by post-translational modifications (PTMs).

---

## [35] source=multitask_sft_big

**USER:** We are optimizing a lead series of small-molecule kinase inhibitors. Here is a list of 50 SMILES strings. Can you profile them for cardiac safety via hERG channel inhibition (IC50 / block liability), predict their inhibition profile against major hepatic enzymes (CYP3A4, CYP2D6, CYP2C9), and estimate their human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN) / Multi-Task QSAR Graph Neural Network (e.g., Chemprop, ADMET-AI): Can speak to in silico statistical likelihoods of hERG liability, CYP450 isoform inhibition/substrate status, and systemic bioavailability categories based on learned 2D/3D chemical descriptors and benchmark training data (e.g., ChEMBL, TDC). Cannot speak to dynamic in vivo multi-compartment pharmacokinetic profiles, patient-specific metabolic differences (e.g., pharmacogenomics), dose-dependent transporter saturation, or non-standard modalities (e.g., biologics, large macrocycles, organometallics) falling outside the model's chemical applicability domain.

---

## [36] source=multitask_sft_big

**USER:** I have docked 25 candidate small molecules into the catalytic site of the human CDK2 crystal structure (PDB: 1HCK). Can you evaluate these protein-ligand complexes to predict their absolute binding affinity values (pKd/pKi) and rank them to prioritize compounds for in vitro kinase assay testing?

**ASSISTANT:** 3D Structure-Based Equivariant Graph Neural Network (e.g., TankBind, PIGNet, or GNINA CNN scoring functions): Can reliably score and rank protein-ligand complexes based on spatial and physicochemical complementarity within the binding pocket using learned structural features from databases like PDBbind. Cannot accurately predict binding kinetics (kon/koff rates), solvent entropy/desolvation dynamics, induced-fit conformational shifts absent from the input structure, or downstream functional efficacy (e.g., cell-based IC50, bioavailability, off-target toxicity).

---

## [37] source=multitask_sft_big

**USER:** We have five lead optimization candidates for an oncology target (SMILES provided). Could you run an in silico ADMET profile to evaluate their risk of cardiotoxicity via hERG inhibition, determine whether they act as inhibitors or substrates across major CYP isoforms (CYP3A4, CYP2D6, CYP2C9), and predict their percent oral bioavailability?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN) / QSAR Molecular Ensemble (e.g., ADMET-AI / Chemprop): Can rapidly predict statistical classifications and regression values for hERG channel blockade, CYP450 isoform inhibition/metabolic liability, and high vs. low oral bioavailability derived from 2D structural representations. Cannot predict full in vivo pharmacokinetic time-concentration curves (Cmax, AUC, Tmax) without PBPK integration, account for formulation effects/excipients, or reliably generalize to novel chemical scaffolds that lie outside the training set's applicability domain.

---

## [38] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (NM_001165963.4:c.3862G>A, p.Glu1288Lys) in a 6-month-old infant presenting with febrile status epilepticus. Can you predict the pathogenicity of this amino acid substitution and whether it is likely to cause loss of function or gain of function?

**ASSISTANT:** Protein-structure-informed variant effect predictor / protein language model (e.g., AlphaMissense, ESM-1v, EVE): Can speak to: Evolutionary constraint at the specific locus, predicted structural disruption, and statistical likelihood/score indicating whether the single nucleotide substitution is pathogenic or benign compared to population baselines. Cannot speak to: Specific biochemical mechanism (e.g., distinguishing gain-of-function from loss-of-function without targeted functional training), incomplete penetrance, variable expressivity, patient-specific phenotype severity, or serving as standalone clinical proof for medical decision-making (qualifies only as in silico supporting evidence, such as ACMG criteria PP3/BP4).

---

## [39] source=multitask_sft_big

**USER:** I have an exome sequencing result with a heterozygous missense change in the human TP53 gene: c.524G>A (p.Arg175His). Could you predict whether this specific amino acid substitution is likely to be pathogenic or benign, and provide a calibrated pathogenicity score?

**ASSISTANT:** AlphaMissense: Can speak to: zero-shot pathogenicity scores and discrete classifications (pathogenic, benign, ambiguous) for single-nucleotide missense variants based on evolutionary constraints and structural context. Cannot speak to: non-coding variants, insertions/deletions (indels), complex structural variants, clinical penetrance, patient-specific phenotypic severity, or definitive clinical diagnosis.

---

## [40] source=multitask_sft_big

**USER:** I have an AnnData file containing raw single-cell RNA-seq counts from human peripheral blood mononuclear cells (PBMCs). Can you predict the cell-type label for each cell using a pretrained foundation model?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer, fine-tuned for cell-type annotation): Can accurately map high-dimensional transcriptomic profiles to established cell types and subtypes present in its training reference, accounting for gene-gene interactions and batch variations. Cannot reliably identify novel or patient-specific rare cell states not represented in the reference atlas, nor can it infer non-transcriptomic phenotypic features such as spatial microenvironment context, surface protein abundance, or post-translational modifications.

---

## [41] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (c.4942C>T, p.Arg1648Cys) in a pediatric patient with intractable epilepsy. Can you evaluate this variant using an in silico pathogenicity predictor to estimate whether it is likely pathogenic or benign?

**ASSISTANT:** AlphaMissense (Deep learning-based missense variant effect predictor): It can accurately predict the likelihood that a single amino acid substitution disrupts protein function and causes disease based on structural context and evolutionary conservation. It cannot speak to non-missense variants (such as indels, frameshifts, or non-coding changes), distinguish between gain-of-function and loss-of-function mechanisms, determine disease penetrance or expressivity, or provide a definitive standalone clinical diagnosis.

---

## [42] source=multitask_sft_big

**USER:** Here is the SMILES string for our lead optimization candidate: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5. Could you evaluate its ADMET profile, specifically predicting human oral bioavailability (%F), CYP3A4/CYP2D6 inhibition liability, and cardiac risk via hERG channel affinity (IC50 / block probability)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop / ADMET-AI): Can speak to: In silico classification and regression estimates for small-molecule physicochemical and pharmacokinetic endpoints (e.g., binary probability of hERG inhibition, categorical CYP isozyme substrate/inhibition status, and empirical oral bioavailability classes) based on 2D chemical topology trained on benchmark bioassay data. Can't speak to: Dynamic human in vivo pharmacokinetic profiles (Cmax, AUC, Tmax), non-linear dose-dependent clearance, impact of vehicle formulation/excipients on intestinal permeability, stereochemical nuances unless explicitly encoded, or species-specific metabolic differences outside the training domain.

---

## [43] source=multitask_sft_big

**USER:** I have a library of 250 novel small-molecule kinase inhibitor candidates represented as canonical SMILES strings. Could you predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) to help us filter out compounds with poor oral bioavailability profiles prior to in vitro ADME assays?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., Chemprop / Directed Message Passing Neural Network fine-tuned on ChEMBL/ADMET benchmarks): Can reliably predict thermodynamic solubility trends and lipophilicity/logD profiles across standard drug-like small molecules within the training set's chemical domain based on 2D molecular graph topology; cannot account for solid-state crystal lattice properties (polymorphism, crystal packing), dynamic formulation or co-solvent effects, salt forms, or non-physiological pH conditions outside its training distribution.

---

## [44] source=multitask_sft_big

**USER:** I have an AnnData object containing log-normalized single-cell RNA-seq gene expression counts from human peripheral blood mononuclear cells (PBMCs) sequenced with 10x Genomics. Can you predict the cell-type labels for these cells using an automated model?

**ASSISTANT:** Pretrained Single-Cell Transformer Foundation Model (e.g., scGPT, Geneformer): It can accurately predict discrete cell-type labels, broad cell lineages, and shared functional cell states represented in its comprehensive pretraining reference atlases. It cannot definitively annotate novel, patient-specific, or ultra-rare pathogenic cell phenotypes absent from its training corpus, nor can it infer causal gene regulatory dynamics or distinguish technical batch artifacts from true biology without careful benchmark integration.

---

## [45] source=multitask_sft_big

**USER:** We are screening a series of small-molecule inhibitors targeting the ATP-binding site of human CDK4 (PDB: 2EUF). Given the co-crystal structure of the kinase domain and the SMILES strings of our top 20 candidate analogs, can you predict their binding affinities (pKd or delta G) to prioritize the most potent binders for synthesis?

**ASSISTANT:** 3D Structure-Based Equivariant Graph Neural Network (e.g., TankBind, GNINA): Can speak to: Relative binding affinity rankings (pKd, pKi, or delta G), predicted 3D binding poses, and localized non-covalent interactions (e.g., hydrogen bonding, hydrophobic contacts) within the active site. Cannot speak to: Binding kinetics (kon/koff residence time), downstream functional efficacy (agonism vs. antagonism), entropic free energy contributions from explicit solvent reorganization, or systemic ADMET and off-target selectivity profiles.

---

## [46] source=multitask_sft_big

**USER:** Here is the FASTA sequence for an uncharacterized bacterial response regulator: 'MTEITAAMVKELRESTGAGMMDCKNALET...'. Can you predict its full 3D tertiary structure and output a PDB file so we can inspect potential active site pockets?

**ASSISTANT:** AlphaFold2 (Evoformer / Structure Module architecture): Can predict high-confidence all-atom static 3D coordinates from sequence/MSAs and provide residue-level uncertainty metrics (pLDDT, PAE). Cannot reliably model conformational dynamics/transitions, exact energetic stability changes from point mutations, small-molecule ligand binding poses (without co-factor conditioning), or structural states of intrinsically disordered regions.

---

## [47] source=multitask_sft_big

**USER:** We are optimizing a lead series of small-molecule kinase inhibitors. Could you run ADMET profiling on this batch of 15 candidate SMILES strings to predict potential cardiotoxicity (hERG liability), inhibition against the primary CYP isoforms (CYP3A4, CYP2D6, CYP2C9), and predicted human oral bioavailability (F > 30%)?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network / Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop fine-tuned on TDC/ChEMBL ADMET benchmarks) or Pretrained Molecular Transformer (e.g., ChemBERTa/MolFormer): Can reliably score relative likelihoods of hERG blockade (in vitro patch-clamp IC50 cutoffs), binary inhibition flags across major CYP450 isoforms, and broad categorical or semi-quantitative oral bioavailability estimates based on 2D chemical structure. Cannot predict detailed in vivo pharmacokinetic profiles (such as Cmax, Tmax, AUC, or clearance rates), account for solid-state formulation effects (salts, polymorphs, excipients), model complex metabolite toxicity, or generalize reliably to modalities outside typical small-molecule chemical space (such as large macrocycles, PROTACs, or peptides).

---

## [48] source=multitask_sft_big

**USER:** I have an AnnData h5ad file with raw UMI counts from 15,000 human bone marrow cells sequenced on 10x Genomics. Could you run an automated pipeline to infer cell-type annotations for each cell using a pretrained model?

**ASSISTANT:** Single-cell transformer foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type classification): Can reliably predict established cell identities and developmental lineages present in the training reference atlas across standard gene expression profiles. Cannot definitively identify completely novel cell states, infer post-transcriptional protein abundance, account for tissue spatial architecture, or establish causal regulatory mechanisms from static transcriptomic counts alone.

---

## [49] source=multitask_sft_big

**USER:** I have a series of 25 novel small-molecule lead candidates represented as SMILES strings for an oncology target. Could you screen them for potential cardiac safety liability (hERG inhibition), metabolic clearance risks (specifically CYP3A4 and CYP2D6 inhibition), and estimate their human oral bioavailability percentage to help us prioritize compounds for in vitro testing?

**ASSISTANT:** Multi-Task Message Passing Neural Network (e.g., Chemprop / ADMET-AI) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: Rapid in silico screening of drug-like small molecules for binary/continuous risks of hERG-mediated cardiotoxicity, primary CYP isozyme inhibition flags, and qualitative/semi-quantitative estimates of oral bioavailability based on 2D chemical structure. Can't speak to: Dynamic physiological pharmacokinetics (Cmax, AUC, Tmax), non-hERG cardiovascular liabilities, stereospecific differences if chiral centers are undefined in SMILES, or non-small-molecule chemical spaces (e.g., peptide therapeutics, PROTACs, large macrocycles) falling outside the model's training applicability domain.

---

## [50] source=multitask_sft_big

**USER:** We have designed five novel small-molecule kinase inhibitors targeting EGFR (PDB: 7NEB). Can you predict their binding affinities (pKd/pIC50) using the protein structure and compound SMILES to help us prioritize which analogues to synthesize for in vitro binding assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) for Protein-Ligand Complex Scoring (e.g., KarmaDock, GNINA, or EquiBind): Can reliably score and rank binding affinity (e.g., Kd, Ki, IC50 approximations) and identify likely binding poses from 3D coordinates. Cannot speak to downstream pharmacokinetics/ADMET profiles, in vivo cellular efficacy, off-target selectivity across the proteome, or large-scale induced-fit conformational changes without explicit molecular dynamics simulations.

---

## [51] source=multitask_sft_big

**USER:** We have solved the crystal structure of the SARS-CoV-2 main protease (Mpro) binding pocket and designed 25 novel peptidomimetic analogs in SDF format. Can you predict the binding affinity (specifically pKd or delta G in kcal/mol) for each ligand against this target to prioritize candidates for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) for Structure-Based Protein-Ligand Affinity Prediction (e.g., TankBind, EquiBind, or GNINA-based 3D CNNs): CAN predict relative ranking, estimated binding free energy (delta G), and spatial interaction scores based on static 3D coordinate contacts and geometric complementarity. CANNOT speak to binding kinetics (kon/koff rates or drug residence time), dynamic protein induced-fit conformational shifts beyond the input conformation, solvent-entropy effects accurately, off-target proteome-wide selectivity, or cellular pharmacokinetics/permeability.

---

## [52] source=multitask_sft_big

**USER:** I have isolated an uncharacterized enzyme from an extremophile with the amino acid sequence 'MGSSHHHHHHSSGLVPRGSHMSEF...VKKLK'. Could you predict its 3D atomic structure, provide the PDB coordinates, and highlight which regions have high confidence?

**ASSISTANT:** Evoformer / Invariant Point Attention-based protein structure prediction model (e.g., AlphaFold2, ESMFold): Can accurately predict static 3D coordinates (backbone and side-chain conformations) and provide confidence metrics like pLDDT and PAE to evaluate structural reliability. Cannot simulate full conformational dynamics/equilibrium ensembles, explicitly model the functional impact of post-translational modifications (PTMs), or predict binding kinetics and ligand/cofactor interactions without dedicated docking or co-folding extensions.

---

## [53] source=multitask_sft_big

**USER:** Here is a set of 12 SMILES strings for our lead optimization series targeting CDK4. Could you run an in silico ADMET screen to estimate their hERG liability, CYP3A4 inhibition profile, and human oral bioavailability (F%) so we can prioritize compounds for our next synthesis and PK assay batch?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN / D-MPNN, such as Chemprop fine-tuned on Therapeutics Data Commons ADMET benchmarks): Can speak to: In silico statistical probability of hERG inhibition (cardiotoxicity risk), classification/affinity towards CYP450 isozyme inhibition (specifically CYP3A4), and estimated categorical or continuous oral bioavailability ranges based on 2D chemical structure and benchmark training distributions. Can't speak to: Dynamic physiological kinetics (e.g., non-linear clearance, food effect, transporter saturation), formulation-dependent solubility/dissolution, patient-specific factors (e.g., organ impairment, drug-drug interactions in vivo), or definitive regulatory safety clearance without empirical in vitro/in vivo assay validation.

---

## [54] source=multitask_sft_big

**USER:** We have synthesized a series of 15 optimized benzimidazole-based small molecules targeting IRAK4. Could you run an in silico ADMET screen on their SMILES strings to predict potential cardiotoxicity risks (hERG inhibition), metabolic liabilities across major cytochrome P450 isoforms (CYP3A4, CYP2D6, CYP2C9), and estimated percentage of human oral bioavailability?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network (e.g., Chemprop D-MPNN or ADMET-AI pretrained on TDC/ChEMBL datasets): Can speak to: High-throughput, early-stage in silico classification and semi-quantitative prioritization of 2D/3D small-molecule structures regarding their likelihood of hERG channel blockade, CYP450 direct competitive inhibition, and general oral fraction absorbed based on learned chemical structural alerts and physicochemical property correlations. Cannot speak to: Quantitative in vivo pharmacokinetic time-concentration curves (e.g., Cmax, AUC, clearance), vehicle/formulation-dependent solubility, active transporter-mediated efflux/uptake mechanisms (e.g., P-gp non-standard interactions), complex time-dependent or mechanism-based CYP inactivation, stereoisomeric divergence without explicit 3D conformations, or definitive clinical safety and regulatory toxicity endpoints.

---

## [55] source=multitask_sft_big

**USER:** I have three lead optimization candidates for an oncology target represented as SMILES. Can you evaluate their ADMET risk profile, specifically predicting hERG-mediated cardiotoxicity risk, CYP3A4 inhibition, and estimated oral bioavailability in humans?

**ASSISTANT:** Multi-Task Graph Neural Network (e.g., Chemprop / D-MPNN fine-tuned on ADMET benchmarks like TDC): Can reliably predict statistical likelihoods of binary endpoints (hERG liability, CYP inhibition) and categorical or percentage oral bioavailability based on molecular structure features learned from standard chemical databases. Cannot account for formulation effects, drug-drug interaction dynamics in vivo, dose-dependent non-linear pharmacokinetics, or target-mediated drug disposition (TMDD).

---

## [56] source=multitask_sft_big

**USER:** Here is the amino acid sequence of a putative kinase catalytic domain from an uncharacterized extremophile: MGEKIALVTGGTRGIGRAIALRLAKAGAQVVVTDISREKLEAVAERIKAEGGKAYALQCDVSDQEQVEAIAKTAEELGGLDIVVNNAAGVFKSTEDISFDEFDRVMNVNLRGAFMACKHAARVMIPKGSGSIICTASISGFVGGQGHAYTASKAGVIGMTKTLAVEWARKGIKANIICPGYIETPMAAAMRKDPTLDKLKEILPEERIKNPYGNKAYIDAMIKILQDENPDGSFLITGLKPVLLDGFK. Can you predict its 3D atomic coordinates in PDB format and provide per-residue confidence scores?

**ASSISTANT:** Protein Language Model-based / Multiple Sequence Alignment (MSA) Co-evolutionary Folding Model (e.g., AlphaFold2, ESMFold): Can predict atomic coordinates (backbone and side-chain orientations) of single-chain proteins and complexes, identify secondary structures and domain folds, and output confidence estimates (e.g., pLDDT, PAE). Cannot reliably model continuous dynamic conformational changes, solvent/solution-specific effects (e.g., pH, salt concentration), post-translational modifications (phosphorylation, glycosylation), or small-molecule/cofactor interactions without explicit multi-modal structural co-modeling architectures.

---

## [57] source=multitask_sft_big

**USER:** I have the amino acid sequence of a newly sequenced bacterial hydrolase (342 residues). Could you predict its 3D atomic coordinates in PDB format, along with per-residue confidence scores to see if the active site is reliably modeled?

**ASSISTANT:** AlphaFold2 (Evoformer/IPA-based deep learning protein structure prediction model): {'can_speak_to': ['Static 3D Cartesian coordinates (PDB/mmCIF) of native or near-native folded states', 'Per-residue local confidence estimations (pLDDT)', 'Relative domain orientation reliability via Predicted Aligned Error (PAE)'], 'cannot_speak_to': ['Dynamic conformational states, folding kinetics, and thermodynamics', 'Impact of environmental factors (e.g., pH, temperature, ionic strength)', 'Unmodeled non-protein entities (ligands, cofactors, ions, post-translational modifications) unless using specialized multi-ligand extensions']}

---

## [58] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from a 10x Genomics 3' scRNA-seq dataset of human peripheral blood mononuclear cells (PBMCs). Could you use a pretrained model to annotate each cell with its discrete cell type, resolving closely related subsets like naive vs. memory CD4+ T cells and DC subsets?

**ASSISTANT:** Single-cell generative foundation transformer (e.g., scGPT or Geneformer fine-tuned for cell-type classification): Can accurately infer recognized cell types, lineage hierarchies, and marker-defined states present within its reference training atlas while handling high-sparsity dropout. Cannot reliably identify entirely novel, patient-specific, or uncharacterized pathological cell states, nor can it infer spatial location, absolute protein abundance, or causal regulatory mechanisms driving cell differentiation.

---

## [59] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from 15,000 human peripheral blood mononuclear cells (PBMCs) sequenced with 10x Genomics. Could you annotate each cell with its corresponding immune cell type (e.g., naive CD4+ T cells, memory B cells, classical monocytes) using a pretrained model?

**ASSISTANT:** Pretrained Single-Cell Foundation Model fine-tuned for cell-type classification (e.g., scGPT or Geneformer): {'can_speak_to': ['Probability distributions over known discrete cell types represented in the reference atlas', 'Mapping cells to canonical transcriptomic identities robust to common sequencing batch effects', 'Marker gene contributions (via attention weights or feature attributions) supporting a specific annotation'], 'cant_speak_to': ['Reliable classification of entirely novel, rare, or uncharacterized cell populations absent from the pretraining/fine-tuning reference', 'Functional or physical validation of surface protein expression (requires CITE-seq or flow cytometry)', 'Spatial organization, cell-cell interactions, and tissue context', 'Disentangling biological identity from severe technical artifacts (e.g., high ambient RNA contamination or undetected doublets) without prior QC']}

---

## [60] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation (c.742C>T, p.Arg248Trp) in the TP53 gene from a clinical exome sequencing panel. Can you predict whether this specific amino acid substitution is pathogenic or benign and quantify its likelihood of disrupting protein function?

**ASSISTANT:** Structure- and Evolution-Aware Missense Variant Pathogenicity Predictor (e.g., AlphaMissense, ESM-1v): Can speak to: the statistical likelihood that a single amino acid substitution disrupts protein structure/function, prioritization of missense variants as likely benign or likely pathogenic based on evolutionary conservation and structural context, and continuous functional impact scores across human proteomes. Cannot speak to: non-missense variants (such as synonymous, splice-site, frameshift, or non-coding regulatory mutations), patient-specific clinical diagnosis or phenotypic penetrance, complex multi-locus epistatic interactions, or definitive clinical classifications without orthogonal evidence meeting ACMG/AMP guidelines.

---

## [61] source=multitask_sft_big

**USER:** Could you evaluate our top five lead candidates (provided as SMILES strings) for their ADMET profiles, specifically predicting hERG-mediated cardiotoxicity risks, inhibition potential against major CYP enzymes (like CYP3A4 and CYP2D6), and estimated percentage of human oral bioavailability?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN / Chemprop) fine-tuned on ADMET benchmarks (e.g., Therapeutics Data Commons): Can speak to: Fast statistical ranking and classification of chemical liabilities, such as likely hERG channel block (e.g., pIC50 thresholds), competitive CYP isozyme inhibition classes, and empirical oral bioavailability ranges based on 2D/3D molecular graph topology. Cannot speak to: In vivo physiological PK dynamics (e.g., multi-compartment plasma clearance curves, dose-dependent non-linear metabolism), formulation-dependent absorption variations, organ-specific active transport kinetics, or molecules falling significantly outside the model's chemical applicability domain.

---

## [62] source=multitask_sft_big

**USER:** Could you evaluate our candidate lead series (SMILES provided below) for preliminary ADMET profiling? Specifically, we need predictions on hERG inhibition risk (cardiotoxicity), CYP3A4/CYP2D6 inhibition potential to flag drug-drug interaction risks, and an estimate of high vs. low human oral bioavailability (%F) to prioritize analogues for in vitro assays.

**ASSISTANT:** Multitask Molecular Graph Neural Network (e.g., Chemprop / D-MPNN pretrained on TDC ADMET and ChEMBL benchmarks): Can speak to: Rapid in silico scoring, probabilistic classification of hERG potassium channel blocking risk, CYP isoform inhibition propensity, and relative ranking of oral absorption likelihood directly from 2D chemical structure. Cannot speak to: Absolute in vivo human pharmacokinetics, complex multi-organ metabolic clearance pathways, formulation- or solubility-limited absorption, dose-dependent toxicities, or provide definitive regulatory safety clearance without prospective experimental validation.

---

## [63] source=multitask_sft_big

**USER:** I have the 3D crystal structure of the human CDK2 kinase (PDB: 1HCK) and 20 candidate small-molecule inhibitors in SMILES format. Can you predict the binding affinity (pKd/Ki) for each compound against the binding pocket to help prioritize them for in vitro assays?

**ASSISTANT:** 3D Structure-Based Protein-Ligand Equivariant Graph Neural Network (e.g., GNINA, TankBind, or EquiBind): It can estimate relative binding scores (e.g., pKd, Ki, or docking scores) and identify probable binding poses based on rigid or semi-rigid structural contacts. It cannot reliably capture large-scale induced-fit conformational changes, full thermodynamic entropy/solvation free energies without explicit molecular dynamics, or predict downstream functional efficacy, ADMET properties, and off-target cytotoxicity.

---

## [64] source=multitask_sft_big

**USER:** We have 45 synthesized small-molecule derivatives targeting the kinase domain of human CDK2 (PDB ID: 1HCK). Can you run our ligand SMILES through a model to predict their absolute binding affinity (pKd / -log Kd) and rank-order them to prioritize top candidates for in vitro assay testing?

**ASSISTANT:** 3D Structure-Based Geometric Graph Neural Network (e.g., TankBind, GNINA, or Equivariant Cross-Attention Scoring Networks): Can predict relative ranking and approximate binding affinity (pKd/pKi) based on spatial complementarity, atomic contacts, and electrostatics in the bound complex. Cannot reliably account for induced-fit conformational dynamics of the protein backbone, explicit water/desolvation thermodynamics, kinetic rates (association/dissociation rates kon/koff), or systemic off-target selectivity and ADMET properties.

---

## [65] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs) generated via 10x Genomics. Can you predict the specific immune cell types for each individual cell barcode based on their gene expression profiles?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer) fine-tuned for cell type classification: Can accurately annotate known immune cell lineages and fine-grained subtypes represented in reference atlases, capture non-linear gene-gene dependencies, and highlight marker genes driving the classification. Cannot reliably identify entirely novel or undocumented cell types (often forcing them into nearest known classes), account for spatial tissue organization, or resolve misclassifications arising from unresolved multiplets (doublets) and technical batch artifacts without proper prior quality control.

---

## [66] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the LDLR gene (c.1246C>T, p.Arg416Cys) in a 34-year-old patient with severe hypercholesterolemia. Can you predict whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Deep learning protein language/structure-based variant effect predictor (e.g., AlphaMissense, ESM-1v): Can evaluate evolutionary conservation, structural disruption, and relative functional impact of single amino acid substitutions to predict pathogenicity scores. Cannot predict effects of non-coding, splice-site, or large structural variants; cannot account for variable penetrance, epigenetic factors, or tissue-specific gene regulation; and cannot substitute for clinical-grade ACMG/AMP variant classification without orthogonal evidence.

---

## [67] source=multitask_sft_big

**USER:** I have a library of 25 novel small-molecule lead analogs in SMILES format targeting oncology. Could you run an in silico ADMET profiling to predict cardiac toxicity via hERG channel inhibition (pIC50), CYP450 inhibition profiles across major isoforms (specifically CYP3A4, CYP2D6, and CYP2C9), and human oral bioavailability (%F)?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) Multi-Task Ensemble trained on Therapeutics Data Commons (TDC): Can reliably predict in vitro endpoints (hERG inhibition, CYP isoform inhibition/substrate status) and general oral bioavailability classifications for small organic drug-like molecules within the model's chemical applicability domain. Cannot account for in vivo physiological dynamics (systemic multi-organ clearance, PBPK distribution), formulation effects (salt forms, solubility enhancers, gut absorption barriers), or accurately evaluate non-traditional small-molecule modalities such as peptides, PROTACs, or organometallics.

---

## [68] source=multitask_sft_big

**USER:** I have an AnnData object containing single-cell RNA sequencing count matrices from human peripheral blood mononuclear cells (PBMCs). Can you annotate the fine-grained cell types for each cell profile based on its gene expression signature?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer, fine-tuned for cell type annotation): Can speak to mapping single-cell transcriptomic profiles to established canonical cell types, identifying rare known subsets represented in training atlases, and robustly handling moderate batch effects and dropout noise. Can't speak to novel or transitional cell states absent from the reference training ontology, underlying causal gene regulatory networks driving the phenotype, or functional/spatial behaviors that depend on post-translational modifications or tissue microenvironment.

---

## [69] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human CDK2 (PDB ID: 1HCK) and a series of 25 novel pyridine-based small-molecule inhibitors in SDF format. Can you predict the binding affinity (pKd/pIC50) for each compound docked into the ATP-binding site to help prioritize leads for synthesis?

**ASSISTANT:** Equivariant 3D Graph Neural Network / Protein-Ligand Complex Scoring Model (e.g., GNINA, TankBind, or EquiBind): Can predict relative ranking and approximate quantitative binding affinities (pKd, pKi) based on spatial, electrostatic, and steric complementary features of rigid or docked receptor-ligand complexes. Cannot reliably model large-scale induced-fit conformational changes, quantify dynamic entropic and explicit solvent free-energy contributions without molecular dynamics, model covalent binding mechanisms, or predict downstream functional efficacy (e.g., cellular IC50, ADMET).

---

## [70] source=multitask_sft_big

**USER:** I have the PDB crystal structure of human CDK2 (PDB ID: 1HCK) and an SDF file containing 50 candidate small-molecule inhibitors. Can you predict the binding affinity (pK_d or binding free energy) for each compound against this target and rank-order them to prioritize top hits for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Protein-Ligand Binding Affinity (e.g., TankBind, EquiBind, or GNINA-based 3D-CNNs): Can speak to: Relative binding affinity rankings (pK_d / pIC_50 estimates), predicted 3D binding poses, and geometric/electrostatic complementarity between the small molecule and the rigid binding pocket. Cannot speak to: Protein backbone flexibility/induced-fit dynamics during binding, binding kinetics (association/dissociation rates k_on/k_off), covalent inhibition mechanisms, or downstream in vivo pharmacokinetic and selectivity profiles.

---

## [71] source=multitask_sft_big

**USER:** We identified a novel missense mutation in the SCN1A gene (c.4943G>A, p.Arg1648His) in a pediatric patient presenting with severe early-onset epilepsy. Can you evaluate whether this amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** AlphaMissense (Structural-evolutionary variant effect predictor): Can speak to: Predicting the likelihood of disease pathogenicity (calibrated risk scores and categories: likely benign, likely pathogenic, or ambiguous) specifically for human single-amino-acid missense variants using structural context and evolutionary conservation. Cannot speak to: Non-coding variants, indels, copy number variations, synonymous mutations, gene-specific penetrance, precise biophysical mechanisms of dysfunction (e.g., gain-of-function vs. loss-of-function), or providing standalone definitive clinical diagnoses without clinical/functional evidence (ACMG/AMP guidelines).

---

## [72] source=multitask_sft_big

**USER:** I have isolated an uncharacterized 340-residue esterase from an extremophilic bacterium with the sequence 'MKTIIFAGAGRGGLA...'. Can you predict its full 3D atomic coordinates (PDB file) and evaluate the structural confidence across the catalytic domain to guide our mutagenesis study?

**ASSISTANT:** AlphaFold2 (Evoformer and Invariant Point Attention architecture): Can accurately predict static, ground-state 3D backbone and side-chain atomic coordinates, per-residue prediction confidence (pLDDT), and relative inter-domain positional certainty (PAE) for folded, naturally evolved sequences. Cannot speak to continuous conformational dynamics across varying physical conditions (e.g., changes in pH or temperature), folding kinetics/pathways, structural alterations driven by small-molecule ligand/cofactor binding, or the impact of post-translational modifications.

---

## [73] source=multitask_sft_big

**USER:** We have solved the 2.1 Å crystal structure of a novel mutant SARS-CoV-2 main protease (Mpro) and prepared a library of 150 peptidomimetic small molecules (SMILES format). Can you predict the binding affinity (pKd or IC50) for each ligand against this target pocket to help prioritize candidates for enzymatic assays?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., EquiBind, TankBind, or GNINA scoring ensembles): It can estimate relative binding affinities (e.g., pKd, delta-G) and rank-order drug candidates based on geometric complementarity, electrostatics, and learned spatial interaction features of the binding pose. It cannot reliably capture binding kinetics (kon/koff rates), full induced-fit protein conformational dynamics, entropic and water-mediated displacement effects with high thermodynamic accuracy, or downstream off-target toxicity and cell permeability.

---

## [74] source=multitask_sft_big

**USER:** We have an experimental cryo-EM structure of our kinase target (PDB: 8ABC) and a library of 150 novel pyrazole-based small-molecule analogs. Could you predict the binding affinity (Kd or pIC50) for each ligand docked into the ATP-binding pocket so we can prioritize compounds for our next synthesis cycle?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) trained on structural protein-ligand complexes (e.g., GNINA/PIGNet/TankBind architectures): Can speak to: Relative binding ranking, scoring of rigid or pre-docked poses, and electrostatic/steric complementarity within canonical binding pockets similar to training distributions (e.g., PDBbind). Cannot speak to: Absolute binding free energies without empirical calibration, target conformational changes or induced-fit dynamics (unless paired with molecular dynamics), explicit solvent thermodynamic contributions (water displacement entropy), or kinetic parameters like off-rate (k_off) and residence time.

---

## [75] source=multitask_sft_big

**USER:** We have the crystal structure of the human CDK2 catalytic domain (PDB ID: 1AQ1) and a library of 35 novel pyrazole-based small-molecule analogs in SMILES format. Can you predict the binding affinity (estimated pKd or delta G) for each compound docked into the ATP-binding pocket so we can prioritize the top candidates for chemical synthesis and surface plasmon resonance validation?

**ASSISTANT:** 3D Equivariant Graph Neural Network (3D-EGNN) for Protein-Ligand Interaction Scoring: It can accurately predict relative binding affinity rankings, estimate binding free energy metrics (e.g., pKd, pIC50), and evaluate geometric/chemical complementarity within a static 3D binding pocket. It cannot determine binding kinetics (kon/koff rates), simulate dynamic induced-fit conformational shifts outside the rigid receptor scaffold, quantify explicit solvent thermodynamic effects (solvation/desolvation entropy), or assess broader biological viability like metabolic clearance, cell permeability, and off-target toxicity.

---

## [76] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense mutation, NM_000059.4(BRCA2):c.8167G>A (p.Asp2723Asn), in a patient with early-onset breast cancer. Can you predict whether this variant is pathogenic or benign?

**ASSISTANT:** Deep learning-based missense variant pathogenicity predictor (e.g., AlphaMissense, EVE): Can speak to: computational likelihood of a missense variant disrupting protein structure/fitness and whether it structurally mirrors known disease-causing mutations. Can't speak to: definitive clinical pathogenicity under ACMG/AMP criteria without functional/segregation data, non-coding or complex structural variants, penetrance, disease onset age, or specific clinical phenotypes.

---

## [77] source=multitask_sft_big

**USER:** I have an AnnData h5ad object containing normalized single-cell RNA sequencing gene expression matrices from human peripheral blood mononuclear cells (PBMCs). Can you automatically predict and annotate the specific immune cell type labels for each cell in this dataset?

**ASSISTANT:** Single-Cell Foundation Transformer (e.g., scGPT or Geneformer fine-tuned for cell-type classification): Can accurately classify known discrete cell types and broad lineages from single-cell transcriptomic profiles, capture co-expression gene-gene networks, and handle standard batch effects across reference datasets. Cannot infer protein-level abundance, post-translational modifications, spatial tissue context, or reliably annotate completely novel/unseen pathological cell states not represented in the pretraining or fine-tuning reference atlases.

---

## [78] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation (p.Arg282Trp) in the TP53 gene of a patient with suspected Li-Fraumeni syndrome. Can you predict whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Protein Language Model / Structural Pathogenicity Predictor (e.g., AlphaMissense, ESM-1v): Can speak to the likelihood that a missense variant disrupts protein structure/function and whether it resembles known pathogenic versus benign human variants. Cannot speak to non-coding variants, indels, complex compound heterozygous interactions, patient-specific disease penetrance, or absolute clinical diagnosis without clinical validation.

---

## [79] source=multitask_sft_big

**USER:** I have identified a novel bacterial uncharacterized protein with the sequence 'MKVLWAALLVTFLAGCQAKVEQAVETEPEPELR...'. Can you predict its full 3D atomic coordinates, generate a PDB file, and provide the per-residue confidence scores to see if it contains a stable catalytic domain?

**ASSISTANT:** AlphaFold2 (Evoformer/Structure Module architecture) or ESMFold (Transformer protein language model with folding trunk): Can accurately predict static 3D Cartesian coordinates (backbone and side-chain atoms), relative domain orientations (PAE), and local prediction reliability (pLDDT). Cannot reliably predict protein folding pathways/kinetics, structural alterations induced by post-translational modifications (PTMs), environmental factors (such as pH, temperature, or membrane context), or multi-state conformational equilibrium without specialized sampling.

---

## [80] source=multitask_sft_big

**USER:** We have designed five novel small-molecule candidates (SMILES provided below) targeting a kinase domain. Could you run an in silico ADMET profiling screen on them to evaluate cardiotoxicity risks via hERG inhibition, cytochrome P450 interactions (specifically CYP3A4 and CYP2D6 inhibition), and estimated human oral bioavailability (percentage or high/low category)?

**ASSISTANT:** Multi-Task Graph Neural Network / Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop trained on TDC ADMET benchmarks): Can speak to: Fast, high-throughput statistical probability estimates and categorical risks (e.g., active/inactive hERG liability, CYP inhibition classification, and general drug-likeness/bioavailability ranges) inferred from 2D molecular graph features against established chemical space benchmarks. Cannot speak to: In vivo physiological PK dynamics (e.g., actual time-concentration profiles, clearance rates, volume of distribution), dose-dependent formulation effects, novel target-mediated toxicities, or reliable outcomes for unique chemotypes that fall outside the model's training applicability domain.

---

## [81] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the LDLR gene (c.818G>A, p.Cys273Tyr) in a patient presenting with premature coronary artery disease. Could you predict whether this variant is pathogenic or benign?

**ASSISTANT:** Deep learning-based missense variant effect predictor (e.g., AlphaMissense, EVE, ESM-1v): Can predict the structural and evolutionary likelihood that a specific single amino acid substitution disrupts protein function, outputting a continuous pathogenicity score or categorical classification. Cannot provide a definitive clinical diagnosis, determine clinical penetrance or expressivity, account for complex gene-gene interactions, or evaluate non-coding, synonymous, or large structural variants without dedicated splicing/regulatory models.

---

## [82] source=multitask_sft_big

**USER:** I have an AnnData object containing normalized scRNA-seq expression counts from ~25,000 human peripheral blood mononuclear cells (PBMCs) generated via 10x Genomics. Could you predict and assign cell-type annotations (e.g., specific T cell subsets, B cells, NK cells, monocytes) to each single cell using a pretrained transfer learning model?

**ASSISTANT:** Single-Cell Foundation Transformer fine-tuned for cell-type annotation (e.g., scGPT, Geneformer) or Reference-based scRNA-seq Classifier (e.g., CellTypist): Can speak to: automated mapping of single cells to known canonical lineages, classification confidence scores, batch-invariant transcriptionally defined cell states, and identification of key driver genes for predicted classes. Cannot speak to: unrepresented or novel cell types not present in the training reference, continuous spatial tissue context, protein-level functional activity, or post-translational regulatory states.

---

## [83] source=multitask_sft_big

**USER:** We have a pipeline of 2,000 small-molecule candidates represented as SMILES strings from our medicinal chemistry campaign. Could you predict their aqueous solubility (LogS) and physiological distribution coefficient (LogD at pH 7.4) so we can prioritize compounds with optimal oral bioavailability?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., Chemprop / D-MPNN or ChemBERTa fine-tuned on MoleculeNet/ADMET benchmarks): Can speak to: In silico estimates of thermodynamic aqueous solubility, relative lipophilicity/polarity rankings, and structure-property relationships within drug-like chemical space matching its training distribution. Cannot speak to: Experimental variability driven by crystal polymorphism, salt forms, formulation excipients, temperature-dependent dissolution kinetics, non-physiological pH ranges, or multi-factor in vivo pharmacokinetic outcomes (e.g., intestinal permeability, clearance).

---

## [84] source=multitask_sft_big

**USER:** I'm evaluating a series of small-molecule kinase inhibitors for early lead optimization. Can you predict the aqueous solubility (LogS) and distribution coefficient at physiological pH (LogD7.4) for this candidate: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5?

**ASSISTANT:** Message Passing Neural Network (D-MPNN) or Pretrained Molecular Transformer (e.g., ChemBERTa fine-tuned on TDC ADMET benchmarks): Can reliably predict intrinsic aqueous solubility and LogD at standard physiological pH (7.4) for typical drug-like small molecules represented as 2D SMILES/molecular graphs. Cannot account for solid-state crystal polymorphism, formulation effects, precipitation kinetics, temperature/ionic strength variations, or accurate behavior of metallo-complexes and large covalent macrocycles outside its training chemical space.

---

## [85] source=multitask_sft_big

**USER:** We have synthesized a library of 35 lead optimization candidates for an oncology target (provided as SMILES strings). Could you screen these compounds to predict their ADMET profiles, specifically flagging potential hERG inhibition (cardiotoxicity risk), CYP3A4 and CYP2D6 inhibition liability, and estimated human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN) or Pretrained Molecular Transformer (e.g., Chemprop / ADMET-AI / MolFormer fine-tuned on TDC/ChEMBL benchmarks): Can: Rapidly provide high-throughput ranking and probabilistic classification of hERG liability, primary CYP enzyme inhibition, and categorical or scalar oral bioavailability estimates based on 2D/3D molecular structure and structural alerts within the training domain. Cannot: Account for formulation effects, drug-drug interaction kinetics (time-dependent inhibition), in vivo systemic clearance complexity, idiosyncratic toxicity, or provide reliable predictions for chemical scaffolds significantly outside the training distribution.

---

## [86] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (c.3862G>A, p.Val1288Met) in an infant presenting with early-onset focal seizures. Could you run this variant through a predictor to evaluate its likely pathogenicity and likelihood of disrupting sodium channel function?

**ASSISTANT:** Pretrained structural/evolutionary variant effect predictor (e.g., AlphaMissense, ESM-1v, PrimateAI-3D): Can speak to the biophysical constraint, evolutionary conservation, and structural impact of the amino acid substitution on protein stability and biochemical function. Cannot speak to patient-specific clinical penetrance, modifier gene interactions, disease severity/phenotypic spectrum, medication responsiveness, or serve as a standalone ACMG/AMP diagnostic classification without orthogonal clinical and functional evidence.

---

## [87] source=multitask_sft_big

**USER:** I have synthesized a set of ten novel small-molecule kinase inhibitor candidates as SMILES strings. Could you estimate their aqueous solubility (logS in mol/L) and lipophilicity/distribution coefficient (logD at physiological pH 7.4) to help us prioritize leads for oral bioavailability?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Transformer (e.g., Chemprop D-MPNN or ChemBERTa-2 fine-tuned on ADMET benchmarks): Can reliably predict: Standard equilibrium thermodynamic properties (logS, logP/logD), relative ADMET property rankings, and functional group contributions across drug-like small molecules with validated 2D representations. Cannot reliably speak to: Kinetic solubility influenced by crystal polymorphism/amorphous states, formulation/excipient effects, temperature variations beyond standard assays, or organometallic/macrocyclic structures underrepresented in standard training distributions.

---

## [88] source=multitask_sft_big

**USER:** I have identified an uncharacterized missense mutation in the human BRCA1 protein (c.5095C>T, p.Arg1699Trp). Can you predict whether this specific variant is likely pathogenic or benign and explain its predicted impact on protein fitness?

**ASSISTANT:** AlphaMissense (structural context-aware variant effect predictor): Can speak to: The likelihood that a single amino acid missense substitution disrupts human protein function and correlates with general pathogenicity based on structural and evolutionary conservation. Can't speak to: Non-coding variants, insertions/deletions, complex structural variants, variant penetrance, specific clinical phenotypes/disease severity, or definitive medical diagnosis without functional validation and clinical guidelines (e.g., ACMG/AMP criteria).

---

## [89] source=multitask_sft_big

**USER:** We have designed 35 novel fluorinated pyridine derivatives as potential oncology leads. Here is the list of canonical SMILES strings: [c1cc(F)cc(n1)...]. Could you predict their aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) to help us select the top candidates for in vitro ADME profiling?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) or Fine-Tuned Molecular Transformer (e.g., ChemBERTa, MolFormer): Can speak to: Rapid quantitative estimation of intrinsic equilibrium solubility (logS), distribution coefficients (logD at pH 7.4), and relative property-based ranking for drug-like small molecules based on 2D chemical structure. Cannot speak to: Kinetic solubility, crystalline solid-state properties (e.g., polymorphism, crystal lattice energy, amorphous transitions), formulation effects, buffer/salt-specific precipitation dynamics, or molecules outside the training distribution (such as large macrocycles, covalent adducts, or organometallics).

---

## [90] source=multitask_sft_big

**USER:** I have an uncharacterized 320-amino acid sequence for a putative bacterial esterase: 'MKTIIALSYIFCLVFA...'. Can you generate its predicted 3D atomic coordinates in PDB format so our team can visualize the fold and locate potential active site residues?

**ASSISTANT:** AlphaFold2 / ESMFold (MSA/Language Model-to-Structure Neural Networks): Can reliably predict: Static, ground-state 3D atomic coordinates (backbone and side-chain conformations), inter-domain orientations, and local confidence metrics (pLDDT, PAE). Cannot reliably speak to: Multi-state functional dynamics, millisecond-scale conformational transitions, post-translational modifications, or exact thermodynamic binding affinities and kinetics for arbitrary small-molecule cofactors.

---

## [91] source=multitask_sft_big

**USER:** I have a series of 25 novel small-molecule analogues for a kinase target provided as SMILES strings. Can you predict their aqueous solubility (logS) and lipophilicity at physiological pH (logD7.4) to help us flag potential bioavailability liabilities?

**ASSISTANT:** Message Passing Neural Network (e.g., Chemprop / D-MPNN fine-tuned on ADMET datasets like TDC or MoleculeNet): Can speak to: rapid, relative ranking of 2D small-molecule equilibrium solubility and pH-specific octanol/water partitioning within standard drug-like chemical space. Cannot speak to: solid-state effects (crystal packing, polymorphism), kinetic dissolution rates, formulation-assisted solubility (e.g., excipients, cosolvents), temperature dependencies, or non-traditional modalities such as large macrocycles and metal complexes outside the training distribution.

---

## [92] source=multitask_sft_big

**USER:** I have two lead candidate molecules for an oncology target with SMILES 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5' and 'CC(C)OC1=CC=C(C=C1)C2=NC(=CS2)N3CCC(CC3)NC(=O)C4=CC=C(C=C4)F'. Could you profile their ADMET risks, specifically predicting human oral bioavailability (F%), hERG liability (cardiotoxicity), and inhibition across primary CYP450 isoforms (CYP3A4, CYP2D6)?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network / Transformer fine-tuned on ADMET benchmarks (e.g., ADMETlab 2.0 / Chemprop D-MPNN on Therapeutics Data Commons): Can rapidly provide in silico risk estimates, classification scores, and basic regression values for well-benchmarked ADMET endpoints (such as qualitative human oral bioavailability, hERG IC50 inhibition thresholds, and CYP 1A2/2C9/2C19/2D6/3A4 inhibition likelihood) based on small-molecule 2D topology. Cannot predict precise in vivo pharmacokinetic dynamics (e.g., clearance rates across diverse patient demographics, dose-dependent exposure, vehicle/formulation effects) nor can it account for complex off-target polypharmacology, active transport mechanisms (e.g., P-gp efflux kinetics), or non-CYP clearance without targeted experimental verification.

---

## [93] source=multitask_sft_big

**USER:** I have an uncharacterized 280-amino-acid sequence from an extremophile bacterium (FASTA: MKVLWAALLVTFLAGCQAKVEQAVETEPEPELRQQ...). Could you predict its 3D tertiary structure and provide the per-residue pLDDT confidence metrics to see if it contains a functional catalytic domain?

**ASSISTANT:** AlphaFold2 (Evoformer-based Protein Structure Prediction Model): {'can_speak_to': ['High-accuracy static 3D backbone and side-chain atomic coordinates (PDB/mmCIF format)', 'Relative domain packing and domain-level organization via Predicted Aligned Error (PAE)', 'Local model confidence and disordered regions via per-residue predicted Local Distance Difference Test (pLDDT)'], 'cant_speak_to': ['Dynamic multi-state conformational equilibrium or folding pathways under physiological conditions', 'Accurate structural shifts driven by non-protein cofactors, ligands, ions, or post-translational modifications (unless explicitly modeled)', 'Quantitative thermodynamic stability changes (delta-delta G) resulting from single-point mutations']}

---

## [94] source=multitask_sft_big

**USER:** I have identified an uncharacterized 180-residue enzyme sequence from an environmental isolate: 'MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHQYREQIKRVKDSDDVPMVLVGNKCDLAARTVESRQAQDLARSYGIPYIETSAKTRQGVEDAFYTLVREIRQHKLRKLNPPDESGPGCMSCKCVLS'. Can you predict its 3D atomic coordinates and provide per-residue confidence scores (pLDDT)?

**ASSISTANT:** End-to-end deep learning protein structure prediction models (e.g., AlphaFold2, ESMFold): Can speak to: predicting static backbone and side-chain atomic coordinates (PDB/mmCIF format), local folding confidence (pLDDT), and inter-domain relative orientation certainty (PAE). Cannot speak to: real-time folding kinetics, full conformational ensembles/structural dynamics in solution, non-covalent interactions with unmodeled small-molecule ligands/ions, or the downstream impact of post-translational modifications.

---

## [95] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the TP53 gene (p.Arg248Trp) from whole-exome sequencing of a patient with suspected early-onset cancer. Could you predict whether this specific amino acid substitution is likely pathogenic or benign, and provide a calibrated pathogenicity score?

**ASSISTANT:** Supervised deep learning-based missense variant effect predictor (e.g., AlphaMissense): Can speak to: The likelihood of a single amino acid substitution disrupting protein function and correlating with clinical pathogenicity based on structural context and evolutionary conservation. Can't speak to: Non-coding variants, insertions/deletions, copy number alterations, incomplete penetrance, patient-specific clinical phenotypes, or providing a standalone, definitive clinical diagnosis without integrative ACMG/AMP guideline evaluation.

---

## [96] source=multitask_sft_big

**USER:** Here is the SMILES string for our lead optimization candidate: 'CC1=C(C(=O)N(C2=CC=CC=C12)C3CCN(CC3)CC4=CC=C(C=C4)F)C'. Can you predict its ADMET profile, specifically hERG cardiac liability (IC50 < 10 µM), inhibition against CYP3A4 and CYP2D6, and whether it is likely to have high human oral bioavailability (>30%)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Pretrained Molecular Transformer (e.g., MolFormer) fine-tuned on benchmark datasets like Therapeutics Data Commons (TDC): Can speak to: Statistical probabilities and binary/regressive estimates of in vitro target inhibition (hERG blocker status, CYP450 isozyme binding) and basic oral absorption potential within the model's learned chemical space. Cannot speak to: In vivo physiological PK dynamics (clearance rates, volume of distribution, tissue accumulation), drug-drug interactions in complex clinical contexts, formulation-dependent bioavailability (e.g., salt forms, excipients, dissolution rates), or accurate predictions for novel chemotypes falling outside the training domain.

---

## [97] source=multitask_sft_big

**USER:** We have solved the crystal structure of the SARS-CoV-2 main protease (Mpro) binding pocket and generated docked poses for 20 novel peptidomimetic lead compounds. Could you predict the binding affinities (specifically pKd or ΔG in kcal/mol) for each compound against the protease, and rank them to prioritize candidates for in vitro enzymatic assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network (3D-EGNN) for Protein-Ligand Affinity Prediction (e.g., GNINA, TankBind, or EquiBind-derived scoring architectures): Can predict relative ranking and approximate non-covalent binding strength (e.g., pKd, ΔG) from static 3D spatial contacts and stereochemical complementarity. Cannot reliably predict binding kinetics (kon/koff residence time), thermodynamics involving large induced-fit conformational rearrangements, solvent entropy changes with explicit-solvent free energy perturbation (FEP) accuracy, or covalent inhibition mechanisms.

---

## [98] source=multitask_sft_big

**USER:** I have an uncharacterized viral surface glycoprotein sequence (FASTA: MKTIIALSYIFCLVFA...). Can you predict its full 3D atomic coordinates (PDB/mmCIF format), generate the predicted aligned error (PAE) matrix, and output per-residue pLDDT confidence scores to assess if the putative receptor-binding domain is well-ordered?

**ASSISTANT:** AlphaFold2 / ESMFold (Equivariant Transformer / Biomolecular Structure Prediction Model): Can speak to: Static ground-state tertiary backbone and side-chain atomic coordinates, relative inter-domain orientations, and model confidence/disorder estimates (pLDDT, PAE). Cannot speak to: Real-time conformational dynamics, kinetic transition pathways, thermodynamic free-energy landscapes, non-canonical post-translational modifications (e.g., complex glycosylation), or solvent/pH-dependent conformational changes.

---

## [99] source=multitask_sft_big

**USER:** I have synthesized a small batch of lead optimization analogs for our kinase inhibitor program. Could you predict the aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) for these SMILES strings to help us triage which compounds to advance into in vitro ADME screening?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Pretrained Molecular Transformer (e.g., ChemBERTa fine-tuned on ADMET benchmarks): Can speak to: In silico ranking of relative lipophilicity and aqueous thermodynamic solubility based on 2D topological features and functional groups learned from curated datasets (e.g., ChEMBL, MoleculeNet). Cannot speak to: Experimental edge cases dependent on solid-state crystal packing (polymorphism affecting intrinsic solubility), precise kinetic solubility, solution conditions (non-standard temperatures, variable co-solvents, non-neutral ionic strength), or downstream complex in vivo bioavailability without experimental assays.

---

## [100] source=multitask_sft_big

**USER:** I have an uncharacterized 320-amino-acid sequence from an extremophile bacterium: 'MVLSEGEWQL...'. Could you generate the predicted 3D atomic coordinates (PDB format) for this monomer and indicate which regions correspond to high-confidence folded domains?

**ASSISTANT:** End-to-End Protein Structure Prediction Network (e.g., AlphaFold2, ESMFold): Can predict static 3D Cartesian coordinates (C-alpha backbone and side chains), domain boundaries, and per-residue confidence scores (pLDDT / PAE). Cannot reliably speak to dynamic conformational ensembles across variable physiological conditions (e.g., temperature/pH changes), folding kinetics/pathways, or precise thermodynamic binding affinities (Kd) to small molecules without additional simulation or specialized docking tools.

---

## [101] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation (p.Arg248Gln) in the TP53 gene of a pediatric patient presenting with early-onset sarcoma. Could you evaluate whether this amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Protein structure- and evolution-aware variant effect predictor (e.g., AlphaMissense, ESM-1v): Can reliably score the likelihood of pathogenicity for single-nucleotide missense variants across human protein-coding regions based on structural and evolutionary constraints; cannot evaluate non-coding variants, synonymous mutations, frameshifts, or large indels, nor can it determine clinical penetrance, age-of-onset, or patient-specific phenotype presentation.

---

## [102] source=multitask_sft_big

**USER:** I have a library of 15 optimized lead compounds for an oncology target provided as SMILES strings. Could you run an in silico ADMET screen to estimate their cardiotoxicity risk via hERG inhibition (pIC50 or active/inactive cutoff), assess their potential to inhibit major hepatic CYP enzymes (specifically CYP3A4 and CYP2D6), and predict whether they are likely to achieve high human oral bioavailability (>30% F)?

**ASSISTANT:** Multi-Task Directed-Message Passing Neural Network (D-MPNN) / Pretrained Molecular Graph Transformer (e.g., fine-tuned on TDC or ADMETlab multi-task datasets): {'can': ['Rapidly rank and filter chemical series based on statistical likelihood of hERG cardiac toxicity, CYP isoform-specific inhibition, and oral bioavailability classes directly from 2D molecular structures.', 'Identify high-risk pharmacophores, structural alerts, and molecular properties (e.g., lipophilicity, polar surface area) that drive poor ADMET liabilities.'], 'cannot': ['Account for dynamic, formulation-dependent in vivo pharmacokinetic parameters (e.g., solubility in specific delivery vehicles, food effects, gastric pH variation).', 'Model non-metabolic clearance mechanisms accurately (e.g., renal excretion, active transporter-mediated biliary excretion) without explicit transporter data.', 'Predict idiosyncratic toxicities, inter-individual genetic polymorphisms (e.g., poor metabolizer CYP variants), or definitive clinical safety profiles without wet-lab validation.']}

---

## [103] source=multitask_sft_big

**USER:** I have an AnnData matrix of single-cell RNA-seq raw count profiles from 20,000 cells collected from human peripheral blood mononuclear cells (PBMCs). Could you identify and annotate the specific cell type for each cell based on its gene expression signature?

**ASSISTANT:** Pretrained transformer-based single-cell foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): Can reliably predict established cell lineages, immune subtypes, and functional activation states represented in the training references, handling cross-batch variability. Cannot infer spatial tissue context, validate post-translational protein expression, or accurately identify entirely novel or non-canonical cell types absent from its pretraining and reference ontologies.

---

## [104] source=multitask_sft_big

**USER:** We have synthesized a batch of 250 small-molecule kinase inhibitor candidates (provided as SMILES strings). Can you predict their aqueous solubility (logS) and lipophilicity at physiological pH (logD7.4) to help us prioritize compounds with favorable oral bioavailability before in vitro testing?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) fine-tuned on ADMET property benchmarks (e.g., TDC, ChEMBL): Can accurately predict intrinsic thermodynamic/kinetic aqueous solubility ranges and distribution coefficients (logD7.4) based on 2D chemical structure, identify liability motifs, and rank lead compounds. Cannot account for solid-state crystalline polymorphism, salt form effects, formulation/excipient interactions, or downstream biological complexity such as active transporter-mediated efflux or metabolic degradation.

---

## [105] source=multitask_sft_big

**USER:** I have the refined crystal structure of human CDK2 (PDB ID: 1HCK) and a series of 50 novel pyrazole-derived small molecules. Could you predict their binding affinities (pKd or IC50 values) against the ATP-binding pocket so we can prioritize the top 5 candidates for chemical synthesis?

**ASSISTANT:** 3D Structure-Based Equivariant Graph Neural Network (e.g., PIGNet, EquiBind, or GNINA/3D-CNN scoring functions): Can speak to: Relative binding score ranking, predicted free energy/pKd values based on static 3D geometric and physicochemical contacts, and scoring of ligand docking poses within a defined binding pocket. Cannot speak to: Induced-fit conformational dynamics, explicit thermodynamic entropic/desolvation penalties without molecular dynamics, functional activity (distinguishing agonists vs. antagonists), off-target selectivity, or in vivo pharmacokinetics (ADMET) and cellular bioavailability.

---

## [106] source=multitask_sft_big

**USER:** I have identified several novel missense mutations in the human BRCA1 and TP53 genes from exome sequencing (such as BRCA1 p.Cys61Gly and TP53 p.Leu130Pro). Can you predict whether these specific amino acid substitutions are pathogenic or benign?

**ASSISTANT:** AlphaMissense (Structural/Evolutionary Missense Variant Pathogenicity Predictor): Can speak to: The likelihood that a specific single-nucleotide missense variant impairs protein function or is clinically pathogenic based on evolutionary conservation and predicted 3D structural constraints. Cannot speak to: Non-missense alterations (such as indels, frameshifts, or nonsense mutations), non-coding or splice-site variants, disease penetrance in a specific patient, or definitive clinical diagnosis without clinical correlation.

---

## [107] source=multitask_sft_big

**USER:** I have synthesized a novel kinase inhibitor candidate with the SMILES string 'CC1=C(C(=O)NC2=CC=C(C=C2)N3CCN(CC3)C)NC4=C1C=CC(=C4)Cl'. Can you predict its aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4)?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop fine-tuned on physicochemical datasets): Can speak to: Fast in silico estimation of equilibrium aqueous solubility (logS) and lipophilicity (logD) based on 2D chemical graph topology and learned chemical fragment patterns. Can't speak to: Dynamic polymorph-dependent solid-state solubility, specific buffer or salt formulation effects, temperature variance, or experimental ADMET outcomes in complex biological matrices without empirical validation.

---

## [108] source=multitask_sft_big

**USER:** I have an AnnData object containing log-normalized single-cell RNA-seq counts from a human PBMC sample (10x Genomics v3). Can you annotate the cell types for each cluster using a pretrained reference model?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer): Can reliably predict canonical cell types, map profiles to standardized tissue ontologies, and generalize across batch effects using zero-shot or fine-tuned gene representations. Cannot directly measure post-translational protein modifications, infer spatial tissue organization without paired spatial data, or reliably classify entirely novel or rare disease-specific cell states absent from the pretraining atlas.

---

## [109] source=multitask_sft_big

**USER:** I have two lead candidate SMILES strings for an oral kinase project: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5' and 'CC(C)OC1=CC=CC=C1NC2=NC=C(C(=N2)N)C3=CN=CC=C3'. Can you predict their aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4)?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop fine-tuned on ESOL and ChEMBL/Lipophilicity benchmarks): Can accurately estimate intrinsic thermodynamic aqueous solubility (logS) and distribution coefficients (logD7.4) for drug-like small molecules within the training applicability domain (MW < 800, standard organic heteroatoms). Cannot speak to formulation/excipient effects, solid-state crystalline polymorph stability, temperature-dependent dissolution kinetics, or non-standard solvent/pH conditions.

---

## [110] source=multitask_sft_big

**USER:** I have the co-crystal structure of human CDK2 (PDB: 1HCL) and a library of 50 novel small-molecule kinase inhibitor analogs in SDF format. Can you predict the binding affinity (pKd or binding free energy) for each ligand against the CDK2 active site to prioritize leads for synthesis?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, or GNINA-based scoring models): Can reliably score geometric/chemical complementarity and predict relative ranking or empirical binding free energy (Kd/Ki/IC50 proxies) for non-covalent complexes with known or docked 3D conformations. Cannot reliably account for entropic penalty, complex solvent/desolvation dynamics, induced-fit protein conformational rearrangements absent in the static input, covalent inhibition, or downstream pharmacokinetic/ADMET properties.

---

## [111] source=multitask_sft_big

**USER:** I have designed five candidate small molecules (provided as SMILES strings) for an oncology lead optimization project. Could you predict their ADMET profiles, specifically assessing hERG cardiotoxicity liability, inhibition risk across major CYP450 enzymes (CYP3A4, CYP2D6, CYP2C9), and estimated human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN) / Graph Neural Network (e.g., Chemprop / ADMET-AI): {'can': ['Rapidly screen and rank small molecules for hERG channel blockade liability based on statistical structure-activity relationships.', 'Predict binary classification of inhibition or substrate activity for major CYP450 isoforms.', 'Provide categorical or approximate regression estimates for human intestinal absorption and oral bioavailability within drug-like chemical space.'], 'cannot': ['Account for dose-dependent pharmacokinetics, formulation effects, or food-drug interactions that influence in vivo bioavailability.', 'Reliably predict endpoints for non-standard modalities such as macrocycles, PROTACs, peptides, or novel scaffolds far outside the training distribution.', 'Model downstream downstream cardiotoxic mechanisms beyond direct I_Kr/hERG channel pore blockade, nor predict reactive metabolite-driven CYP inactivation.']}

---

## [112] source=multitask_sft_big

**USER:** I have synthesized a small batch of drug-like small molecules as prospective kinase inhibitors. Can you predict the aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) for this series based on their SMILES strings, such as 'Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc4nccc(-c5cccnc5)n4'?

**ASSISTANT:** Message Passing Neural Network (e.g., Chemprop D-MPNN) or Pretrained Molecular Language Model (e.g., ChemBERTa / MolFormer) fine-tuned on ADMET datasets (e.g., TDC, ChEMBL): Can predict: Quantitative baseline estimates of thermodynamic/kinetic aqueous solubility and octanol-water partition/distribution coefficients (logP/logD7.4) for small, druglike organic molecules in standard aqueous buffers. Cannot predict: Solid-state polymorphic effects, formulation-dependent dissolution rates, kinetic precipitation dynamics, salt form behavior, or partition behavior in non-standard complex biological fluids with serum protein binding.

---

## [113] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human CDK2 (PDB: 1HCK) and 45 novel drug-like small molecules as SMILES strings. Could you predict the binding affinity (specifically pKd or ΔG) of each molecule against this target to help rank our candidates before in vitro synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) / Convolutional Structure-Based Scoring Model (e.g., GNINA, TankBind): Can speak to: Relative binding ranking, scoring of non-covalent structural interactions (e.g., hydrogen bonds, hydrophobic contacts), and approximate equilibrium binding affinity (pKd/pKi) for non-covalent, drug-like ligands within typical pocket representations. Cannot speak to: Covalent binding mechanisms, kinetic parameters (association/dissociation rates kon and koff), thermodynamic entropy changes arising from solvent reorganization, induced-fit target conformational shifts not present in the static input structure, or downstream functional efficacy (agonist vs. antagonist effects).

---

## [114] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human EGFR kinase domain (PDB: 1M17) and a library of 50 novel quinazoline derivatives as SMILES strings. Can you predict the absolute binding free energy (ΔG) or pKd values for these compounds against the ATP-binding pocket to help prioritize candidates for synthesis?

**ASSISTANT:** Equivariant 3D Graph Neural Network (e.g., TankBind, EquiBind, or GNINA-style 3D-CNN/EGNN pretrained on PDBbind): Can reliably score and rank static protein-ligand poses, identify key non-covalent interactions (e.g., hydrogen bonding, hydrophobic contacts), and estimate relative binding affinity (pKd/pKi) within the chemical space of known structural complexes. Cannot accurately capture real-time induced-fit conformational dynamics, full thermodynamic entropy/desolvation penalties, off-target selectivity across the proteome, or pharmacokinetics and downstream cellular efficacy (e.g., IC50/ADMET).

---

## [115] source=multitask_sft_big

**USER:** I have an uncharacterized 350-amino-acid sequence of a putative kinase isolated from an environmental metagenome (MVEVL...LAK). Can you predict its 3D atomic structure, provide the coordinates in PDB format, and give me the per-residue confidence metrics (pLDDT) to see which domains are well-folded?

**ASSISTANT:** AlphaFold2 (Evoformer/Structural Module Architecture): Can determine high-confidence static 3D ground-state coordinates, overall fold topology, domain boundaries, and relative domain positioning via predicted aligned error (PAE). Cannot reliably resolve full conformational dynamics, thermodynamic folding pathways, the impact of arbitrary single-point mutations on stability, or structural changes triggered by small-molecule ligand or cofactor binding.

---

## [116] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the BRCA1 gene (NM_007294.4:c.181T>G, p.Cys61Gly) in an individual with early-onset breast cancer. Can you score the predicted pathogenicity of this amino acid substitution to help determine if it is damaging or benign?

**ASSISTANT:** AlphaMissense (Protein structural-evolutionary variant effect predictor): Can speak to: Zero-shot computational scoring of missense variant deleteriousness, structural tolerance, and evolutionary conservation at the specific protein residue to support ACMG/AMP computational criteria (e.g., PP3/BP4). Can't speak to: Non-coding, synonymous, frameshift, or splicing alterations; patient-specific clinical penetrance; somatic actionability; or providing a definitive medical diagnosis without functional assay and pedigree validation.

---

## [117] source=multitask_sft_big

**USER:** I have an AnnData object containing single-cell RNA-seq count matrices from human PBMC samples. Can you pass these transcriptomic profiles through a pretrained foundation model to annotate each cell with its corresponding immune cell type and confidence score?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer) fine-tuned for cell-type classification: Can accurately assign discrete cell-type labels and broad lineage identities by leveraging contextual gene-gene interaction embeddings across common sequencing platforms. Cannot reliably identify novel or unseen cell types not represented in the reference atlas, infer spatial tissue context or proteomic/epigenetic states from scRNA alone, or infer causal driver mechanisms of disease states solely from annotated transcriptional profiles.

---

## [118] source=multitask_sft_big

**USER:** We have designed a batch of 45 lead-optimization small molecules for an oncology target and need to evaluate their early ADMET profiles. Could you run predictions on their SMILES to assess potential hERG-mediated cardiotoxicity, inhibition across major CYP450 isoforms (CYP3A4, CYP2D6, CYP2C9), and predicted human oral bioavailability (%F)?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) / Multi-Task Graph Neural Network (e.g., ADMET-AI / Chemprop): Can speak to in silico risk scoring, classification probabilities, and quantitative estimations for standardized benchmark endpoints (e.g., hERG IC50/blockage thresholds, CYP isoform inhibition status, and binary or estimated oral bioavailability ranges) for canonical, drug-like small molecules within the model's structural applicability domain. Cannot speak to full in vivo pharmacokinetics/dynamics (time-concentration profiles), dosage/formulation-dependent absorption nuances, active transporter-mediated clearance, species-specific physiological variability, or novel modalities outside typical small-molecule chemical space (such as PROTACs or large macrocycles).

---

## [119] source=multitask_sft_big

**USER:** We have prioritized five lead small-molecule candidates from our oncology campaign. Could you run an in silico ADMET screen on their SMILES strings to evaluate potential hERG cardiotoxicity (pIC50 or risk category), inhibitory potential against major CYP enzymes (specifically CYP3A4, CYP2D6, and CYP2C9), and predicted human oral bioavailability percentage?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN) / Pretrained Molecular Graph Ensemble (e.g., ADMET-AI / Chemprop): Can speak to: Statistical probabilities and regression-based estimates for in vitro endpoints (e.g., binary hERG inhibition risk, CYP isozyme inhibition flags, and general rule-of-five/QSPR-based oral bioavailability trends derived from 2D molecular graphs). Cannot speak to: In vivo physiological PK dynamics, exact human plasma concentration-time profiles, formulation-dependent dissolution/absorption factors, stereochemical or active-transporter-mediated clearance pathways not represented in training datasets, or idiosyncratic toxicities.

---

## [120] source=multitask_sft_big

**USER:** We have designed a series of 12 novel small-molecule analogs targeting CDK4/6 and need an early ADMET profiling report. Could you run predictions on their SMILES to evaluate cardiac toxicity risk via hERG inhibition, identify potential drug-drug interaction liabilities across major CYP enzymes (specifically CYP3A4, CYP2D6, and CYP2C9), and estimate human oral bioavailability (F > 20% or 30%)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN) / Chemprop trained on curated ADMET datasets (e.g., Therapeutics Data Commons / ADMET-AI): Can speak to in vitro assay proxy probabilities (e.g., categorical or semi-quantitative hERG channel block, substrate/inhibition flags for key CYP450 isoforms, and standardized human fraction absorbed/bioavailability classifications based on benchmark training sets). Cannot speak to complex in vivo multi-organ system pharmacokinetics, active metabolite toxicity, idiosyncratic drug-induced injury, formulation or food-effect modulations on absorption, or high-confidence predictions on chemotypes falling outside the training applicability domain.

---

## [121] source=multitask_sft_big

**USER:** I have a small-molecule lead series (12 analogs provided as SMILES) targeting a kinase. Could you run an in silico ADMET screen to predict their cardiotoxicity risk via hERG inhibition, potential metabolic clearance liabilities across major CYP enzymes (specifically CYP3A4 and CYP2D6 inhibition/substrate status), and estimated human oral bioavailability (%F) so we can prioritize compounds for our upcoming in vitro ADME panel?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN) or Molecular Transformer (e.g., Chemprop or Uni-Mol fine-tuned on Therapeutics Data Commons ADMET benchmarks): Can speak to: Fast relative ranking, binary risk flags (e.g., hERG blocker vs. non-blocker, CYP inhibition status), and qualitative bioavailability category predictions for standard drug-like organic small molecules within the training set's chemical space. Can't speak to: Dynamic in vivo pharmacokinetic profiles (e.g., Cmax, AUC, volume of distribution over time), organ-specific toxicity beyond off-target flags, active metabolite profiles, or reliable predictions for novel modalities (e.g., PROTACs, peptides, macrocycles) that lie outside the model's applicability domain.

---

## [122] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from a 10x Genomics 3' single-cell RNA-seq run of human peripheral blood mononuclear cells (PBMCs). Can you use a pretrained model to automatically classify and annotate cell types for each individual cell instead of manually labeling clusters via canonical marker genes?

**ASSISTANT:** Single-Cell Foundation Model / Transformer (e.g., scGPT, Geneformer, CellTypist): Can speak to: Robustly mapping individual transcriptional profiles to established cell ontologies and cell states, zero-shot or fine-tuned classification across shared tissue domains, and generalizing despite batch variations or sequencing depth differences. Can't speak to: Highly novel or abnormal cell types absent from training atlases, spatial context, post-transcriptional or protein-level abundances (unless paired multi-modal data is provided), or mechanistic causal drivers behind distinct cellular states.

---

## [123] source=multitask_sft_big

**USER:** I have synthesized a series of novel kinase inhibitor derivatives and need to prioritize them for lead optimization. Could you predict the aqueous solubility (logS) and lipophilicity (logD at pH 7.4) for these five compounds based on their SMILES strings?

**ASSISTANT:** Message Passing Neural Network (MPNN) / Directed MPNN (e.g., Chemprop) pretrained on molecular property datasets: Can reliably predict intrinsic solubility, partition coefficients, and empirical property trends for drug-like small molecules based on molecular topology and functional groups. Cannot account for experimental variables such as solid-state polymorphism, kinetic vs. thermodynamic dissolution behavior, formulation excipients, or pH/salt concentration shifts outside standard assay conditions.

---

## [124] source=multitask_sft_big

**USER:** We are optimizing a lead series of kinase inhibitors. Could you predict the aqueous solubility (LogS) and distribution coefficient at physiological pH (LogD7.4) for these candidate SMILES strings so we can triage which analogs to advance to in vitro ADME assays?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Transformer (e.g., Chemprop D-MPNN or ChemBERTa fine-tuned on ADMET datasets): Can speak to: Relative rankings of small molecules based on 2D topological features, estimation of thermodynamic solubility and lipophilicity within the chemical space of the training data, and structural motifs driving polarity. Cannot speak to: Solid-state crystal lattice energy, polymorphism, formulation/salt form effects, dynamic buffer-specific dissolution rates, or systemic in vivo pharmacokinetic outcomes (e.g., clearance, bioavailability).

---

## [125] source=multitask_sft_big

**USER:** We identified a novel de novo missense variant in the SCN1A gene (p.Arg1648Cys) in a pediatric patient presenting with drug-resistant early-onset epileptic encephalopathy. Can you predict whether this specific amino acid substitution is likely pathogenic or benign, and provide a computational pathogenicity score?

**ASSISTANT:** Deep learning missense variant pathogenicity predictor (e.g., AlphaMissense, PrimateAI-3D, ESM-1v): {'can_speak_to': ['Likelihood that the amino acid substitution disrupts protein structure or evolutionary-conserved function', 'Relative pathogenicity classification (benign, ambiguous, or pathogenic) benchmarked against population frequencies and curated databases (e.g., ClinVar)', 'Cross-species conservation and structural constraint at the specific residue level'], 'cant_speak_to': ['Definitive clinical diagnosis or deterministic disease causation for the individual patient', 'Phenotypic severity, age of onset, or drug responsiveness (e.g., Dravet syndrome vs. GEFS+)', 'Mechanisms outside protein coding changes, such as cryptic splicing alterations, promoter/enhancer effects, or somatic mosaicism', 'Modifiers such as incomplete penetrance, polygenic background, or epigenetic factors']}

---

## [126] source=multitask_sft_big

**USER:** I have the primary amino acid sequence for an uncharacterized bacterial esterase (285 residues). Could you predict its 3D tertiary structure, identify the catalytic triad orientation, and output the atomic coordinates in PDB format?

**ASSISTANT:** AlphaFold2 / ESMFold (Evoformer-based / Protein Language Model-based Structure Prediction Networks): Can reliably predict static ground-state monomeric 3D coordinates, backbone/side-chain conformations, and per-residue prediction confidence (pLDDT/PAE). Cannot definitively predict dynamic conformational ensembles, folding kinetics, thermal stability/thermodynamics, or precise small-molecule ligand-binding affinities and allosteric transitions without separate molecular dynamics or docking simulations.

---

## [127] source=multitask_sft_big

**USER:** We have designed a library of 150 novel small-molecule analogs targeting the ATP-binding pocket of human EGFR (PDB: 8A27). Could you predict the binding affinities (pKd/pIC50) of these ligands against the target structure to help prioritize candidates for subsequent in vitro kinase assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Protein-Ligand Complex Scoring (e.g., TankBind, EquiBind, or GNINA-style 3D-CNN/GNN): Can speak to: Relative binding ranking, pose-dependent physical complementarity (steric clash, H-bonding, hydrophobic contacts), and screening enrichment within similar chemical space. Cannot speak to: Absolute thermodynamic binding free energy (ΔG) with experimental accuracy, induced-fit pocket reorganization, entropic/explicit solvent desolvation effects, or functional downstream efficacy/ADMET properties.

---

## [128] source=multitask_sft_big

**USER:** Could you predict the aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) for this drug candidate: CC1=C(C(=O)N(C2=CC=CC=C12)C3=CC=C(C=C3)C(=O)NC4=NC=CS4)N? We are screening lead analogs for oral absorption.

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN / Chemprop fine-tuned on ESOL and Lipophilicity benchmarks): Can speak to intrinsic thermodynamic equilibrium solubility (logS) and distribution coefficients (logD) for small, drug-like organic molecules based on 2D chemical graph topology. Cannot speak to kinetic solubility, dissolution rate, physical state factors (e.g., crystalline polymorphs, salt forms, amorphous state, or particle size), formulation/excipient interactions, or ionization shifts across non-standard pH ranges.

---

## [129] source=multitask_sft_big

**USER:** We have designed a series of novel small-molecule kinase inhibitors (provided as SMILES strings) and need an initial in silico ADMET profiling before lead optimization. Could you predict their risk of hERG cardiotoxicity (IC50 / blocker liability), CYP450 inhibition potential (specifically CYP3A4 and CYP2D6), and predicted human oral bioavailability (%F)?

**ASSISTANT:** Message Passing Neural Network (MPNN) / Chemprop or Transformer-based Molecular Foundation Model (e.g., MolFormer, Uni-Mol) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: Quantitative or categorical structural alerts for hERG potassium channel blocking, binary classification of CYP isozyme inhibition, and estimated fraction of oral absorption/bioavailability derived from static 2D/3D chemical structures. Cannot speak to: In vivo multi-compartment pharmacokinetics, active transport dynamics (e.g., P-gp efflux or hepatic uptake), formulation or food-effect impacts on bioavailability, non-CYP clearance pathways, or definitive clinical cardiotoxicity without functional patch-clamp and in vivo PK experimental validation.

---

## [130] source=multitask_sft_big

**USER:** We identified several novel missense mutations in the TP53 and BRCA1 genes from a patient's whole-exome sequencing data (e.g., TP53 p.Arg175His and BRCA1 p.Cys61Gly). Can you predict whether these specific amino acid substitutions are likely pathogenic or benign, along with confidence scores for their functional impact?

**ASSISTANT:** Protein language model-derived missense variant effect predictor (e.g., AlphaMissense, ESM-1v, or PrimateAI-3D): Can speak to: predicting the relative likelihood that a single amino acid substitution disrupts protein structure and function, evolutionary constraint at the mutated site, and classifying missense variants as likely benign, ambiguous, or likely pathogenic. Can't speak to: non-coding variants, synonomous changes, large indels or structural rearrangements, specific patient phenotype or disease severity, penetrance, environmental modifier effects, or serving as an autonomous clinical diagnosis without guideline-based (ACMG/AMP) evidence synthesis.

---

## [131] source=multitask_sft_big

**USER:** I have an oncology lead candidate with SMILES 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'. Could you predict its aqueous solubility (LogS) and distribution coefficient (LogD at pH 7.4) to help assess its developability profile?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., D-MPNN or Graph Transformer fine-tuned on ADMET datasets like TDC/ChEMBL): Can predict 2D structure-derived physicochemical point estimates (logS, logD7.4) and relative property trends across related chemical analogs. Cannot account for solid-state crystal lattice energy, polymorphism, specific salt forms, experimental formulation additives, or generalize reliably to chemotypes heavily out-of-distribution from the training data.

---

## [132] source=multitask_sft_big

**USER:** I have an uncharacterized 320-residue enzyme sequence from an extremophilic bacterium: 'MKTIIALSYIFCLVFA...'. Could you predict its 3D atomic coordinates, generate a standard PDB structure, and provide per-residue confidence (pLDDT) metrics so I can assess whether the catalytic triad geometry is preserved?

**ASSISTANT:** AlphaFold2 (Evoformer / Attention-based Structural Biology Model): {'can': ['Predict highly accurate static 3D atomic coordinates (backbone and side chains) directly from primary amino acid sequences.', 'Output well-calibrated per-residue confidence scores (pLDDT) and domain-packing confidence (PAE).', 'Model rigid tertiary folds, domain organization, and, in specialized variants (AlphaFold-Multimer), stoichiometric protein-protein complexes.'], 'cannot': ['Simulate continuous conformational dynamics, intermediate folding pathways, or multiple functional states (e.g., open vs. closed transitions).', 'Reliably predict the destabilizing structural disruptions caused by single-point missense mutations.', 'Model non-protein entities natively without specialized variants/inputs (e.g., small-molecule drug ligands, metal ions, post-translational modifications (PTMs), or membrane bilayer environments).']}

---

## [133] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix (AnnData object) from human PBMC samples. Could you run a pretrained model to automatically classify and label the cell type for each cell?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer): Can speak to: identifying fine-grained and coarse cell types based on transcriptional signatures, zero-shot or fine-tuned label transfer across batch-effected datasets, and extracting latent cell embeddings. Cannot speak to: spatial tissue context, post-transcriptional/epigenetic modifications, temporal dynamic lineage without trajectory data, or novel/aberrant cell states not represented in the underlying reference training distribution.

---

## [134] source=multitask_sft_big

**USER:** I have the 3D crystal structure of the human EGFR kinase domain (PDB: 1M17) and a library of 150 small-molecule kinase inhibitor candidates in SMILES format. Can you predict the binding affinity (pIC50 or Kd) for each compound docked into the ATP-binding pocket so we can prioritize the top candidates for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) for Structure-Based Protein-Ligand Affinity Scoring: Can estimate thermodynamic binding affinity metrics (e.g., pKd, pKi, pIC50) and evaluate spatial and electrostatic complementarity from static structural complexes. Cannot reliably model large-scale protein induced-fit conformational shifts, compute kinetic rates (k_on/k_off), fully resolve explicit solvent entropic penalties, or infer cellular efficacy, off-target toxicity, and ADMET profiles.

---

## [135] source=multitask_sft_big

**USER:** I have the 3D crystal structure of the human CDK2 kinase domain and a set of 25 analog drug candidates in SDF format. Can you estimate the binding affinity (pKd/pKi) for each compound docked into the ATP-binding pocket so we can prioritize the top candidates for in vitro synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, or GNINA 3D-CNN scoring models): Can reliably score static structural complementarity, rank-order candidate congeners by estimated binding free energy, and highlight key non-covalent contacts (hydrogen bonds, pi-stacking, hydrophobic interactions). Cannot capture full thermodynamic entropic penalties, explicit water/desolvation dynamics, induced-fit conformational changes, covalent inhibition mechanisms, kinetic rates (kon/koff), or downstream cellular potency (IC50).

---

## [136] source=multitask_sft_big

**USER:** We have designed a library of 50 functionalized kinase inhibitors represented as SMILES. Could you predict their ADMET profiles—specifically flagging potential hERG liability (cardiotoxicity), CYP3A4 inhibition, and estimated percentage of human oral bioavailability (%F)—to help prioritize compounds for our upcoming in vitro pharmacokinetic assays?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Molecular Transformer (e.g., ChemBERTa) fine-tuned on curated ADMET datasets (such as Therapeutics Data Commons / ChEMBL): Can predict: In silico classification probabilities for in vitro liability (hERG inhibition >10 µM, CYP3A4 inhibition) and empirical estimates of human oral bioavailability based on 2D molecular structure. Cannot predict: Exact in vivo pharmacokinetic dynamics (e.g., clearance rates, Cmax, half-life), formulation or excipient effects, patient-specific metabolic variability (pharmacogenomics), or reliable predictions for novel scaffolds lying far outside the model's training applicability domain.

---

## [137] source=multitask_sft_big

**USER:** I have the co-crystal structure of human EGFR (PDB: 1M17) and docking poses for 20 novel small-molecule quinazoline derivatives. Can you predict their binding affinity (pKd or pKi values) and rank them to help us prioritize leads for synthesis?

**ASSISTANT:** Equivariant 3D Graph Neural Network / Structure-Based Scoring Model (e.g., GNINA, TankBind, or EquiBind-affinity): Can predict relative binding free energy and ranked affinity values (pKd/pKi/IC50 approximations) from 3D coordinates of non-covalent complex interfaces. Cannot reliably capture binding kinetics (association/dissociation rates), large induced-fit target conformational changes not captured in the input coordinates, solvent entropy thermodynamics, covalent inhibition mechanisms, or downstream ADMET/pharmacokinetic efficacy.

---

## [138] source=multitask_sft_big

**USER:** We have resolved the holo crystal structure of our kinase target (PDB format) and designed a library of 250 novel analog inhibitors (SDF format). Can you run an inference pipeline to predict the absolute binding affinity (pKd/Ki) for each complex and rank-order them to prioritize compounds for in vitro synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Networks (3D-EGNN) for Structure-Based Affinity Prediction (e.g., TankBind, GNINA, or EquiScore): Can speak to: Relative binding rank ordering, geometric complementary fit, and intermolecular interaction scoring (hydrogen bonding, hydrophobic contacts, steric clashes) from rigid or docked 3D co-complex conformations. Cannot speak to: True thermodynamic entropy and dynamic water displacement effects, induced-fit conformational transitions not captured in the static input structure, off-target promiscuity, or in vivo bioavailability/pharmacokinetics.

---

## [139] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (c.3944G>A, p.Arg1315His) in an infant presenting with severe early-onset epilepsy. Can you predict the pathogenicity score for this variant and tell us whether it is likely disease-causing?

**ASSISTANT:** AlphaMissense (Deep structural and evolutionary variant effect predictor): Can speak to: predicting the likelihood that an amino acid substitution (missense variant) is benign or pathogenic based on structural context and evolutionary conservation. Cannot speak to: non-coding variants, indels, synonymous mutations, splicing impacts, clinical penetrance, specific phenotypic severity, or definitive clinical diagnosis independent of comprehensive ACMG/AMP guideline criteria.

---

## [140] source=multitask_sft_big

**USER:** I have an AnnData object with filtered, normalized single-cell RNA-seq count matrices from human peripheral blood mononuclear cells (PBMCs). Can you predict the high-resolution cell-type identity for each single-cell profile?

**ASSISTANT:** Transformer-based Single-Cell Foundation Model (e.g., scGPT, Geneformer): Can speak to: Assigning cell-type annotations based on learned gene-gene regulatory networks, mapping query expression profiles against known reference atlases, and identifying major and minor canonical immune subpopulations. Cannot speak to: Conclusively identifying novel or uncharacterized cell types outside the training distribution, establishing causal transcriptional trajectories/lineage dynamics without longitudinal data, or resolving misclassifications caused by severe ambient RNA contamination or uncorrected batch effects.

---

## [141] source=multitask_sft_big

**USER:** I have a library of 250 drug-like small-molecule SMILES generated for a kinase inhibitor project. Can you predict their aqueous solubility (logS) and lipophilicity (logD at pH 7.4) so we can prioritize the most bioavailable leads for synthesis?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) pretrained on PubChem/ChEMBL and fine-tuned on ADMET benchmarks (e.g., ESOL, Lipophilicity): Can accurately estimate baseline aqueous solubility (logS) and physiological lipophilicity (logD7.4) from 2D molecular graph representations for small-molecule drug candidates within standard chemical space. Cannot reliably predict solid-state properties (e.g., crystal polymorphs, amorphous transitions), dissolution kinetics, formulation/excipient interactions, or behavior of non-small-molecule modalities like large macrocycles and peptides.

---

## [142] source=multitask_sft_big

**USER:** I have the 3D crystal structure of the human EGFR kinase domain (PDB: 1M17) and a library of 50 novel quinazoline derivatives as SMILES strings. Can you predict the binding affinity (pKd/IC50 values) of each compound against this target to prioritize candidates for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Protein-Ligand Complex Scoring (e.g., EGNN/SE(3)-Transformer trained on PDBbind): Can reliably score and rank static physical interactions, interatomic distances, and typical non-covalent contacts (hydrogen bonding, hydrophobic packing) from 3D co-crystal or docked poses. Cannot reliably account for dynamic solvent thermodynamics (entropy/free energy landscapes), large-scale induced-fit receptor conformational shifts, or translate predicted affinity into in vivo pharmacokinetic efficacy, selectivity, or toxicity.

---

## [143] source=multitask_sft_big

**USER:** I have a small batch of drug-like candidates represented as SMILES strings (e.g., 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'). Can you predict their aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) to help us prioritize leads for synthesis?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Molecular Language Model (ChemBERTa-2): Can accurately estimate scalar physicochemical properties (logS, logD) for standard small organic molecules based on topological/molecular graph features within the training distribution. Cannot account for solid-state crystal packing (polymorphism), temperature/ionic strength variations in real buffers, dynamic 3D conformational equilibria, or reliably extrapolate to macrocycles, covalent adducts, and organometallics.

---

## [144] source=multitask_sft_big

**USER:** We have 15 newly designed small-molecule kinase inhibitors as SMILES strings. Could you run an in silico ADMET screen to predict their hERG channel inhibition risk, CYP3A4/CYP2D6 inhibitory potential, and predicted percentage of human oral bioavailability?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop / ADMET-AI) trained on ADMET benchmark datasets (such as Therapeutics Data Commons and ChEMBL): Can speak to: Rapid quantitative or binary classification estimates of hERG-mediated cardiotoxicity risk, CYP isozyme inhibition flags, and molecular structure-derived oral bioavailability likelihood within the applicability domain of the training chemical space. Cannot speak to: In vivo physiological PK complexities (e.g., first-pass hepatic extraction ratio, non-linear transporter interactions, food-effect dynamics, formulation-dependent solubility/dissolution rates) or definitive clinical safety profiles without experimental validation.

---

## [145] source=multitask_sft_big

**USER:** We have 15 optimized lead compounds for an oncology target represented as SMILES. Can you evaluate their drug-likeness profiles by predicting hERG liability (cardiotoxicity risk), CYP450 inhibition potential (specifically CYP3A4, CYP2D6, and CYP2C9), and estimated human oral bioavailability (percentage or F > 30%)?

**ASSISTANT:** Multitask Directed Message-Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: In vitro risk scoring and binary/ranking classifications for hERG channel blockade (IC50 threshold), competitive CYP450 isoform inhibition, and historical categorical oral bioavailability likelihood within the model's structural applicability domain. Can't speak to: Dynamic in vivo human pharmacokinetic curves (Cmax, Tmax, AUC), dose-dependent or formulation-dependent exposure, time-dependent/mechanism-based CYP inactivation, organ-specific clearance mechanisms, or structural classes significantly underrepresented in the TDC training data.

---

## [146] source=multitask_sft_big

**USER:** We are prioritizing five lead small-molecule candidates from our lead optimization series (provided as SMILES strings) for an oncology program. Could you predict their ADMET profiles, specifically hERG liability (cardiotoxicity risk), CYP450 inhibition potential across CYP3A4 and CYP2D6, and predicted human oral bioavailability percentage?

**ASSISTANT:** Multitask Directed Message Passing Neural Network (D-MPNN, e.g., ADMET-AI / Chemprop trained on TDC benchmarks): Can speak to: Rapid quantitative or binary classification estimates of in vitro hERG blockage, CYP isoform inhibition, and general oral absorption likelihood directly from 2D molecular structures within drug-like chemical space. Cannot speak to: In vivo multi-compartment pharmacokinetic time-course dynamics, crystal form/solubility issues, carrier-mediated transport anomalies, drug-drug interactions driven by non-CYP pathways, or macromolecules/peptides outside its small-molecule training domain.

---

## [147] source=multitask_sft_big

**USER:** We have designed a library of 50 novel small-molecule kinase inhibitor analogues (provided as SMILES). Before advancing to synthesis, could you predict their hERG channel inhibition risk, CYP3A4/2D6 liability, and estimated oral bioavailability percentage?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Molecular Transformer (e.g., MolFormer-XL) fine-tuned on multi-task ADMET benchmarks (such as TDC or ChEMBL): {'can_speak_to': 'Static structure-property relationships, qualitative or semi-quantitative risk scoring for in vitro hERG blockage (cardiotoxicity flag), probabilistic classification of major CYP isozyme inhibition, and empirical classification/ranking of oral bioavailability within familiar chemical space.', 'cant_speak_to': 'Complex dynamic in vivo pharmacokinetics (PBPK profile, AUC, Cmax), dose-dependent or formulation-dependent exposure, active transport kinetics, non-CYP clearance mechanisms, or true clinical safety/toxicity thresholds.'}

---

## [148] source=multitask_sft_big

**USER:** I have a library of 450 drug-like small molecules formatted as SMILES strings. Can you predict their aqueous solubility (logS) and distribution coefficient (logD at pH 7.4) to help us triage candidates with poor oral bioavailability before synthesis?

**ASSISTANT:** Pretrained Molecular Transformer / Graph Neural Network (e.g., ChemBERTa-2 or Uni-Mol): Can accurately predict intrinsic equilibrium solubility (logS) and lipophilicity (logD) for standard small organic molecules based on chemical structure, functional groups, and 2D/3D representations, providing effective rank-ordering for early-stage screening. Cannot speak to dynamic dissolution rates, solid-state crystal lattice energy/polymorphism, counter-ion and salt-form influences, temperature-dependent behavior, or interactions introduced by formulation excipients and complex biological fluids.

---

## [149] source=multitask_sft_big

**USER:** We have designed a series of small-molecule kinase inhibitors targeting the ATP-binding pocket of human EGFR (PDB: 1M17). Can you predict the binding affinity (pKd or IC50 values) for these candidates against the receptor to prioritize the top compounds for synthesis?

**ASSISTANT:** Structure-Aware 3D Graph Neural Network for Protein-Ligand Affinity Prediction (e.g., GNINA, TankBind, or Pafnucy): It can estimate relative binding free energies, rank candidate ligands by predicted affinity (Kd/Ki/IC50) within a defined 3D structural pocket, and identify favorable steric or electrostatic contacts. It cannot speak to functional drug mechanisms (e.g., whether a ligand acts as an agonist or antagonist), binding kinetics (on/off rates), large-scale dynamic conformational shifts/induced fit, proteome-wide off-target selectivity, or in vivo ADMET and pharmacokinetics.

---

## [150] source=multitask_sft_big

**USER:** I have isolated an uncharacterized 189-amino-acid enzyme with the sequence 'MTEYKLVVVGAGGVGKSALTIQLIQNHFVDEYDPTIEDSYRKQVVIDGETCLLDILDTAGQEEYSAMRDQYMRTGEGFLCVFAINNTKSFEDIHQYREQIKRVKDSDDVPMVLVGNKCDLAARTVESRQAQDLARSYGIPYIETSAKTRQGVEDAFYTLVREIRQHKLRKLNPPDESG'. Can you predict its 3D coordinates in PDB format and output local confidence scores for the fold?

**ASSISTANT:** Equivariant/Transformer-based Protein Structure Prediction Model (e.g., AlphaFold2, ESMFold): Can determine static ground-state 3D Cartesian coordinates (backbone and side chains) and estimate local and global structural confidence (pLDDT, PAE). Cannot reliably predict dynamic conformational transitions, thermodynamics/free-energy landscapes (e.g., folding pathways or ΔΔG of mutations), functional kinetics, or environmental variations such as explicit solvent, pH, and post-translational modifications.

---

## [151] source=multitask_sft_big

**USER:** I have an uncharacterized 240-residue sequence for a putative esterase from an environmental metagenomic sample: 'MAKTLLVLFLLSLALAGP...'. Can you predict its 3D atomic coordinates, identify potential active site pocket conformations, and provide the predicted local confidence scores per residue in PDB format?

**ASSISTANT:** AlphaFold2 / ESMFold (Evoformer-based or Transformer protein language model structure predictors): Can reliably predict static ground-state 3D backbone/side-chain coordinates, per-residue confidence scores (pLDDT), domain orientation confidence (PAE), and likely active site pocket geometries. Cannot speak to folding kinetics/pathway dynamics, true conformational ensembles across physiological states, quantitative thermodynamic stability (ΔΔG), binding affinity constants (Kd), or structural alterations caused by unmodeled post-translational modifications and non-standard ligands.

---

## [152] source=multitask_sft_big

**USER:** We found a novel de novo missense variant in the SCN1A gene (c.4942C>T, p.Arg1648Cys) in a pediatric patient with early-onset severe epilepsy. Could you predict whether this specific amino acid change is pathogenic or benign?

**ASSISTANT:** Pretrained deep learning variant effect predictor (e.g., AlphaMissense, ESM-1v): Can score the likelihood of molecular disruption and classify the missense change as likely pathogenic, benign, or ambiguous based on structural context and evolutionary conservation. Cannot establish clinical penetrance, determine specific phenotypic severity or disease onset, account for patient-specific genetic background/modifiers, evaluate splicing or non-coding impacts, or substitute for formal ACMG/AMP clinical diagnostic classification.

---

## [153] source=multitask_sft_big

**USER:** I have an unannotated AnnData (.h5ad) object containing single-cell RNA sequencing raw counts for approximately 40,000 cells from human peripheral blood mononuclear cells (PBMCs). Could you use a pretrained model to classify and annotate the cell types present in this sample without requiring me to manually curate marker gene lists?

**ASSISTANT:** Single-cell transcriptomic foundation model (Transformer-based, e.g., scGPT, Geneformer, scBERT): Can speak to: automated cell-type annotation across canonical immune and tissue lineages, robust embedding of high-dimensional gene expression vectors, and cross-batch generalization across standard 10x/scRNA-seq platforms. Cannot speak to: identifying completely novel, non-cataloged cell types or aberrant disease-specific transitional states without fine-tuning; inferring spatial context, protein abundance, or post-transcriptional regulation from mRNA counts alone; or providing clinically actionable diagnostic conclusions.

---

## [154] source=multitask_sft_big

**USER:** I have the crystal structure of the human EGFR kinase domain (PDB: 1M17) and 40 novel small-molecule quinazoline analogs. Could you predict the binding affinity (pK_d or Delta G) of each docked pose to help us prioritize the top 5 candidates for in vitro synthesis and binding assays?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., TankBind, PIGNet, or GNINA-derived 3D-CNN scoring functions): Can reliably predict relative binding affinities (e.g., pKd, pIC50 ranking) and score physical contact complementary within rigid or semi-rigid binding pockets for structural analogs. Cannot predict functional downstream efficacy (e.g., agonist vs. antagonist behavior), induced-fit conformational changes, non-equilibrium binding kinetics (k_on/k_off residence time), off-target selectivity, or cell permeability and ADMET properties.

---

## [155] source=multitask_sft_big

**USER:** I have the co-crystal structure of human CDK2 (PDB: 1HCK) and a batch of 25 novel pyrazole-based small-molecule derivatives as SMILES strings. Can you predict the binding affinity (pKd/pKi) for each compound against the CDK2 ATP-binding site to help us prioritize which analogs to synthesize?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, GNINA): Can predict: Relative binding affinity rankings (pKd/pKi/IC50 proxy), approximate ligand binding pose/coordinates within the pocket, and static non-covalent interactions (e.g., hydrogen bonding, pi-stacking, steric fit). Cannot predict: Absolute association/dissociation kinetics (k_on, k_off, residence time), full induced-fit protein conformational dynamics, thermodynamic entropy changes from displaced solvent networks, covalent binding mechanisms, or downstream in vitro/in vivo ADMET and efficacy profiles.

---

## [156] source=multitask_sft_big

**USER:** Here is the SMILES representation of our lead optimization compound: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5. Can you predict its intrinsic aqueous solubility (logS) and distribution coefficient (logD at physiological pH 7.4) to evaluate whether it meets our oral bioavailability criteria?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Transformer (e.g., ChemBERTa, Uni-Mol, or D-MPNN/Chemprop fine-tuned on ADMET benchmarks like TDC or ChEMBL): Can accurately predict thermodynamic aqueous solubility (logS) and octanol-water distribution (logD) based on 2D chemical topology or learned 3D conformations, and rank structural analogs relative to training domain distributions. Cannot reliably account for crystal lattice energy, specific salt forms, or solid-state polymorphism effects; cannot predict solubility in complex multicomponent formulation vehicles or dynamic, non-standard pH microenvironments without explicit co-solvent and ionization modeling; and cannot substitute for empirical in vivo pharmacokinetic absorption studies.

---

## [157] source=multitask_sft_big

**USER:** I have isolated a novel 340-residue uncharacterized hydrolase from a soil metagenomic sample (FASTA sequence provided below). Can you generate its predicted 3D atomic coordinates in PDB format and tell me which regions have high structural confidence?

**ASSISTANT:** Attention- and Invariant/Equivariant-based Protein Structure Prediction Models (e.g., AlphaFold2, ESMFold): Can reliably predict static, ground-state 3D Cartesian coordinates (backbone and side chains) and provide local/global confidence metrics (pLDDT, PAE). Cannot simulate dynamic conformational ensembles across changing physiological conditions (e.g., pH, temperature, membrane environments), determine catalytic kinetics/reaction mechanisms, or reliably calculate thermodynamic folding stability changes (ΔΔG) from single-point mutations without downstream biophysical modeling.

---

## [158] source=multitask_sft_big

**USER:** I have an unannotated count matrix of 18,000 single cells from a human bone marrow 10x Genomics scRNA-seq experiment. Can you apply a pretrained foundation model to predict and assign fine-grained cell-type labels to each cell barcode?

**ASSISTANT:** Single-cell Pretrained Transformer (e.g., scGPT or Geneformer): Can speak to: predicting canonical and intermediate immune/hematopoietic cell types based on contextual gene co-expression patterns, handling batch variability, and cross-dataset label transfer. Cannot speak to: identifying entirely novel/uncharacterized cell types not represented in the pretraining atlas, resolving non-transcriptomic functional states (e.g., post-translational modifications), or disentangling technical artifacts like doublets and ambient RNA contamination without separate quality control.

---

## [159] source=multitask_sft_big

**USER:** I have the amino acid sequence of a novel bacterial hydrolase (MAA...KLG, 342 residues). Can you predict its 3D tertiary structure, provide the atomic coordinates in PDB format, and give confidence scores for the catalytic triad region?

**ASSISTANT:** AlphaFold2 / ESMFold (Transformer-based structural biology deep learning models): Can reliably predict static 3D atomic coordinates (PDB/mmCIF), backbone and side-chain conformations, and assign per-residue and pairwise confidence scores (pLDDT, PAE). Cannot model dynamic conformational transitions, real-time folding kinetics, structural changes induced by arbitrary ligand/cofactor binding, or reliably resolve intrinsically disordered regions (IDRs).

---

## [160] source=multitask_sft_big

**USER:** I have a library of 150 novel small-molecule kinase inhibitor candidates as SMILES strings. Can you predict their aqueous solubility (logS) and lipophilicity (logD at pH 7.4) so our medicinal chemistry team can prioritize compounds with viable oral bioavailability?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., Chemprop / D-MPNN) or Chemical Language Model (e.g., ChemBERTa / MolFormer): Can rapidly predict physicochemical properties and rank drug-like analogs based on molecular structure and 2D topology within trained chemical domains. Cannot account for solid-state crystal polymorphism/lattice energy effects that dictate real-world dissolution, dynamic formulation effects, or complex in vivo absorption and metabolic clearance.

---

## [161] source=multitask_sft_big

**USER:** I have a 10x Genomics 3' scRNA-seq dataset of human peripheral blood mononuclear cells (PBMCs) stored in an AnnData object with raw UMI counts across ~15,000 cells. Could you predict and assign discrete immune cell-type labels to each individual cell using a pretrained model?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer) / Transformer-based scRNA Foundation Models: Can accurately map single-cell gene expression profiles to known reference cell types, impute missing values, and generalize across platforms and batch variations. Cannot reliably characterize completely novel or non-cataloged disease-specific cell states absent from reference training sets, predict surface protein abundance directly from transcript counts, or provide definitive biological validation without experimental confirmation.

---

## [162] source=multitask_sft_big

**USER:** We are optimizing a lead series of small-molecule kinase inhibitors. Could you predict the aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) for these 30 novel SMILES strings so we can filter out compounds with poor oral bioavailability profiles?

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Chemical Language Model (e.g., ChemBERTa) fine-tuned on curated ADME benchmark datasets: Can speak to: In silico estimates of equilibrium thermodynamic solubility (logS) and octanol-water distribution at pH 7.4 (logD7.4) based on 2D molecular topology, relative ranking of analogs within drug-like chemical space, and identification of lipophilicity flags. Can't speak to: Solid-state crystal lattice energy and polymorphism, kinetic dissolution rates, precipitation dynamics in specific assay buffers, formulations/excipient effects, or compounds far outside the model's training domain (such as large macrocycles, PROTACs, or inorganic complexes).

---

## [163] source=multitask_sft_big

**USER:** I detected a novel heterozygous missense variant in the BRCA1 gene (c.5095C>T, p.Arg1699Trp) through exome sequencing of a patient with a strong family history of breast cancer. Can you predict the pathogenicity score for this variant to help determine if it is disease-causing or benign?

**ASSISTANT:** Protein Language Model / Deep Learning Variant Effect Predictor (e.g., AlphaMissense, ESM-1v): Can quantify evolutionary constraint, likelihood of protein structural destabilization, and statistical probability of deleterious effects for missense mutations. Cannot provide definitive clinical diagnoses, determine age-dependent penetrance or epigenetic factors, assess non-coding or splicing-mediated impacts, or replace functional laboratory assays and ACMG/AMP clinical classification criteria.

---

## [164] source=multitask_sft_big

**USER:** I have an uncharacterized 280-amino-acid enzyme sequence from an extremophile bacterium (FASTA: >target_protein MKTLLLLT...VKG). Can you predict its complete 3D atomic coordinates, generate a PDB file, and provide per-residue confidence scores to see if it adopts a known TIM-barrel fold?

**ASSISTANT:** AlphaFold2 (or ESMFold): Can: Accurately predict static tertiary 3D atomic coordinates (backbone and side chains) from primary amino acid sequences, assess local folding reliability via pLDDT scores, and indicate domain-packing confidence via Predicted Aligned Error (PAE). Cannot: Reliably predict the disruptive structural impact of single point mutations, simulate dynamic conformational transitions/folding kinetics, or model the precise atomic coordinates of non-covalent ligands, cofactors, ions, and post-translational modifications without specialized extensions.

---

## [165] source=multitask_sft_big

**USER:** We have designed a series of small-molecule kinase inhibitors. Could you evaluate their lead-likeness by predicting hERG cardiac toxicity liability (pIC50), CYP450 inhibition profiles (specifically CYP3A4 and CYP2D6), and estimated percentage of human oral bioavailability from their SMILES strings?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN) / Graph Neural Network ensemble for ADMET (e.g., Chemprop trained on Therapeutics Data Commons or ADMET-AI): Can speak to: Rapid in silico screening of drug-like small molecules for in vitro hERG liability, substrate/inhibition likelihood against major CYP isoforms, and empirical oral bioavailability categorization based on historical training data. Can't speak to: Complex in vivo pharmacokinetics (e.g., clearance rates, volume of distribution, tissue distribution), dose-dependent saturation or drug-drug interactions, impact of specific drug formulations/prodrug strategies, or accurate profiling for chemical modalities outside its training domain (e.g., PROTACs, peptides, macrolides).

---

## [166] source=multitask_sft_big

**USER:** We have prioritized three candidate SMILES for our lead optimization campaign (e.g., 'CC1=C(C(=O)N2CCCC2)C=C(NC(=O)C3CCN(CC3)C)C=C1'). Could you evaluate their ADMET profiles, specifically predicting hERG-mediated cardiotoxicity risk (blocker vs. non-blocker), inhibition likelihood across major CYP isoforms (CYP3A4, CYP2D6, CYP2C9), and estimated human oral bioavailability percentage (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN / Chemprop, such as ADMET-AI): Can speak to: Rapid in silico screening, relative candidate ranking, and statistical probability of hERG liability, CYP450 cross-reactivity, and medium-to-high oral absorption within well-represented small-molecule chemical space. Cannot speak to: Absolute in vivo PK profiles, dynamic tissue distribution, non-CYP or renal clearance mechanisms, formulation effects (e.g., solubility/excipient interactions), species differences, or reliable predictions for novel macrocycles and molecules far outside the training distribution's applicability domain.

---

## [167] source=multitask_sft_big

**USER:** I have an uncharacterized kinase sequence from a newly sequenced thermophile: 'MVKLTAELIEQAAQYTNAVRDAGEIL...'. Can you predict its 3D atomic coordinates in PDB format and highlight regions with high confidence (pLDDT > 70) versus disordered loops?

**ASSISTANT:** AlphaFold2 (Evoformer-based Structure Prediction Network): Can accurately predict static ground-state tertiary structures, backbone/side-chain coordinates, and provide per-residue confidence (pLDDT) and domain packing confidence (PAE). Cannot reliably model full conformational dynamics/kinetics, environmental effects (pH, temperature, salt concentration), accurate ligand/cofactor-bound states without co-modeling, or the destabilizing structural effects of single-point missense mutations.

---

## [168] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense mutation (c.5096G>A, p.Arg1699Gln) in the BRCA1 gene of a patient with early-onset breast cancer. Could you predict whether this variant is pathogenic or benign and provide a confidence score?

**ASSISTANT:** Deep learning-based variant effect predictor (e.g., AlphaMissense, ESM-1v, or PrimateAI-3D): Can predict the likelihood that a missense amino acid substitution disrupts protein structure and biochemical function based on evolutionary conservation and structural context. Cannot independently diagnose clinical disease, determine penetrance or age of onset, evaluate non-coding or structural variants (in missense-only models), or substitute for ACMG/AMP clinical validation guidelines.

---

## [169] source=multitask_sft_big

**USER:** We identified a novel missense variant, c.742C>T (p.Arg248Trp), in the TP53 gene of an oncology patient. Can you run this through an in silico predictor to assess whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Structural-evolutionary deep learning variant effect predictor (e.g., AlphaMissense, ESM-based pathogenicity classifiers): Can score the likelihood of single-nucleotide missense variants causing molecular damage or functional disruption based on structural context and evolutionary conservation. Cannot evaluate non-coding variants, indels, complex epistatic interactions, or provide definitive clinical diagnoses or variant penetrance without supporting clinical, familial, and functional assay evidence.

---

## [170] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from an unannotated 10x Genomics 3' single-cell RNA-seq experiment on human peripheral blood mononuclear cells (PBMCs). Can you run an automated cell-type annotation pipeline to assign discrete cell-type labels and confidence scores to each barcode?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer for Cell-Type Classification): Can reliably predict discrete cell-type identities from single-cell transcriptomic profiles and transfer annotations across technical batches and sequencing platforms based on reference fine-tuning. Cannot reliably identify novel or uncharacterized cell states absent from the reference corpus (often misclassifies them into nearest seen classes), nor can it independently validate functional phenotypes, spatial context, or post-transcriptional protein dynamics purely from single-cell mRNA counts.

---

## [171] source=multitask_sft_big

**USER:** I have designed a series of novel small-molecule kinase inhibitors. Here is the SMILES string for our primary lead: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5. Can you estimate its intrinsic aqueous solubility (logS) and lipophilicity (logD at pH 7.4)?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) or Molecular Transformer (e.g., ChemBERTa) fine-tuned on ADMET benchmarks (such as MoleculeNet ESOL and ChEMBL Lipophilicity datasets): Can speak to: Quantitative estimation of equilibrium thermodynamic aqueous solubility (logS) and distribution coefficients (logD at fixed physiological pH) derived from 2D topological graphs and functional group encodings, as well as substructure-level attribution. Cannot speak to: Solid-state polymorph behavior, crystal lattice energy, dynamic dissolution rates, excipient-specific formulation effects, degradation kinetics, or precise in vivo pharmacokinetic distribution without experimental and physiologically based pharmacokinetic (PBPK) modeling.

---

## [172] source=multitask_sft_big

**USER:** I have an uncharacterized 340-amino acid sequence from a newly sequenced bacterial strain (FASTA: MKTIIALSYIFCLVFA...). Can you predict its tertiary 3D atomic coordinates, output a PDB file, and provide the per-residue pLDDT confidence scores?

**ASSISTANT:** AlphaFold2 (Evoformer-based deep learning structure prediction model): Can predict static 3D Cartesian coordinates of the native ground-state fold, secondary structure elements, inter-residue contacts, and per-residue confidence (pLDDT/PAE). Cannot accurately determine dynamic conformational equilibrium, transition state folding kinetics, the energetic impacts of non-covalent ligand/cofactor binding, or structured states for intrinsically disordered regions (IDRs).

---

## [173] source=multitask_sft_big

**USER:** We identified a novel missense variant in the BRCA1 gene (c.5095C>T, p.Arg1699Trp) during a hereditary cancer screening panel. Could you predict whether this variant is likely pathogenic or benign, and provide a confidence score?

**ASSISTANT:** AlphaMissense (Structural-evolutionary missense variant pathogenicity predictor): Can predict whether single-amino-acid missense substitutions are likely pathogenic or benign based on structural context from AlphaFold and evolutionary conservation across organisms. Cannot evaluate non-coding variants, frameshifts, indels, or synonymous mutations, cannot detect splicing alterations, and cannot determine disease penetrance or serve as a standalone clinical diagnosis without functional/clinical validation.

---

## [174] source=multitask_sft_big

**USER:** Here is the SMILES string for our lead compound: 'CC1=C(C(=O)N(C1=O)C2=CC=C(C=C2)C#N)N3CCN(CC3)C(=O)C4CC4'. Can you estimate its aqueous solubility (logS) and distribution coefficient (logD at physiological pH 7.4) before we order in vitro ADME profiling?

**ASSISTANT:** Pretrained Molecular Graph Neural Network or Chemical Language Model (e.g., ChemBERTa or D-MPNN / Chemprop fine-tuned on ADME benchmarks): {'can_speak_to': ['Relative rankings and quantitative estimates of thermodynamic/kinetic aqueous solubility and lipophilicity (logS, logP, logD at fixed pH 7.4) for drug-like small molecules.', 'Structural alerts and substructural feature attributions driving high/low lipophilicity or poor solubility.'], 'cant_speak_to': ['Solid-state crystal packing effects, polymorphism, or amorphous-form solubility variations.', 'Solubility in complex multi-solvent matrices, variable ionic strengths, or non-standard temperature/pH regimes not present in the training set.', 'Out-of-distribution structures such as organometallics, macrocycles, or high-molecular-weight biologics.']}

---

## [175] source=multitask_sft_big

**USER:** I identified a novel heterozygous missense variant in the TP53 DNA-binding domain (chr17:7674220 C>T, p.Arg273His) in a patient with suspected Li-Fraumeni syndrome. Can you evaluate the predicted pathogenicity of this amino acid substitution?

**ASSISTANT:** AlphaMissense (or similar structural-evolutionary deep learning missense variant effect predictor): Can predict the likelihood that a single amino acid substitution disrupts protein function, outputting continuous pathogenicity scores and discrete classifications (likely benign, likely pathogenic, or ambiguous) across human proteins. Cannot evaluate non-coding, synonymous, frameshift, or structural variants, nor can it account for clinical penetrance, gene-dosage effects, patient-specific phenotypes, or replace formal ACMG/AMP clinical variant classification guidelines.

---

## [176] source=multitask_sft_big

**USER:** I generated a single-cell RNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs) and need to annotate the cell types. Can you run this profile through an automated model to predict the specific cell lineages and states without manual cluster marker curation?

**ASSISTANT:** scGPT (single-cell Generative Pre-trained Transformer): Can speak to: High-accuracy cell type annotation across standard immune/tissue atlases, multi-batch data integration, latent cell state representations, and gene-gene interaction embeddings derived from transcript abundance. Can't speak to: Novel or unrepresented rare cell states absent from the pre-training reference, post-transcriptional or epigenetic regulation, spatial tissue architecture, or causal gene regulatory mechanisms without perturbation data.

---

## [177] source=multitask_sft_big

**USER:** Here is the amino acid sequence of an uncharacterized dehalogenase from a marine bacterium: 'MSIQHFRVALIPFFAAFCLPVFAHPETLVKVKDAEDQLGARVGYI...'. Can you predict its full 3D tertiary structure and generate the atomic coordinates in PDB format?

**ASSISTANT:** End-to-end evolutionary/attention-based protein structure prediction network (e.g., AlphaFold2, ESMFold): Can accurately predict static 3D backbone and side-chain atomic coordinates, secondary structure features, domain architecture, and per-residue confidence scores (pLDDT/PAE). Cannot reliably model real-time kinetic folding pathways, multi-state conformational transitions under physiological fluctuations, or the explicit structural effects of environmental variables like pH, temperature, post-translational modifications, and small-molecule ligand binding (unless explicitly trained on multi-modal complexes).

---

## [178] source=multitask_sft_big

**USER:** Here is an uncharacterized amino acid sequence for a putative bacterial esterase: 'MTEITAAMVKELRESTGAGMMDCKNALH...'. Can you predict its full 3D tertiary structure and output the atomic coordinates in PDB format so we can locate the catalytic triad?

**ASSISTANT:** Evoformer and Protein Language Model Structure Predictors (e.g., AlphaFold2, ESMFold): Can reliably predict static 3D backbone and side-chain coordinates, tertiary fold topology, multimeric interfaces (via AlphaFold-Multimer), and residue-level confidence metrics (pLDDT and PAE). Cannot model dynamic conformational ensembles and folding kinetics, accurately resolve intrinsically disordered regions, predict the impact of post-translational modifications, or natively model non-protein cofactors and small-molecule ligand interactions.

---

## [179] source=multitask_sft_big

**USER:** We have synthesized five novel kinase inhibitor analogues for an oncology program. Could you screen these SMILES strings to evaluate their ADMET profiles, specifically predicting hERG-mediated cardiotoxicity risks, inhibition potential against major CYP enzymes (CYP3A4, CYP2D6, CYP2C9), and expected human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Message Passing Neural Network / Molecular Graph Transformer (e.g., Chemprop D-MPNN or MolFormer fine-tuned on Therapeutics Data Commons ADMET benchmarks): Can speak to: Statistical probabilities and predicted threshold values for hERG channel blockade, CYP450 isoform inhibition/substrate likelihood, and categorical or regression-based estimates of human oral bioavailability derived from 2D/3D chemical topology. Cannot speak to: Time-dependent in vivo pharmacokinetic parameters (Cmax, Tmax, clearance curves without full PBPK modeling), formulation/solubility-enhancement effects, patient-specific metabolic differences (pharmacogenomics), active gut transport mechanisms not represented in training sets, or definitive in vivo cardiotoxicity.

---

## [180] source=multitask_sft_big

**USER:** I have the crystal structure of the SARS-CoV-2 main protease (PDB: 7BQY) and docked poses for 200 small-molecule inhibitors in SDF format. Can you predict the binding affinity (pKd or binding free energy ΔG) for each protein-ligand complex to help prioritize leads for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (3D-EGNN) / Structure-Based Geometric Deep Learning Model: Can predict relative ranking and thermodynamic binding affinities (pKd, pKi, ΔG) from static 3D spatial contacts and atomic interactions. Cannot predict binding kinetics (kon, koff, residence time), full induced-fit protein dynamics occurring over long timescales, solvent entropy effects accurately without explicit simulation, or downstream in vivo pharmacokinetic/ADMET profiles.

---

## [181] source=multitask_sft_big

**USER:** I have isolated a putative 380-amino-acid metalloprotease from an uncultured marine bacterium with the sequence 'MKLSTVLLSL...'. Can you predict its full 3D monomer structure and give me residue-level confidence scores to see if the active site cleft is well-resolved?

**ASSISTANT:** AlphaFold2 (MSA- and Evoformer-based protein structure prediction model): Can speak to: High-accuracy predicted 3D atomic coordinates (static tertiary structure), relative inter-domain orientations, and model confidence estimates (pLDDT scores and Predicted Aligned Error). Cannot speak to: Solution dynamics/kinetic pathways, thermodynamic stability (delta G), impacts of environmental conditions (pH, temperature, membrane context), post-translational modifications, or coordinated ion/ligand binding chemistry without explicit co-factor conditioning.

---

## [182] source=multitask_sft_big

**USER:** I have isolated an uncharacterized enzyme from a metagenomic sample with the sequence 'MKVLVLGSGGREHALAWKLAQS...'. Can you predict its 3D tertiary structure in PDB format and provide the residue-level confidence scores?

**ASSISTANT:** AlphaFold2 (or ESMFold / OpenFold): Can predict static ground-state 3D atomic coordinates, global fold topology, secondary structure elements, and per-residue prediction confidence (pLDDT/PAE). Cannot predict thermodynamic folding pathways, continuous conformational dynamics in solution, binding affinity/kinetics, or structural alterations induced by post-translational modifications, crystal contacts, and small-molecule ligands not included in the inputs.

---

## [183] source=multitask_sft_big

**USER:** I have an AnnData object with raw UMI counts from a 10x Genomics 3' scRNA-seq run of human PBMCs. Could you classify and label the cell types across all single cells using a pretrained foundation model?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer) fine-tuned for cell-type classification: Can reliably identify known, canonical cell lineages and discrete cell types across varying sequencing platforms, accounting for cross-batch technical noise. Cannot identify entirely novel or disease-specific transitional states not present in the reference vocabulary, infer functional protein-level activity from transcript counts alone, or resolve ultra-fine subclusters with subtle transcriptional gradients.

---

## [184] source=multitask_sft_big

**USER:** I have the primary amino acid sequence of a novel bacterial transport protein: 'MKTLLILAVSVAFAGNA...'. Could you predict its full tertiary 3D structure, identify the transmembrane alpha-helices, and provide a PDB file containing the predicted coordinates with per-residue confidence scores?

**ASSISTANT:** Evoformer/End-to-End Protein Structure Prediction Transformer (e.g., AlphaFold2, ESMFold): Can determine high-accuracy static 3D coordinates (backbone and side-chain geometry), domain topology, relative residue proximity, and local prediction confidence metrics (pLDDT, PAE). Cannot predict real-time folding kinetics, thermodynamic pathways, multi-state dynamic transitions without sampling, exact binding affinities for non-covalent ligands, or environmental impacts such as specific pH/membrane lipid compositions.

---

## [185] source=multitask_sft_big

**USER:** I have isolated a novel bacterial esterase with the following sequence: 'MNKPQQTLTVTGLFA...LKGE'. Could you predict its 3D tertiary structure, generate the atomic coordinates in PDB format, and provide residue-level confidence metrics (pLDDT) to see if the active site is well-resolved?

**ASSISTANT:** AlphaFold2 (or ESMFold): Can accurately predict static single-state backbone and side-chain 3D Cartesian coordinates from primary sequence and output confidence measures (pLDDT, PAE). Cannot reliably model conformational dynamics/pathways, effects of post-translational modifications (PTMs), crystal-packing artifacts, solvent/temperature-dependent folding kinetics, or non-covalent binding of arbitrary small-molecule ligands/ions (without specialized multimolecular extensions).

---

## [186] source=multitask_sft_big

**USER:** I have the amino acid sequence of an uncharacterized orphan enzyme from a marine metagenome: 'MKTAYIAKQRQISFVKSHFSRQLEERLGLIEVQAP...'. Can you predict its 3D atomic coordinates, generate a PDB file, and provide per-residue confidence scores for the folding quality?

**ASSISTANT:** AlphaFold2 / ESMFold (Equivariant Transformer / Evoformer-based protein structure prediction model): Can speak to: High-accuracy static 3D backbone and side-chain Cartesian coordinates, secondary/tertiary folding topology, and confidence estimates (pLDDT and PAE matrices) for structural reliability. Cannot speak to: Real-time conformational dynamics/thermodynamics, binding energetics (e.g., Kd, ΔG), post-translational modifications (PTMs), or non-covalent interactions with novel cofactors, ions, and small-molecule substrates without specialized docking downstream.

---

## [187] source=multitask_sft_big

**USER:** Here is the amino acid sequence of a novel uncharacterized bacterial esterase: 'MKTIIALSYIFCLVFA...LKA'. Can you predict its full 3D tertiary structure, generate the PDB coordinate file, and highlight the confidence metrics for the predicted catalytic active site?

**ASSISTANT:** AlphaFold2 (or ESMFold / Evoformer-based protein folding architectures): Can reliably predict static 3D atomic coordinates (PDB/mmCIF) for well-aligned globular domains and provide residue-level confidence estimates (pLDDT, PAE). Cannot reliably model conformational dynamics/transitions, post-translational modifications (PTMs), folding pathways, non-covalent ligand/ion interactions (standard AF2), or predict the exact destabilizing effects of single-point missense mutations.

---

## [188] source=multitask_sft_big

**USER:** I have an uncharacterized bacterial esterase sequence (342 amino acids: 'MNK...VLA'). Can you generate the predicted 3D Cartesian coordinates in PDB format and output the per-residue pLDDT confidence scores to assess the folding of the active-site pocket?

**ASSISTANT:** Protein Structure Prediction Network (e.g., AlphaFold2 / ESMFold): Can reliably predict static, ground-state 3D all-atom coordinates, overall fold topology, domain boundaries, and local confidence metrics (pLDDT/PAE). Cannot accurately simulate thermodynamic conformational dynamics, explicit-solvent free energy landscapes, kinetic rates, the precise structural destabilization caused by rare single-point missense mutations, or binding-induced conformational changes without the ligand co-present in the model framework.

---

## [189] source=multitask_sft_big

**USER:** We identified a novel de novo missense variant in the SCN1A gene (c.3812C>T, p.Ala1271Val) in an infant presenting with early-onset focal seizures. Can you predict the pathogenicity score for this variant and tell us if it is likely disease-causing?

**ASSISTANT:** Supervised structural-evolutionary missense pathogenicity predictor (e.g., AlphaMissense) or protein language model fine-tuned for variant effect (e.g., ESM-1v): Can speak to: The likelihood that a single amino acid substitution disrupts protein structure and function based on evolutionary conservation and structural biology constraints. Cannot speak to: The clinical penetrance, age of onset, specific disease phenotype (e.g., Dravet syndrome vs. GEFS+), patient-specific genetic background modifiers, or non-missense variants (e.g., splice-site, frameshift, or non-coding regulatory mutations).

---

## [190] source=multitask_sft_big

**USER:** I have an uncharacterized 280-amino-acid sequence from an environmental isolate (starts with 'MVLSEGEWQL...'). Can you predict its 3D atomic coordinates, identify probable folding domains, and give me per-residue confidence scores for the predicted conformation?

**ASSISTANT:** AlphaFold2 (DeepMind): Can accurately predict static, monomeric 3D tertiary structures, domain topologies, and confidence metrics (pLDDT, PAE). Cannot predict real-time conformational dynamics/transitions, thermodynamic stability differences (ddG) from single-point mutations, or coordinates involving unmodeled small-molecule ligands, cofactors, and post-translational modifications.

---

## [191] source=multitask_sft_big

**USER:** I have a CSV file containing SMILES strings for 150 novel small-molecule kinase inhibitors from our lead optimization series. Could you predict their intrinsic aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) to help filter out candidates with poor bioavailability before in vitro testing?

**ASSISTANT:** Message-Passing Graph Neural Network (e.g., Chemprop / D-MPNN) or Molecular Language Model (e.g., ChemBERTa) fine-tuned on curated ADMET datasets (such as Therapeutics Data Commons or ChEMBL): Can accurately estimate thermodynamic logS and physiological logD7.4 trends across small, neutral, or typical organic drug-like scaffolds within the model's chemical domain; cannot account for formulation factors (e.g., crystal polymorphism, amorphous states, salt forms), kinetics of dissolution, dynamic pH/pKa shifts outside standard physiological conditions, or highly atypical chemistries such as large macrocycles, metal complexes, and polymers.

---

## [192] source=multitask_sft_big

**USER:** I have a batch of 150 novel kinase inhibitor analogs represented as SMILES strings. Can you predict their intrinsic aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) to help us prioritize candidates with favorable oral absorption profiles?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Directed Message Passing Neural Network (e.g., Chemprop D-MPNN fine-tuned on ADMET benchmarks): Can speak to: In silico estimates of equilibrium solubility, physiological lipophilicity (logD7.4), structural property-activity trends, and relative lead compound prioritization based on molecular graph topology. Cannot speak to: Solid-state crystal packing effects, salt/polymorph stability, formulation or surfactant impact on kinetic solubility, experimental protocol discrepancies, or dynamic pH changes along the gastrointestinal tract.

---

## [193] source=multitask_sft_big

**USER:** We identified a novel de novo missense substitution in MYH7 (p.Arg719Trp) from whole-exome sequencing of a pediatric patient with suspected cardiomyopathy. Can you run an in silico analysis to predict whether this specific variant is pathogenic, identify the structural disruption it causes, and recommend whether this justifies starting preventative medical therapy?

**ASSISTANT:** Protein Language Model / Structure-Aware Variant Effect Predictor (e.g., AlphaMissense, ESM-1v): Can predict the statistical likelihood that a specific missense variant is deleterious vs. benign based on evolutionary sequence conservation and structural context, providing calibrated pathogenicity scores. Cannot provide a definitive clinical diagnosis, predict variable penetrance or disease severity in an individual, assess non-missense alterations (such as indels, synonymous, or non-coding regulatory variants), or provide clinical decision-making/therapeutic guidance.

---

## [194] source=multitask_sft_big

**USER:** I have an unannotated scRNA-seq count matrix from a human PBMC sample generated with 10x Genomics (around 12,000 cells). Could you run a pretrained foundation model to predict and annotate the cell types present in this dataset?

**ASSISTANT:** Transformer-based single-cell foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type classification): Can reliably predict discrete canonical cell types and broad lineages present in its reference training data, leverage zero-shot or few-shot transfer learning, and handle high-dimensional drop-out noise. Cannot infer spatial tissue context, definitively resolve novel/rare cell sub-states absent from training references, infer post-transcriptional protein abundance, or correct for experimental artifacts like unresolved doublets.

---

## [195] source=multitask_sft_big

**USER:** We have synthesized a library of 35 lead-like small molecules as potential LRRK2 inhibitors for Parkinson's disease. Could you run an in silico ADMET screen on their SMILES strings to predict potential hERG-mediated cardiotoxicity, CYP450 inhibition profiles (specifically CYP3A4 and CYP2D6), and predicted human oral bioavailability (F%)?

**ASSISTANT:** Multitask Graph Neural Network / Message Passing Framework for ADMET (e.g., Chemprop / ADMET-AI trained on Therapeutics Data Commons benchmarks): Can reliably predict binary classification labels and relative quantitative risk rankings for hERG potassium channel blockade, major CYP450 isoform inhibition/substrate status, and high-vs-low oral absorption for drug-like small molecules within the training applicability domain. Cannot accurately model complex whole-body physiologically based pharmacokinetics (PBPK), time-dependent metabolism/covalent inhibition, formulation or food-effect impacts on bioavailability, or generalize well to 'beyond-Rule-of-5' chemical space (e.g., large macrocycles, PROTACs, or inorganic conjugates).

---

## [196] source=multitask_sft_big

**USER:** I have a library of 150 novel small molecule lead candidates represented as SMILES strings. Can you predict their aqueous kinetic solubility (logS) and lipophilicity/membrane partitioning at physiological pH (logD7.4) to help us prioritize compounds with good oral bioavailability for our upcoming in vitro screen?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., Chemprop / D-MPNN) or Molecular Transformer (e.g., ChemBERTa) fine-tuned on curated small-molecule ADMET benchmarks (such as TDC or MoleculeNet).: Can speak to: In silico estimates of intrinsic aqueous solubility (logS) and distribution coefficients (logD at pH 7.4) based on 2D molecular graph topology and functional group electronics across drug-like small-molecule chemical space. Can't speak to: Polymorphic crystal lattice energy, formulation/excipient effects, buffer counterion interactions, kinetic precipitation over time, or non-traditional modalities such as large macrocycles, peptide conjugates, and organometallics that lie outside the training distribution.

---

## [197] source=multitask_sft_big

**USER:** We identified several novel de novo missense variants in the SCN1A and KCNQ2 genes from pediatric epilepsy whole-exome sequencing data. Can you predict which of these amino acid substitutions are likely pathogenic versus benign so we can prioritize them for functional patch-clamp assays?

**ASSISTANT:** Protein Language Model / Deep Learning Structural Variant Effect Predictor (e.g., AlphaMissense, ESM-1v): Can speak to: The functional and structural disruption caused by single-residue missense mutations, evolutionary conservation of the wild-type residue, and the relative probability of a protein-altering mutation being pathogenic. Cannot speak to: Non-coding or regulatory variants, synonomous changes, complex structural variants/indels, tissue-specific penetrance, or definitive clinical diagnosis under ACMG/AMP guidelines without orthogonal patient and functional evidence.

---

## [198] source=multitask_sft_big

**USER:** We have 15 optimized lead candidates for our oncological target (provided as SMILES). Can you run in silico profiling to predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) so we can filter out compounds likely to have poor oral bioavailability?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Foundation Model (e.g., Chemprop D-MPNN, Uni-Mol, or ChemBERTa fine-tuned on physicochemical benchmark datasets): Can reliably predict intrinsic lipophilicity (logD at pH 7.4) and thermodynamic/kinetic aqueous solubility (logS) for drug-like small molecules based on 2D topology and 3D conformations. Cannot account for solid-state polymorphism, counterion/salt-form effects, formulation excipients, temperature variations, or kinetic precipitation behavior under non-standard assay buffer conditions.

---

## [199] source=multitask_sft_big

**USER:** We identified three novel missense mutations in the SCN5A gene (p.Arg1623Gln, p.Val411Met, and p.Leu1825Pro) from whole-exome sequencing of a patient presenting with cardiac arrhythmia. Can you predict the pathogenic potential of these specific amino acid substitutions and score their likelihood of causing functional disruption?

**ASSISTANT:** Structure-informed protein language model for variant effect prediction (e.g., AlphaMissense): Can speak to: The relative probability of missense variants being benign vs. pathogenic based on structural context and evolutionary conservation, highlighting positions critical to protein stability or functional domains. Cannot speak to: Pathogenicity of non-coding or complex structural variants (indels, frameshifts), complete clinical certainty or patient-specific penetrance, complex gene-environment interactions, or the exact molecular mechanism (e.g., gain-of-function vs. loss-of-function) without functional assay validation.

---

## [200] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the TP53 DNA-binding domain (c.818G>A, p.Arg273His) in a patient with suspected Li-Fraumeni syndrome. Could you use a computational model to predict whether this specific amino acid substitution is pathogenic or benign?

**ASSISTANT:** Deep learning-based missense variant effect predictor (e.g., AlphaMissense, ESM-1v): Can speak to: The likelihood that a specific missense single-nucleotide variant disrupts protein function or stability based on structural constraints and evolutionary conservation. Can't speak to: Non-coding or synonymous variants, large indels/structural variants, gene-specific disease penetrance, regulatory/splicing disruption, or definitive clinical diagnosis according to ACMG/AMP guidelines without orthogonal functional and clinical evidence.

---

## [201] source=multitask_sft_big

**USER:** I have the amino acid sequence of a newly isolated bacterial metalloprotease: 'MKTIIALSYIFCLVFA...'. Can you predict its full tertiary 3D atomic coordinates and provide the structure in standard PDB format along with confidence metrics?

**ASSISTANT:** AlphaFold2 (Evoformer-based Protein Structure Predictor): Can reliably predict: static 3D backbone and side-chain atomic coordinates, domain boundaries, and local confidence scores (pLDDT, PAE). Cannot speak to: functional conformational dynamics in solution, folding kinetics/pathways, precise structural consequences of unmodeled post-translational modifications, or binding affinities without explicit co-folding of ligands/cofactors.

---

## [202] source=multitask_sft_big

**USER:** We have synthesized a set of 15 optimized lead SMILES for our oncology program. Could you predict their ADMET profiles, specifically focusing on hERG inhibition risk (cardiotoxicity), CYP3A4 inhibition potential, and human oral bioavailability (%F), so we can prioritize the best candidates for upcoming in vitro assays?

**ASSISTANT:** Multitask Directed Message Passing Neural Network (D-MPNN / Chemprop) fine-tuned on ADMET benchmarks (such as Therapeutics Data Commons and ChEMBL): Can speak to: Structure-based classification of hERG-mediated cardiotoxicity risk, categorical or semi-quantitative liability for key CYP450 enzyme inhibition, and preliminary ranking of oral bioavailability potential derived from 2D molecular graphs. Cannot speak to: Complex in vivo pharmacokinetics (e.g., clearance curves, Cmax, AUC, organ-specific accumulation), dosage and formulation effects, species-dependent physiological interactions, or polypharmacological toxicity arising from active downstream metabolites.

---

## [203] source=multitask_sft_big

**USER:** I have a lead series of 20 novel heterocycles targeting an oncology pathway (provided as SMILES strings). Could you predict their ADMET profiles, specifically cardiac liability via hERG inhibition, CYP450 isoform inhibition (specifically CYP3A4, CYP2D6, and CYP2C9), and categorical oral bioavailability (%F > 30%) to help us prioritize candidates for in vitro assay validation?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network (e.g., Directed Message Passing Neural Network / Chemprop fine-tuned on curated ADMET datasets like TDC or ChEMBL): It can estimate relative in silico probabilities and binary risk classifications for hERG blockade, major CYP inhibition liabilities, and low vs. high oral bioavailability for drug-like small molecules within the training applicability domain. It cannot predict absolute in vivo pharmacokinetic profiles (e.g., Cmax, AUC, organ distribution), formulation- or food-dependent bioavailability effects, non-CYP metabolism, or stereospecific pharmacokinetics if input molecules lack defined 3D stereocenters.

---

## [204] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix (10x Genomics h5ad file) containing around 25,000 cells from human lung tissue. Could you run a model to automatically identify and assign cell-type labels to each cell cluster without requiring me to manually search for marker genes?

**ASSISTANT:** Pretrained single-cell foundation transformer (e.g., scGPT, Geneformer) fine-tuned for cell-type classification: {'can': ['Assign granular or canonical cell-type identities based on high-dimensional gene expression embeddings.', 'Transfer annotations across diverse sequencing platforms, batches, and donor variations.', 'Identify known cell states and transitionary lineages represented in comprehensive reference atlases.'], 'cant': ['Confidently classify novel, rare, or disease-specific cell types absent from the pretraining/reference corpora without producing overconfident misclassifications.', 'Disentangle biological phenotype from severe technical artifacts like ambient RNA contamination, uncorrected doublets, or extreme dropout.', 'Determine functional protein abundance, post-translational states, or spatial architecture purely from dissociated scRNA expression.']}

---

## [205] source=multitask_sft_big

**USER:** I have an uncharacterized 420-amino acid sequence from an extremophile bacterium. Can you predict its 3D tertiary structure, including side-chain conformations, and output the atomic coordinates in PDB format along with per-residue confidence scores?

**ASSISTANT:** Evoformer-based Protein Structure Prediction Model (e.g., AlphaFold2, ESMFold): Can predict static, ground-state Cartesian coordinates (backbone and side-chain 3D positions) and assign local and global confidence scores (pLDDT and PAE). Cannot speak to real-time conformational dynamics, kinetic folding pathways, thermodynamic free energy, or structural alterations caused by unmodeled post-translational modifications, ions, or small-molecule ligands.

---

## [206] source=multitask_sft_big

**USER:** I need to estimate the aqueous solubility (logS) and lipophilicity (logD at physiological pH 7.4) for this newly designed lead candidate: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5. Can you run a property prediction on this SMILES string?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop fine-tuned on ADMET/MoleculeNet benchmarks): Can accurately predict continuous physicochemical values (logS, logD) directly from 2D molecular graphs and rank compound series within standard drug-like chemical space. Cannot account for experimental condition shifts (e.g., specific counterions, co-solvents, temperature variations, ionic strength), solid-state crystalline polymorphism impacting actual dissolution kinetics, or molecules far outside the model's training applicability domain.

---

## [207] source=multitask_sft_big

**USER:** We identified a novel de novo missense variant, p.Gly418Arg (c.1252G>A), in the SCN1A gene of an infant presenting with early-onset treatment-resistant seizures. Can you evaluate the predicted pathogenicity of this substitution and report whether it is likely benign or damaging to channel function?

**ASSISTANT:** AlphaMissense (structural context-aware pretrained protein language model): Can speak to: The relative probability that a specific missense substitution is structurally and evolutionary disruptive (classified as benign, ambiguous, or pathogenic) using protein structural biology and evolutionary conservation. Cannot speak to: Non-coding variants, indels, or complex structural rearrangements; regulatory or splice-site alterations; variant penetrance; patient-specific phenotype severity; or provide a definitive clinical diagnosis independent of ACMG/AMP guideline-based curation.

---

## [208] source=multitask_sft_big

**USER:** I have a library of 150 small-molecule SMILES strings from our lead optimization campaign against CDK4. Can you run predictions for their intrinsic aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) so we can filter out compounds with poor oral bioavailability profiles?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Transformer fine-tuned on ADMET data (e.g., Chemprop / ChemBERTa-2 / Uni-Mol): {'can': ['Predict equilibrium physicochemical ADMET properties (logS, logP, logD at standard pH 7.4) directly from 2D topological structures or 3D conformations of drug-like small molecules.', 'Identify structural motifs contributing positively or negatively to lipophilicity and solubility within the learned chemical space.'], 'cant': ['Account for experimental solid-state variables such as crystal polymorphism, amorphous states, or formulation excipients that heavily alter actual kinetic solubility.', "Reliably predict values for organometallics, very large macrocycles, or chemical scaffolds significantly outside the model's training applicability domain."]}

---

## [209] source=multitask_sft_big

**USER:** We have designed a series of 25 novel small-molecule CDK4/6 inhibitor analogs (provided as SMILES). Can you screen these candidates to predict their ADMET profiles, specifically flagging any potential hERG cardiotoxicity risk, CYP450 inhibition across major isoforms (CYP3A4, CYP2D6), and estimating human oral bioavailability?

**ASSISTANT:** Multi-Task Graph Neural Network / Pretrained Molecular Transformer (e.g., Chemprop or Uni-Mol fine-tuned on Therapeutics Data Commons [TDC] ADMET benchmarks): Can reliably predict in silico risk scores and binary classifications for standard in vitro assays (such as hERG potassium channel inhibition and CYP enzyme inhibition) and surrogate physicochemical-based bioavailability trends within its chemical applicability domain. Cannot account for complex in vivo pharmacokinetics, formulation effects, food-effect variations, species-specific transporter interactions (e.g., unmodeled P-glycoprotein efflux), or non-CYP mediated clearance pathways.

---

## [210] source=multitask_sft_big

**USER:** I have an uncharacterized 340-residue sequence from a marine metagenomic sample (FASTA: 'MAQSL...'). Could you predict its 3D atomic coordinates, output a PDB file, and provide per-residue confidence scores so we can identify potential catalytic binding pockets?

**ASSISTANT:** Transformer-based Invariant Point Attention (IPA) Structure Predictor (e.g., AlphaFold2, ESMFold, OpenFold): Can accurately predict static ground-state tertiary/quaternary coordinates, domain arrangements, and relative confidence metrics (pLDDT, PAE). Cannot predict folding pathways/kinetics, thermodynamic conformational ensembles under varying physiological conditions, explicit effects of unseen post-translational modifications, or quantitative binding free energies.

---

## [211] source=multitask_sft_big

**USER:** I have isolated a novel 320-residue putative esterase from an extremophile metagenomic screen: 'MKTLLILALLSCL...'. Can you predict its 3D tertiary structure, determine active-site geometry, and output the atomic coordinates in PDB format with local confidence scores?

**ASSISTANT:** AlphaFold2 / ESMFold (Evoformer- or Protein Language Model-based Structure Prediction Architectures): Can reliably predict static equilibrium tertiary and quaternary coordinates of structured domains and provide per-residue confidence (pLDDT) and inter-domain alignment error (PAE). Cannot accurately resolve full conformational ensembles/dynamics, functional kinetics, intrinsic disorder states, structural consequences of single point mutations, or non-covalent binding of small-molecule ligands and cofactors unless explicitly trained or paired with all-atom multimodal architectures like AlphaFold 3.

---

## [212] source=multitask_sft_big

**USER:** We have synthesized a batch of 20 lead optimization analogs for an oncology target. Could you screen these SMILES strings for key ADMET liabilities—specifically hERG potassium channel inhibition (IC50 < 10 µM), CYP3A4 inhibition, and rodent oral bioavailability (>30% F)—to prioritize five compounds for our upcoming in vivo pharmacokinetic study?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmark datasets: Can speak to: Rapid in silico classification of 2D molecular topology risks, rank-ordering candidates by relative probability of hERG cardiotoxicity, CYP isoform interaction, and broad categorical oral bioavailability based on historical small-molecule SAR. Can't speak to: Dynamic multi-compartment in vivo pharmacokinetics (e.g., exact clearance, Cmax, half-life), formulation- or dissolution-limited bioavailability, dose-dependent metabolic saturation, complex metabolite safety profiles, or stereospecific effects if 3D conformer/chiral information is unrepresented.

---

## [213] source=multitask_sft_big

**USER:** I have an AnnData object containing normalized scRNA-seq count matrices from a human PBMC sample processed on 10x Chromium. Can you predict and assign cell-type labels to each cell in the dataset using its gene expression profile?

**ASSISTANT:** Single-cell foundation transformer models (e.g., scGPT, Geneformer, scBERT): Can reliably predict established cell types, classify fine-grained immune subsets, and transfer labels across datasets by leveraging contextual gene-gene interactions while mitigating batch effects. Cannot accurately identify completely novel or undocumented cell types outside its reference taxonomy, infer spatial localization or non-transcriptomic states (such as post-translational protein abundance), or reliably distinguish biology from technical artifacts like ambient RNA contamination and unresolved doublets.

---

## [214] source=multitask_sft_big

**USER:** I have a 320-amino-acid sequence of an uncharacterized orphan enzyme from a marine metagenome (sequence: MVLSEGEWQLVLHVWAKVEADVAGHGQDILIRLFKSHPETLEKFDRFKHLKTEAEMKASEDLKKHGVTVLTALGAILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSRHPGDFGADAQGAMNKALELFRKDIAAKYKELGYQG...). Can you generate the predicted 3D coordinates in PDB format, show the domain architecture, and provide per-residue confidence scores?

**ASSISTANT:** AlphaFold2 / ESMFold (Deep Learning-based Protein Structure Prediction Models): Can accurately predict static single-state tertiary (and multimeric) 3D atomic coordinates, secondary structure elements, and domain boundaries, while outputting reliable per-residue confidence (pLDDT) and pairwise alignment errors (PAE). Cannot dynamically model full conformational flexibility or folding pathways, account for non-covalent ligand/cofactor binding interactions (unless modeled with specialized variants like AlphaFold3), or predict the exact effects of physical environmental conditions such as pH, ionic strength, or temperature.

---

## [215] source=multitask_sft_big

**USER:** I have an uncharacterized 280-amino-acid sequence of an enzyme isolated from a thermophilic bacterium (FASTA format below). Could you predict its 3D tertiary structure, generate the atomic PDB coordinates, and report the local per-residue confidence metrics?

**ASSISTANT:** AlphaFold2 (Evoformer-based Protein Structure Prediction Model): Can reliably predict static 3D backbone and sidechain atomic coordinates, secondary/tertiary folding topology, and per-residue confidence scores (pLDDT/PAE). Cannot accurately model real-time conformational dynamics, folding kinetics, interactions with small-molecule ligands/cofactors, or structural alterations driven by pH, temperature, or solvent conditions.

---

## [216] source=multitask_sft_big

**USER:** I have designed a batch of small-molecule kinase inhibitors. Could you predict their intrinsic aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) using their SMILES strings to help prioritize leads for synthesis?

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN / Chemprop) fine-tuned on ADMET molecular property benchmarks: Can reliably predict relative trends in thermodynamic/kinetic aqueous solubility and distribution coefficients (logD at fixed pH 7.4) across drug-like 2D chemical space learned from datasets like ChEMBL and TDC. Cannot account for experimental variables like polymorphic crystal packing, temperature/ionic strength shifts, specific salt forms, dissolution kinetics, or molecules with metallo-organic centers or novel scaffolds far outside the training distribution.

---

## [217] source=multitask_sft_big

**USER:** Here is a list of 12 novel small-molecule SMILES candidates from our lead optimization campaign. Could you run an in silico ADMET profiling to predict hERG cardiotoxicity risk (IC50 or liability flag), inhibition potential across the primary CYP isozymes (CYP3A4, CYP2D6, CYP2C9), and estimate human oral bioavailability (percentage or high/low binary classification)?

**ASSISTANT:** Multi-Task Graph Neural Network / Message Passing Neural Network (MPNN) pretrained on ADMET benchmarks (e.g., Chemprop or ADMET-AI trained on Therapeutics Data Commons datasets): Can speak to: Rapid in silico screening of static 2D/3D chemical structures for probability of hERG inhibition, substrate/inhibition flags for key cytochrome P450 enzymes, and empirical estimates of fraction absorbed/bioavailability based on historical in vitro and preclinical assay data within its chemical training distribution. Can't speak to: Dynamic, time-dependent in vivo pharmacokinetic parameters (e.g., full concentration-time curves, dose-dependent non-linear clearance), formulation-dependent absorption (e.g., salt form, excipients, food effects), gut-wall metabolism, covalent/mechanism-based inactivation, or idiosyncratic in vivo toxicities.

---

## [218] source=multitask_sft_big

**USER:** I have the PDB structure for the active site of human EGFR (T790M mutant) and SMILES strings for five candidate small-molecule inhibitors. Can you predict their binding affinity (Kd or pIC50) against this pocket and rank which compound is likely to bind the tightest?

**ASSISTANT:** 3D Structure-Based Graph Neural Network / Equivariant GNN (e.g., TankBind, EquiBind) or 3D-CNN (e.g., GNINA) pretrained on PDBbind complexes: Can speak to: Relative binding ranking, estimated standard binding free energy (delta G / pKd / pKi) based on spatial and electrostatic complementarity in rigid or semi-flexible docking pockets. Cannot speak to: Absolute in vivo or cell-based IC50/EC50 values (which depend on membrane permeability, metabolism, and off-target binding), kinetic rate constants (kon/koff residence time), water-mediated entropic contributions without explicit solvent modeling, or major induced-fit conformational changes not captured in the input crystal structure.

---

## [219] source=multitask_sft_big

**USER:** I have a library of 25 novel drug candidates docked into the catalytic pocket of SARS-CoV-2 Mpro (PDB: 6LU7). Could you predict their binding affinities (pKd or delta G) so we can prioritize the top 5 for in vitro synthesis and enzyme inhibition assays?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, or GNINA-style CNN/GNN hybrid scoring function): It can reliably score and rank relative binding affinities based on 3D spatial geometry, steric complementarity, and non-covalent interactions (e.g., hydrogen bonding, hydrophobic contacts) within rigid or semi-rigid protein-ligand complexes. It cannot speak to true binding kinetics (kon/koff rates), solvent thermodynamics/entropy changes from water displacement, induced-fit conformational changes, or broader pharmacokinetics (ADMET, cytotoxicity, off-target selectivity).

---

## [220] source=multitask_sft_big

**USER:** I have an unannotated 10x Genomics single-cell RNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs). Can you use a pretrained model to predict the cell-type identity for each individual cell in this dataset?

**ASSISTANT:** scGPT (fine-tuned for cell-type annotation) or Geneformer: Can speak to: assigning high-probability cell-type and lineage labels for known, annotated cell states present in the reference pretraining atlas; robustly mapping identity despite moderate sequencing depth variations and batch effects. Cannot speak to: identifying entirely novel, rare, or aberrant pathological cell states not represented in reference data; inferring spatial context, tissue microenvironment architecture, or actual surface protein abundance without multimodal (e.g., CITE-seq) validation.

---

## [221] source=multitask_sft_big

**USER:** Here is a batch of 10 lead optimization candidates in SMILES format. Could you evaluate their ADMET profiles—specifically predicting hERG cardiac toxicity potential, inhibition against key CYP isoforms (CYP3A4, CYP2D6, CYP2C9), and predicted human oral bioavailability?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network (e.g., Chemprop D-MPNN or ADMETlab multi-task architecture): Can speak to: Fast in silico screening for binary/semi-quantitative endpoints, including hERG channel blocking risk, CYP450 substrate/inhibitor classification, and high vs. low oral bioavailability likelihood based on 2D chemical structure. Cannot speak to: Time-dependent pharmacokinetics (Cmax, Tmax, clearance profiles) requiring PBPK simulations, reactive metabolite formation, specific drug-drug interaction mechanisms, or properties of compounds far outside the model's chemical training domain (e.g., organometallics, large macrocycles).

---

## [222] source=multitask_sft_big

**USER:** I have identified a novel candidate enzyme from a marine metagenomics screen with the amino acid sequence: 'MEEVVLI...'. Can you generate its predicted 3D atomic coordinates in PDB format so we can locate potential active site pockets?

**ASSISTANT:** Deep learning protein structure prediction models (e.g., AlphaFold2, ESMFold): Can: Predict high-accuracy static 3D coordinates (backbone and side chains) from primary sequence, identify tertiary/quaternary folding domains, and provide per-residue confidence metrics (pLDDT) and pairwise alignment errors (PAE). Can't: Model conformational dynamics or transition states, quantitatively calculate ligand-binding affinities (Kd/delta G), accurately predict full folding pathways, or resolve structures reliant on unmodeled non-covalent cofactors, metal ions, or post-translational modifications (unless using generalized multimers like AlphaFold 3).

---

## [223] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix from a human PBMC sample processed on 10x Genomics (v3 chemistry). Can you automatically classify and assign the discrete cell type (e.g., CD4+ naive T cells, classical monocytes, NK cells) for each individual cell barcode?

**ASSISTANT:** Pretrained Single-Cell Foundation Transformer (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): {'can_speak_to': ['Assigning cell identity labels based on co-expression patterns and marker gene distributions across standard cell ontologies', 'Handling dropout and technical noise via contextual gene embeddings learned during large-scale pretraining', 'Transferring labels across compatible sequencing platforms and tissues with modest batch variation'], 'cant_speak_to': ['Identifying completely novel, previously uncharacterized cell states or lineage intermediates absent from the reference/training distribution', 'Spatial organization, microenvironment niche interactions, or physical cell morphology', 'Protein-level surface marker abundance (e.g., CITE-seq discrepancies where RNA expression diverges from surface protein expression)', 'Mechanistic or causal drivers of the observed transcriptional states']}

---

## [224] source=multitask_sft_big

**USER:** I have the co-crystal structure of human CDK2 (PDB: 1HCL) and a set of 150 docked pyrazole-based small molecules. Can you predict the binding affinity (pKd or pKi values) for each ligand in this binding pocket to help prioritize candidates for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Protein-Ligand Scoring (e.g., TankBind, EquiBind, Uni-Mol): Can predict relative ranking and empirical binding free energies (pKd/pKi/delta-G) based on rigid or semi-flexible 3D complex poses and learned geometric contact patterns. Cannot reliably account for extensive induced-fit conformational changes, solvent entropy without explicit sampling, covalent binding mechanisms, downstream functional efficacy (e.g., agonism vs. antagonism), or in vivo pharmacokinetic properties.

---

## [225] source=multitask_sft_big

**USER:** I have an AnnData h5ad file containing raw single-cell RNA-seq count matrices from human peripheral blood mononuclear cells (PBMCs). Can you predict and assign cell-type labels to each individual cell in this dataset?

**ASSISTANT:** scGPT (single-cell Generative Pretrained Transformer) / Geneformer: Can speak to: Zero-shot or fine-tuned cell type annotation, mapping cells to known reference cell ontologies, identifying distinguishing marker gene signatures, and embedding cellular states in a low-dimensional manifold. Can't speak to: Absolute functional in vivo phenotype (transcript levels do not strictly correlate to protein abundance), spatial tissue architecture/microenvironment context, non-transcriptomic regulatory mechanisms (e.g., epigenetics/chromatin accessibility), or reliable identification of ultra-rare or entirely novel cell types absent from the pretraining/reference corpora.

---

## [226] source=multitask_sft_big

**USER:** We have synthesized a series of 15 kinase inhibitor analogs (provided as SMILES) and need to prioritize them for in vitro assays. Can you profile their ADMET liabilities, specifically evaluating risk of hERG potassium channel inhibition (cardiotoxicity), inhibition across primary CYP450 isoforms (CYP3A4, CYP2D6, CYP2C9), and predicted human oral bioavailability?

**ASSISTANT:** Multi-Task Graph Neural Network / Directed Message Passing Neural Network (e.g., Chemprop / ADMET-AI trained on TDC benchmarks): Can rapidly score and rank drug-like small molecules for in vitro risk probabilities (hERG blockade, CYP enzyme inhibition) and estimate qualitative oral bioavailability categories based on molecular graph topology. Cannot model precise in vivo pharmacokinetic dynamics (e.g., clearance rates, Cmax, AUC), formulation/food effects, transporter-mediated active efflux, dose-dependent non-linearities, or stereospecific interactions unless explicit 3D conformations and physiological PBPK parameters are incorporated.

---

## [227] source=multitask_sft_big

**USER:** I have an AnnData matrix of normalized single-cell RNA-seq expression profiles from human peripheral blood mononuclear cells (PBMCs). Can you run an automated annotation pipeline to predict and label the specific cell types (e.g., distinguishing CD4+ naive, memory, and CD8+ T-cell subsets) for each cell?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer): Can accurately assign established cell-type labels, capture complex non-linear gene-gene regulatory dependencies, and generalize across different sequencing batches and protocols. Cannot infer spatial tissue organization, directly quantify actual surface protein abundance (unless paired with multimodal CITE-seq data), or reliably detect novel, uncharacterized pathological cell states that deviate entirely from its reference pretraining atlas.

---

## [228] source=multitask_sft_big

**USER:** I have a lead small molecule with the SMILES string 'CC1=C(C(=O)N2CCCC2=N1)C3=CC=C(C=C3)F'. Could you predict its aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) to help us assess its oral bioavailability profile?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Transformer (e.g., Chemprop D-MPNN, Uni-Mol, or ChemBERTa fine-tuned on ADMET datasets): Can speak to: Intrinsic thermodynamic solubility (logS) and distribution coefficients (logD7.4) derived from 2D topological or 3D conformer representations within the model's chemical space domain. Cannot speak to: Solid-state crystal lattice energies (polymorph-dependent solubility), kinetic dissolution rates, formulation/excipient effects, or complex dynamic in vivo physiological compartmental absorption.

---

## [229] source=multitask_sft_big

**USER:** I have a series of 50 novel small-molecule kinase inhibitor candidates as SMILES strings. Can you predict their aqueous solubility (LogS at neutral pH) and lipophilicity/membrane permeability profile (LogD at physiological pH 7.4) to help us prioritize which analogues to advance to in vitro ADME assays?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) / Chemprop (optionally pretrained on ChEMBL or MoleculeNet benchmark sets): Can speak to: Fast in silico estimation of thermodynamic/kinetic aqueous solubility (LogS) and lipophilicity/distribution coefficients (LogP/LogD7.4) for drug-like organic small molecules represented by 2D chemical graphs, identifying structural property trends and high-risk insolubility outliers within the model's domain of applicability. Cannot speak to: Solid-state crystal lattice energy, polymorphism, or amorphous vs. crystalline behavior; pH-dependent solubility curves without explicit pKa/ionization modeling; the effects of specific formulation buffers, salts, counter-ions, or cosolvents; aggregation kinetics; or non-standard chemotypes (e.g., organometallics, macrocycles, polymers, and covalent peptide conjugates) underrepresented in the training data.

---

## [230] source=multitask_sft_big

**USER:** I have identified a novel heterozygous missense mutation (chr17:43045712 G>A, BRCA1 p.Cys61Tyr) in a patient with a strong family history of early-onset breast cancer. Could you predict whether this specific variant is likely pathogenic or benign?

**ASSISTANT:** Protein structure- and sequence-aware variant effect predictor (e.g., AlphaMissense, EVE, ESM-1v): Can speak to: in silico computational likelihood of pathogenicity, predicted disruption to protein structural stability, and evolutionary sequence conservation at the affected residue. Can't speak to: definitive clinical diagnoses (cannot substitute for full ACMG/AMP clinical variant classification), disease penetrance, patient-specific phenotype severity, epigenetic modifications, or non-coding/splicing consequences.

---

## [231] source=multitask_sft_big

**USER:** I have synthesized a series of 12 novel small-molecule kinase inhibitors as SMILES strings. Could you run an in silico ADMET screen to predict their cardiotoxicity risk (specifically hERG IC50 inhibition), major cytochrome P450 interactions (CYP3A4 and CYP2D6 inhibition), and estimated human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Message Passing Neural Network (MPNN) / Graph Convolutional Network for ADMET (e.g., Chemprop or ADMET-AI trained on Therapeutics Data Commons datasets): Can speak to: Fast, high-throughput estimation of binary liability risks (e.g., hERG blocker vs. non-blocker, CYP inhibition status) and empirical trend ranking of oral bioavailability based on molecular structure and physicochemical descriptors within the training set's chemical space. Cannot speak to: Definite clinical in vivo pharmacokinetic profiles, dynamic multi-organ clearance mechanisms, transporter-mediated active uptake/efflux saturation (e.g., P-gp/OATP interactions), species-specific physiological variability, or novel chemotypes that fall outside the model's training applicability domain.

---

## [232] source=multitask_sft_big

**USER:** I have a batch of 50 novel small-molecule kinase inhibitor candidates as SMILES strings. Can you predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD at pH 7.4) to help us prioritize leads for our upcoming in vitro ADME assays?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (Directed Message Passing Neural Network / D-MPNN, e.g., Chemprop): Can speak to quantitative aqueous solubility (logS) and lipophilicity/distribution coefficients (logP/logD) derived from molecular topology, functional groups, and 2D connectivity across drug-like chemical space. Cannot speak to solid-state crystalline polymorphism, precipitation kinetics, solvent-excipient interactions in specific formulations, temperature-dependent solubility shifts, or downstream pharmacokinetic behavior like in vivo bioavailability.

---

## [233] source=multitask_sft_big

**USER:** We have synthesized 12 novel small-molecule analogs for our oncology lead series (provided as SMILES). Can you run an ADMET screening to flag potential cardiotoxicity via hERG inhibition (pIC50), check for CYP3A4 and CYP2D6 inhibition liabilities, and predict human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop / ADMET-AI): Can: Rapidly screen chemical libraries to predict in vitro bioactivity flags (hERG blockage, major CYP isozyme inhibition) and statistical oral bioavailability classifications based on 2D topological molecular graphs and learned functional group representations. Cannot: Provide definitive in vivo human PK/PD profiles, model complex non-linear systemic factors (e.g., gut-wall metabolism, active influx/efflux transporters, formulation dependency), or reliably generalize to novel chemical scaffolds far outside its training distribution.

---

## [234] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense substitution in the MYH7 gene (c.1208G>A, p.Arg403Gln) in an adult patient presenting with unexplained hypertrophic cardiomyopathy. Could you run a prediction to evaluate the functional impact and pathogenicity likelihood of this variant?

**ASSISTANT:** AlphaMissense (Deep learning variant effect predictor combining structural models and evolutionary sequence representations): Can speak to: The likelihood that a specific missense single-nucleotide substitution is structurally disruptive or constrained by evolutionary selection, classifying it as likely benign, ambiguous, or likely pathogenic. Can't speak to: Non-coding variants, indels, splice-site effects outside the coding sequence, clinical penetrance, age of onset, gene-specific inheritance patterns, or serving as a standalone definitive diagnostic confirmation under ACMG/AMP clinical guidelines.

---

## [235] source=multitask_sft_big

**USER:** We are optimizing a series of small-molecule kinase inhibitors and need to prioritize candidates before synthesis. Here are 50 novel compounds formatted as SMILES. Can you predict their aqueous solubility (logS) and distribution coefficient (logD at pH 7.4) to help us flag potential ADME bottlenecks?

**ASSISTANT:** Pretrained Molecular Transformer / Graph Neural Network (e.g., ChemBERTa, MolFormer, or Chemprop DMPNN fine-tuned on ADME benchmark datasets): Can speak to: In silico estimates of thermodynamic aqueous solubility (logS), pH-dependent lipophilicity (logD) based on 2D chemical structure/topology, and relative ranking/flagging of drug-like small molecules within the model's chemical domain. Can't speak to: Dynamic physical phenomena such as solid-state polymorphism, kinetic vs. thermodynamic solubility discrepancies under experimental conditions, formulation/excipient effects, or definitive in vivo pharmacokinetics without wet-lab validation.

---

## [236] source=multitask_sft_big

**USER:** I have the 3D structure of the SARS-CoV-2 main protease (Mpro, PDB: 6LU7) and a panel of 25 novel small-molecule peptidomimetic inhibitors as SMILES. Could you predict the binding affinity (pKd or delta G) of each ligand against the binding pocket so we can prioritize the top 5 for in vitro enzymatic assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network / Cross-Modal Protein-Ligand Interaction Model (e.g., Target-Aware 3D GNNs such as TankBind or GNINA): Can reliably score and rank-order relative binding affinities (pKd, delta G) and highlight putative 3D contact interfaces for rigid or semi-rigid binding pockets. Cannot speak to in vivo biological efficacy, cell permeability, metabolic stability (ADMET), synthetic feasibility, or dynamic induced-fit conformational changes not captured in the static crystal structure.

---

## [237] source=multitask_sft_big

**USER:** I have an AnnData (.h5ad) object containing raw UMI counts from 10x Genomics scRNA-seq of human peripheral blood mononuclear cells (PBMCs). Can you predict the specific cell-type annotations (e.g., naive CD4+ T cell, classical monocyte, memory B cell) for each cell barcode?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer) fine-tuned for cell-type annotation / CellTypist: Can accurately map high-dimensional single-cell transcriptomic profiles to curated cell-type taxonomies, handle sequencing depth variations, and provide confidence scores for canonical cell states. Cannot reliably identify entirely novel cell types outside its training taxonomy (often forcing misclassification into the closest known class), directly infer protein expression levels or post-translational modifications, nor determine spatial organization or causal gene regulatory mechanisms without multimodal/perturbation data.

---

## [238] source=multitask_sft_big

**USER:** I need to estimate the aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) for a series of small-molecule kinase inhibitors I'm optimizing. Here are the SMILES strings: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5 and c1cc(ccc1C(=O)Nc2cc(c(cc2)Cl)C(F)(F)F)CN3CCNCC3. Can you predict these ADMET values?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) or Pretrained Molecular Graph Transformer (e.g., Chemprop or GROVER fine-tuned on physicochemical property benchmarks like ESOL and ChEMBL logD): Can speak to: Fast zero-shot/few-shot estimation of thermodynamic solubility (logS) and lipophilicity/membrane partitioning (logD at specified pH) for drug-like small molecules based on 2D chemical graph topology and learned substructural motifs. Cannot speak to: Solid-state crystal lattice packing, polymorphism, kinetic precipitation rates, non-ideal formulation effects (e.g., cosolvents, surfactants), salt forms, or non-traditional modalities outside the training distribution (e.g., PROTACs, macrocycles, metal complexes).

---

## [239] source=multitask_sft_big

**USER:** I have an AnnData object containing raw and normalized scRNA-seq count matrices from a human PBMC dataset. Can we use a pretrained model to predict fine-grained cell type annotations for each single cell?

**ASSISTANT:** Single-cell transcriptomic foundation transformer (e.g., scGPT, Geneformer): Can reliably map known transcriptional cell states, assign canonical cell lineages, and perform robust transfer learning across varying batches and sequencing technologies based on gene expression profiles. Cannot definitively identify novel or previously uncharacterized cell states without reference fine-tuning, nor can it distinguish cell phenotypes that rely heavily on non-transcriptomic features like spatial tissue architecture, surface protein abundance (CITE-seq), or chromatin accessibility (scATAC-seq) unless multi-modal data is incorporated.

---

## [240] source=multitask_sft_big

**USER:** We have synthesized a series of novel small-molecule analogs targeting an oncology kinase. Can you evaluate the lead compound (SMILES: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5) for potential ADMET liabilities, specifically hERG cardiac toxicity risk, CYP3A4/CYP2D6 inhibition, and predicted percentage of oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Molecular Graph Neural Network / Directed Message Passing Neural Network (e.g., Chemprop / ADMET-AI): Can speak to: In silico statistical probability of hERG channel blockade, qualitative or categorical inhibition against major cytochrome P450 isoforms, and general classification or learned estimates of human oral bioavailability based on molecular structure and physicochemical descriptors. Cannot speak to: In vivo dynamic pharmacokinetics, compound formulation/solubility-limited absorption effects, active transport (e.g., P-gp efflux) mechanisms unless specifically modeled, active metabolites, dose-dependent saturation, or definitive clinical safety outcomes.

---

## [241] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix from a human PBMC sample (10x Genomics). Can you predict the discrete cell-type labels and confidence scores for each cell barcode using a reference model?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer, fine-tuned for cell-type annotation) / CellTypist: Can accurately assign canonical and fine-grained cell-type annotations based on gene expression profiles, correct for technical dropout/batch variability, and output prediction probabilities. Cannot reliably identify entirely novel or non-reference cell types (tends to force-map them to known classes), verify post-transcriptional protein abundances, or infer spatial/tissue microenvironment dynamics from dissociated transcriptomes alone.

---

## [242] source=multitask_sft_big

**USER:** I have an unannotated 10x Genomics single-cell RNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs). Can you predict the cell-type annotations for each individual cell using a standard reference?

**ASSISTANT:** Transformer-based single-cell foundation model fine-tuned for cell-type annotation (e.g., scGPT, Geneformer) or transfer-learning classifier (e.g., CellTypist): Can accurately map single-cell transcriptional profiles to established cell-type ontologies, distinguish discrete lineages, and resolve sub-populations represented in the pretraining/reference atlases. Cannot determine protein-level abundance, post-translational modifications, spatial context, or reliably annotate completely novel cell types not present in the training distribution.

---

## [243] source=multitask_sft_big

**USER:** I have an AnnData object containing raw UMI counts from 15,000 single cells isolated from human peripheral blood mononuclear cells (PBMCs) sequenced via 10x Genomics. Can you predict the high-resolution cell-type annotations for each individual cell using its transcriptomic profile?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer) / Geneformer fine-tuned for cell-type classification: Can accurately assign discrete cell-type labels and broad lineage identities by modeling nonlinear gene-gene co-expression networks and accommodating batch effects across typical scRNA-seq datasets. Cannot reliably detect entirely novel or unprecedented cell lineages lacking reference representations, cannot directly infer spatial context or post-translational protein states, and cannot rectify misclassifications driven by poor single-cell quality control metrics like high mitochondrial fractions or unresolved doublets.

---

## [244] source=multitask_sft_big

**USER:** We are optimizing lead candidates against the SARS-CoV-2 main protease (PDB: 7BQY). Given the 3D holo structure of the target binding pocket and this list of 40 candidate SMILES strings, can you predict the binding affinity (pKd or kcal/mol) for each compound so we can prioritize top candidates for in vitro assay synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, or GNINA-based convolutional/interaction networks): CAN predict relative ranking of ligand binding strength, estimate equilibrium binding affinity scores (pKd, pKi, or docking-like energy scores), and identify key contact interactions in the binding pocket. CANNOT speak to binding kinetics (association/dissociation rates kon and koff), thermodynamic entropy contributions accurately without explicit solvent/MD simulations, physiological ADMET profiles (permeability, metabolic stability, toxicity), or induced-fit conformational changes extending significantly beyond the trained structural pocket.

---

## [245] source=multitask_sft_big

**USER:** Could you evaluate the ADMET profile for our series of lead kinase inhibitors? Specifically, we need predictions for hERG liability (pIC50), potential CYP3A4 and CYP2D6 inhibition, and estimated human oral bioavailability (%F) from their SMILES strings to prioritize candidates for animal PK studies.

**ASSISTANT:** Multitask Directed Message Passing Neural Network (D-MPNN) fine-tuned on Therapeutics Data Commons (TDC) / ChEMBL ADMET benchmarks (e.g., Chemprop): Can speak to: In silico screening and binary/continuous risk estimation for hERG-mediated cardiotoxicity, substrate/inhibition flags for key cytochrome P450 isoforms, and intrinsic structural propensities impacting oral absorption (e.g., Rule of 5 properties, membrane permeability surrogates). Can't speak to: Dynamic in vivo pharmacokinetic time-concentration curves (AUC, Cmax, clearance) which require full PBPK modeling; formulation-dependent bioavailability impacts (e.g., crystalline polymorphism, salt selection, lipid formulations); idiosyncratic drug-induced liver injury (DILI); or off-target safety risks outside the explicitly trained target endpoints.

---

## [246] source=multitask_sft_big

**USER:** I have an uncharacterized 320-amino-acid sequence from a marine bacterium: 'MKTIIALSYIFCLVFAQ...'. Can you predict its static 3D tertiary structure, generate the PDB coordinate file, and indicate the confidence score for the predicted domains?

**ASSISTANT:** AlphaFold2 / ESMFold (Iterative Attention-based Protein Structure Prediction Networks): Can accurately predict ground-state 3D atomic coordinates from primary sequences, generate per-residue confidence scores (pLDDT), and output predicted aligned error (PAE) to identify rigid domains. Cannot reliably predict full dynamic conformational ensembles, dynamic transition states, the structural impacts of arbitrary non-protein ligands/cofactors without explicit co-modeling, or the precise energetic consequences of single-point missense mutations.

---

## [247] source=multitask_sft_big

**USER:** I have an annotated .h5ad count matrix containing single-cell RNA-seq profiles for about 20,000 human peripheral blood mononuclear cells (PBMCs) generated on the 10x Chromium platform. Can you predict the cell-type labels for these cells, resolving both major lineages (like T, B, and NK cells) and finer subsets (such as regulatory T cells and classical vs. non-classical monocytes)?

**ASSISTANT:** Transformer-based single-cell foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type classification): It can speak to canonical and fine-grained transcriptomic identities, gene-expression-driven cell classifications, and marker-gene co-expression patterns present in the training reference atlas. It cannot speak to functional protein abundance (e.g., post-transcriptional surface markers), in vivo functional state or cytokine secretion capacity, spatial microenvironment/tissue context, or reliably annotate novel/pathological cell states absent from the pretraining reference.

---

## [248] source=multitask_sft_big

**USER:** Could you predict the aqueous solubility (logS in mol/L) and lipophilicity (logD at physiological pH 7.4) for this series of kinase inhibitor analogs represented as SMILES: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'?

**ASSISTANT:** Pretrained Molecular Graph Representation / Transformer Model (e.g., ChemBERTa or Chemprop D-MPNN fine-tuned on ChEMBL/TDC ADMET benchmarks): {'can_speak_to': ['Estimated intrinsic aqueous solubility (logS) and distribution coefficients (logD7.4) of drug-like small molecules based on 2D topology and functional group contributions.', 'Relative ranking and physicochemical trend analysis across closely related structural analogs within the training domain.', 'Identification of lipophilic or solubilizing pharmacophore features (e.g., basic amines, aromatic rings).'], 'cant_speak_to': ['Experimental solubility variations caused by crystal polymorphs, particle size, solid-state lattice energy, or amorphous forms.', 'Matrix and media effects (e.g., buffer composition, salt forms, biorelevant media like FaSSIF/FeSSIF, or varying ionic strength).', 'Accurate pH-dependent ionization profiles without explicit tautomer/protomer enumeration and micro-pKa modeling.']}

---

## [249] source=multitask_sft_big

**USER:** We have designed a batch of 20 novel pyrrolo[2,3-d]pyrimidine analogs as potential kinase inhibitors. Could you estimate their aqueous solubility (logS) and physiological lipophilicity (logD at pH 7.4) from their canonical SMILES strings to help us triage which compounds proceed to in vitro ADME assays?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on small-molecule ADMET/physicochemical benchmarks: Can speak to: Rapid quantitative estimation of intrinsic solubility (logS), logD7.4, and relative rank-ordering of drug-like small molecules within the model's structural applicability domain. Cannot speak to: Solid-state polymorph-dependent solubility, crystal lattice packing effects, non-standard ionization equilibria (without explicit pKa calculations), kinetic precipitation rates, or behavior in specific formulation/excipient mixtures.

---

## [250] source=multitask_sft_big

**USER:** I have an unannotated 10x Genomics scRNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs) and need to annotate the cell type for each individual cell barcode. Can you predict the specific lineage and subtype labels for this dataset?

**ASSISTANT:** Transformer-based single-cell foundation model (e.g., scGPT, Geneformer): Can accurately map high-dimensional gene expression profiles to known cell lineages, handle batch-effect-adjusted transcriptomic signatures, and transfer learned representations across tissues. Cannot definitively annotate novel, rare, or aberrant cell states absent from the training reference, nor can it infer spatial organization, absolute protein abundance, or post-transcriptional dynamics from transcript counts alone.

---

## [251] source=multitask_sft_big

**USER:** I have an uncharacterized 280-amino acid sequence from a fungal secondary metabolite gene cluster (MSKGEELFTGVVPILVELDGDVNGHKFSVSGEGEGDATYGKLTLKFICTTGKLPVPWPTLVTTL...). Could you generate the predicted 3D Cartesian coordinates (PDB format) for this monomer along with per-residue confidence scores?

**ASSISTANT:** AlphaFold2: Can reliably predict static 3D backbone and side-chain coordinates for folded domains and provide local confidence metrics (pLDDT) and domain-orientation reliability (PAE). Cannot accurately capture dynamic conformational ensembles/folding kinetics, simulate solution thermodynamics across varying pH or temperature, or explicitly account for non-canonical post-translational modifications (PTMs) and native ligand-bound states without specialized docking.

---

## [252] source=multitask_sft_big

**USER:** We identified a novel missense variant in the LDLR gene (c.854T>C, p.Leu285Pro) in an adult patient with severe hypercholesterolemia. Could you evaluate whether this amino acid substitution is likely pathogenic or benign based on evolutionary conservation and structural impact?

**ASSISTANT:** Pretrained Missense Variant Effect Predictor (e.g., AlphaMissense, EVE, or ESM-1v): Can speak to: The likelihood that a single amino acid substitution impairs protein structural stability, evolutionary fitness, or molecular function, outputting a calibrated pathogenicity probability score. Can't speak to: Non-coding variants, indels, synonymous changes, splicing effects, complex gene-gene interactions, incomplete penetrance, patient-specific clinical severity, or standalone definitive clinical diagnosis (cannot replace full ACMG/AMP guideline-based clinical adjudication).

---

## [253] source=multitask_sft_big

**USER:** I have a small batch of drug leads for an oncology target. Could you estimate the aqueous solubility (logS) and lipophilicity at physiological pH (logD7.4) for this candidate: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) or Pretrained Molecular Graph Transformer (e.g., Chemprop, ChemBERTa fine-tuned on TDC/ChEMBL ADMET benchmarks): Can speak to: In silico estimates of thermodynamic/intrinsic aqueous solubility, logD at specified pH, structural feature contributions to ADMET endpoints, and relative ranking of analogs during lead optimization. Cannot speak to: Solid-state crystal lattice energies, polymorphism, formulation or co-solvent effects, dynamic in vivo precipitation kinetics, compound stability/degradation over time, or exact experimental values outside the model's chemical training distribution.

---

## [254] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq count matrix from human peripheral blood mononuclear cells (PBMCs) sequenced on the 10x Genomics platform. Can you run this through an automated model to label each single-cell profile with its precise immune cell type and subset?

**ASSISTANT:** Single-cell foundation transformer model (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): It can speak to classifying cells into known transcriptional cell types and lineages, outputting probabilistic assignment scores, and identifying common cellular states present in reference atlases. It cannot speak to spatial localization, post-translational protein activity without multiomic data, morphological features, or definitively identifying entirely novel or pathogenic cell states absent from the pretraining/fine-tuning reference corpora.

---

## [255] source=multitask_sft_big

**USER:** I have an AnnData object containing log-normalized single-cell RNA-seq counts from human peripheral blood mononuclear cells (PBMCs). Can you annotate the specific cell types for each cell profile in my dataset?

**ASSISTANT:** Pretrained Single-Cell Transformer Foundation Model (e.g., scGPT, Geneformer): Can reliably identify known immune lineages, classify standard cell states represented in reference training atlases, and generalize across batch variations and technical noise. Cannot identify entirely novel or non-cataloged cell types, infer functional cellular states driven primarily by post-transcriptional or spatial contexts not captured in gene expression, or resolve phenotypes in cells with extreme dropout or low sequencing depth.

---

## [256] source=multitask_sft_big

**USER:** I have the co-crystal structure of human CDK2 (PDB: 1HCK) and a library of 45 synthesized small-molecule quinazoline derivatives in SDF format. Can you predict the binding affinity (pK_d or binding free energy) for each compound docked into the ATP-binding pocket so we can prioritize the top candidates for in vitro assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Structure-Based Affinity Prediction (e.g., TankBind, GNINA, or EGNN fine-tuned on PDBbind): Can: Score and rank-order small-molecule ligands based on static 3D geometric and physicochemical complementarity within the target pocket, estimating empirical metrics like pKd/pKi. Can't: Account for explicit desolvation free energies, conformational entropy changes, induced-fit target flexibility, binding kinetics (k_on/k_off residence times), or downstream cellular potency (IC50/EC50) influenced by membrane permeability and non-specific binding.

---

## [257] source=multitask_sft_big

**USER:** I have an uncharacterized 340-amino-acid sequence from an extremophilic bacterium (sequence: MSALTRV...VKL). Can you predict its 3D atomic coordinates, provide a PDB file, and give per-residue confidence scores so I can determine if it adopts a standard TIM barrel fold?

**ASSISTANT:** AlphaFold2 (Evoformer/Structure Module architecture): Can accurately predict static 3D atomic coordinates from single-chain sequences using evolutionary profiles, provide residue-level confidence metrics (pLDDT), and estimate inter-domain alignment reliability (PAE). Cannot reliably model real-time conformational dynamics/transition pathways, predict the destabilizing effects of arbitrary single-point mutations, or account for structural changes induced by non-covalent small-molecule ligands, ions, and post-translational modifications without specialized extensions.

---

## [258] source=multitask_sft_big

**USER:** I have an uncharacterized 240-residue bacterial enzyme sequence: 'MKLLVILSLVAVVLAACSS...'. Can you predict its 3D all-atom tertiary structure, provide the PDB coordinates, and generate the residue-level pLDDT confidence metrics to see if it adopts a stable catalytic fold?

**ASSISTANT:** Equivariant Graph Neural Network / Transformer-based Protein Structure Predictor (e.g., AlphaFold2, ESMFold): Can reliably predict static, low-energy ground-state 3D atomic coordinates, secondary and tertiary folding patterns, multimeric complexes (if multimer-trained), and local prediction confidence (pLDDT / PAE). Cannot speak to real-time folding kinetics/pathways, dynamic conformational ensembles under varying physiological conditions (pH, temperature), free energy landscapes (ΔG), or structural alterations caused by unmodeled post-translational modifications, small-molecule ligands, and solvent effects.

---

## [259] source=multitask_sft_big

**USER:** I need to evaluate a small batch of hit compounds for lead optimization. Could you predict the aqueous kinetic solubility (logS) and lipophilicity at physiological pH (logD7.4) for these SMILES: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5' and 'CC(C)CC1=CC=C(C=C1)C(C)C(=O)O'?

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN / Chemprop) or Molecular Graph Transformer (e.g., ChemBERTa fine-tuned on ADMET benchmarks like ESOL and ChEMBL-logD): Can speak to: Expected thermodynamic solubility, partition/distribution coefficients (logP/logD7.4) based on 2D topological features and functional groups within the model's training applicability domain. Cannot speak to: Experimental variability (e.g., exact buffer ionic strength, temperature, dynamic solid-state crystalline polymorphism, formulation effects), precipitation kinetics in complex biological media, or complex multi-organ in vivo pharmacokinetics (e.g., active gut transport, clearance rates).

---

## [260] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (NM_001165963.4:c.3824A>G, p.Asn1275Ser) in a child presenting with early-onset focal epilepsy. Could you run an in silico pathogenicity prediction to determine if this variant is likely damaging or benign?

**ASSISTANT:** Supervised structural-evolutionary variant effect predictor (e.g., AlphaMissense, PrimateAI-3D, ESM-1v): Can speak to the statistical likelihood that a specific missense variant disrupts protein function or is classified as pathogenic versus benign based on structural context and evolutionary constraint. Cannot speak to definitive clinical diagnosis, variant penetrance, expressivity, specific drug response, non-missense consequences (such as splicing disruptions), or regulatory/epigenetic modifiers.

---

## [261] source=multitask_sft_big

**USER:** We have a series of 25 novel small-molecule kinase inhibitors ready for lead optimization. Could you run an in silico ADMET screening on their SMILES strings to predict potential hERG cardiotoxicity liabilities (IC50), CYP450 inhibition profiles (specifically CYP3A4 and CYP2D6), and estimated human oral bioavailability (%F) to help prioritize candidates for in vitro assays?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: Rapid, high-throughput preliminary ranking of 2D chemical structures against known in vitro ADMET endpoints (hERG inhibition, CYP isozyme interactions, and qualitative/semi-quantitative oral absorption). Cannot speak to: Quantitative in vivo pharmacokinetic parameters over time (AUC, Cmax, clearance rates without physiologically based pharmacokinetic/PBPK modeling), drug-drug interactions mediated by non-target enzymes or transporters, formulation/solubility-dependent bioavailability in specific animal models, or stereospecific toxicity when SMILES stereocenters are undefined or poorly represented in training distributions.

---

## [262] source=multitask_sft_big

**USER:** I have the crystal structure of the human CDK2 receptor (PDB: 1HCK) and a series of 45 newly synthesized purine-derivative analogs as SMILES strings. Can you predict their binding affinities (pKd or binding free energy in kcal/mol) to the ATP-binding site to help prioritize candidates for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (e.g., GNINA, TankBind, or Uni-Mol for structure-based protein-ligand scoring): Can speak to: Relative ranking of ligand binding potencies, spatial complementarity in the binding pocket, and enrichment of active hits from small-to-medium focused chemical libraries based on learned 3D geometric interactions. Cannot speak to: Highly accurate absolute thermodynamic binding free energies (due to implicit solvent approximations and neglected entropic effects), large-scale induced-fit or allosteric protein conformational changes, covalent binding mechanisms, or in vivo pharmacokinetics, selectivity, and cytotoxicity.

---

## [263] source=multitask_sft_big

**USER:** We have synthesized a series of 50 novel small-molecule kinase inhibitors. Could you predict the aqueous solubility (logS) and distribution coefficient at physiological pH (logD at pH 7.4) from their SMILES strings to prioritize the candidates for our upcoming pharmacokinetic profiling?

**ASSISTANT:** Pretrained Molecular Graph Neural Network (e.g., Chemprop / D-MPNN or ChemBERTa fine-tuned on ADMET benchmarks such as TDC or MoleculeNet): Can speak to: Relative ranking of small-molecule oral drug-like compounds, 2D topology-driven lipophilicity and general thermodynamic solubility approximations within the chemical space of the training distribution. Can't speak to: Polymorphic crystal forms, kinetic versus thermodynamic solubility differences, precipitation kinetics, matrix/buffer-specific ionic effects, or predictions for chemical spaces far outside typical medicinal small molecules (such as large macrocycles, PROTACs, or organometallics).

---

## [264] source=multitask_sft_big

**USER:** I have isolated an uncharacterized bacterial hydrolase from an environmental metagenomic screen with the following sequence: 'MNTIILGAGPVGLSTALEIALRAGHEVTIIDKQPSEVSRALEEQGVEVVTEAEDAARLRARGLSLFDAVVDAVTPAEDL'. Can you predict its 3D coordinates in PDB format and indicate the confidence of the predicted active site region?

**ASSISTANT:** AlphaFold2 / ESMFold (MSA and Protein Language Model-based Structure Predictors): Can predict high-accuracy static 3D Cartesian coordinates (PDB/mmCIF), per-residue prediction confidence metrics (pLDDT), and inter-domain relative orientation confidence (PAE). Cannot predict dynamic conformational ensembles, folding kinetics/pathways, effects of post-translational modifications (PTMs), or quantitative binding affinities with arbitrary small-molecule substrates/ligands.

---

## [265] source=multitask_sft_big

**USER:** I have the apo PDB structure of the human ABL1 kinase domain and a series of 25 novel ATP-competitive heterocyclic inhibitors as SDF files. Can you predict the binding affinity (pKd/IC50) for each complex and identify which compound has the strongest predicted interaction?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) / 3D-CNN Protein-Ligand Scoring Model (e.g., GNINA, TankBind, PLANET): Can reliably score and rank static 3D binding poses, estimate binding affinity metrics (such as pKd or delta G approximations), and highlight structural interaction hotspots; cannot account for explicit solvent dynamics, induced-fit conformational changes without explicit sampling, downstream ADMET properties, or actual in vivo cellular efficacy.

---

## [266] source=multitask_sft_big

**USER:** We have designed a series of five lead small molecules for an oncology target (SMILES provided). Could you evaluate their ADMET profiles, specifically predicting cardiotoxicity via hERG inhibition, metabolic interaction profiles across CYP3A4 and CYP2D6, and estimated oral bioavailability?

**ASSISTANT:** Multi-Task Molecular Message Passing Neural Network / Molecular Graph Transformer (e.g., Chemprop, ADMET-AI, or Uni-Mol): Can speak to: Fast in silico risk assessment, quantitative or probabilistic scoring of hERG-mediated QT prolongation liability, binary inhibition classification across major CYP450 isoforms, and rule/structure-based categorization of human oral absorption. Can't speak to: Exact in vivo pharmacokinetic curves (Cmax, Tmax, AUC), first-pass metabolic rate nuances beyond the training set, vehicle/formulation-dependent solubility and permeability effects, or stereoisomer-specific properties if derived from 2D SMILES without 3D conformational optimization.

---

## [267] source=multitask_sft_big

**USER:** I have the amino acid sequence of a putative kinase isolated from an uncharacterized marine bacterium (MKTAYIAKQRQISFVKSHFSRQLEER...). Can you predict its 3D tertiary coordinates (as a PDB file) and tell me which residues form the putative catalytic site?

**ASSISTANT:** AlphaFold2 / ESMFold (Deep Learning-based Protein Structure Prediction Models): CAN generate high-accuracy static 3D atomic coordinates (backbone and side chains) for folded domains, assess local prediction reliability via per-residue confidence metrics (pLDDT) and pairwise domain alignments (PAE), and identify conserved structural folds. CANNOT reliably simulate thermodynamic conformational dynamics or folding kinetics, predict non-covalent binding poses for small-molecule ligands/cofactors natively, or provide structural certainty for intrinsically disordered regions (IDRs) or conditions deviating from physiological states (e.g., extreme pH, temperature).

---

## [268] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (c.3862C>T, p.Arg1288Cys) in an infant presenting with severe refractory seizures. Could you run an in silico analysis to predict whether this specific amino acid substitution is likely pathogenic or benign?

**ASSISTANT:** Deep learning-based missense variant pathogenicity predictor (e.g., AlphaMissense): Can predict the structural and evolutionary likelihood that a missense single-nucleotide variant disrupts protein function and classify it as likely benign, ambiguous, or likely pathogenic. Cannot determine clinical penetrance, patient-specific phenotypic severity, mode of inheritance, or evaluate non-coding, synonymous, frameshift, or splice-site variants; additionally, it cannot replace comprehensive clinical genetics assessment or serve as standalone proof of pathogenicity under ACMG/AMP guidelines.

---

## [269] source=multitask_sft_big

**USER:** I need to evaluate the drug-likeness of a lead optimization candidate. Can you predict the aqueous solubility (logS) and distribution coefficient (logD at pH 7.4) for the compound with SMILES: CC1=CC=C(C=C1)NC(=O)CN2CCN(CC2)C3=CC=CC=C3?

**ASSISTANT:** Fine-Tuned Directed Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Molecular Transformer (e.g., ChemBERTa-2): Can reliably predict equilibrium thermodynamic solubility and lipophilicity/distribution coefficients for standard drug-like organic small molecules within its learned chemical space. Cannot account for experimental kinetic solubility, solid-state crystal polymorphism, formulation or salt effects, or novel organometallic/macrocyclic structures absent from its training distribution.

---

## [270] source=multitask_sft_big

**USER:** I have a high-resolution co-crystal structure of human CDK2 (apo structure PDB: 1HCL) and a library of 50 novel pyrazole-based small molecules. Can you predict the binding affinity (pIC50 or Kd) of each ligand bound to the ATP-binding pocket, factoring in 3D atomic coordinates and non-covalent interactions?

**ASSISTANT:** 3D Equivariant Graph Neural Network / Structure-Based Scoring Model (e.g., TankBind, EquiBind, or GNINA/Pafnucy-style 3D-CNN): Can predict static pose-dependent scoring metrics and relative binding affinities (e.g., ranking pKd/pIC50 values) based on spatial and physicochemical contact features within the binding pocket. Can't reliably account for extensive induced-fit receptor plasticity, predict binding kinetics (kon/koff rates), assess entropic solvent reorganization (displacement of structured waters) without explicit molecular dynamics, or determine functional pharmacology (e.g., distinguishing agonism from antagonism).

---

## [271] source=multitask_sft_big

**USER:** I have the crystal structure of human CDK2 (PDB ID: 1HCK) and a list of 25 analog drug candidates as SMILES strings. Can you predict the binding affinity (pKd or binding free energy) for each ligand against this target to help rank them for our next synthesis cycle?

**ASSISTANT:** 3D Equivariant Graph Neural Network for Protein-Ligand Complexes (e.g., TankBind, EquiBind, or GNINA scoring networks): Can predict relative binding affinities (pKd/pKi), rank ligand poses, and score geometric/electrostatic complementarity in the binding pocket. Cannot predict binding kinetics (kon/koff residence time), induced-fit receptor plasticity beyond static structures, entropic/explicit solvent effects accurately, or downstream functional activity (agonist vs. antagonist) and cellular efficacy.

---

## [272] source=multitask_sft_big

**USER:** I have the amino acid sequence of a novel bacterial membrane transporter (540 residues). Can you predict its full 3D atomic coordinates, identify likely transmembrane alpha-helices, and provide confidence metrics like pLDDT?

**ASSISTANT:** Attention-based end-to-end protein structure prediction model (e.g., AlphaFold2 / ESMFold): Can accurately predict static 3D Cartesian coordinates, secondary/tertiary folding topology, domain arrangements, and residue-level confidence (pLDDT/PAE). Cannot reliably model real-time conformational dynamics, explicit thermodynamic stability changes (delta-delta G) from single-point mutations, or binding-induced structural changes in the absence of co-factors or lipid membrane environments.

---

## [273] source=multitask_sft_big

**USER:** We are optimizing a lead series against IRAK4. Can you evaluate these three SMILES candidates: CC1=CC=C(C=C1)NC(=O)C2=CN=C(N=C2)N3CCNCC3, CC(=O)NC1=CC=C(O1)C(=O)N2CCC(CC2)NC3=NC=NC4=C3C=CN4, and C1CC1C2=NC(=CS2)C3=CN=C(N=C3)NC4=CC=C(C=C4)F for ADMET risk, specifically hERG channel inhibition, CYP3A4 inhibition, and human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., ADMET-AI / Chemprop): Can speak to: In silico screening probabilities for cardiotoxicity risk (hERG IC50/inhibition), metabolic liability via CYP3A4 inhibition flags, and generalized human oral bioavailability classification or fraction absorbed based on public benchmark data (e.g., Therapeutics Data Commons). Cannot speak to: In vivo formulation effects (e.g., amorphous solid dispersion vs. crystalline solubility), complex multi-organ systemic clearance, patient-specific pharmacokinetics (age, hepatic impairment, drug-drug interactions), or precise quantitative plasma concentration-time profiles (AUC, Cmax), which require PBPK modeling and experimental validation.

---

## [274] source=multitask_sft_big

**USER:** I have docked 50 novel small-molecule kinase inhibitors into the active site of human CDK2 (PDB: 1HCK). Could you predict the binding affinity (pKd/pKi) for these complex conformations to help us prioritize the top 5 candidates for chemical synthesis?

**ASSISTANT:** Structure-Based 3D Equivariant Graph Neural Network (e.g., TankBind, PLANET) or 3D-CNN Scoring Model (e.g., GNINA): Can reliably score static 3D protein-ligand poses, capture spatial and non-covalent interactions (e.g., hydrogen bonds, hydrophobic contacts), and estimate relative or absolute thermodynamic binding affinity (pKd/pKi/ΔG). Cannot account for complex induced-fit conformational dynamics, water-mediated entropy changes without explicit solvent modeling, binding kinetics (kon/koff rates or residence time), or downstream ADMET/toxicity profiles.

---

## [275] source=multitask_sft_big

**USER:** We have solved the apo and holo crystal structures of the SARS-CoV-2 main protease (Mpro) and designed a library of 250 peptidomimetic inhibitors. Could you predict the binding affinity (pK_d or IC50 values) for these candidate compounds against the Mpro active site to help us prioritize leads for in vitro enzymatic assays?

**ASSISTANT:** 3D Structure-Based Equivariant Graph Neural Network (e.g., EquiBind, GNINA, or Uni-Mol): Can reliably score and rank-order non-covalent protein-ligand binding affinities (e.g., pKd, delta-G) based on 3D geometric and atomic complementarity. Cannot account for covalent binding mechanisms, full solvent thermodynamics/entropy changes without explicit water modeling, target conformational dynamics/induced-fit transitions beyond static structures, or pharmacokinetic properties like bioavailability and clearance.

---

## [276] source=multitask_sft_big

**USER:** We identified a novel de novo missense variant in SCN1A (c.3944G>A, p.Arg1315His) in a patient with early-onset epileptic encephalopathy. Can you evaluate the structural and evolutionary constraint at this position to predict whether this specific substitution is likely pathogenic or benign?

**ASSISTANT:** AlphaMissense: AlphaMissense can speak to the likelihood that a single-amino-acid missense substitution disrupts human protein structure/function, providing calibrated categorical calls (likely benign, ambiguous, likely pathogenic) based on structural context and evolutionary conservation. It cannot speak to non-coding variants, frameshifts, indels, copy number alterations, incomplete penetrance, inheritance mode, phenotypic severity, or definitive clinical diagnosis without corroborating functional and pedigree evidence.

---

## [277] source=multitask_sft_big

**USER:** We have designed a batch of 25 novel small-molecule analogs represented as SMILES strings for our oncology lead optimization campaign. Could you run an in silico screen to predict their aqueous solubility (logS) and lipophilicity at physiological pH (logD7.4) so we can prioritize the most drug-like candidates for synthesis and ADME testing?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Chemical Language Model (e.g., Chemprop D-MPNN or ChemBERTa-2 fine-tuned on Therapeutics Data Commons / ChEMBL ADME datasets): Can speak to: Relative ranking of small-molecule physicochemical properties (logS, logD7.4) derived from 2D molecular graph topology, charge state, and functional group contributions under standard screening conditions. Can't speak to: Solid-state crystal lattice energy/polymorphism, thermodynamic vs. kinetic solubility discrepancies, counterion/salt-form effects, formulation or excipient interactions, and conditions with non-standard temperature or ionic strength.

---

## [278] source=multitask_sft_big

**USER:** I have an uncharacterized fungal sequence: 'MVLSEGEWQLVLHVWAKVEADVAGHGQDILIRLFKSHPETLEKFDRFKHLKTEAEMKASEDLKKHGVTVLTALGAILKKKGHHEAELKPLAQSHATKHKIPIKYLEFISEAIIHVLHSRHPGDFGADAQGAMNKALELFRKDIAAKYKELGYQG'. Can you predict its 3D atomic coordinates, output a PDB file, and provide per-residue confidence scores?

**ASSISTANT:** AlphaFold2 / ESMFold (Transformer- and Evoformer-based protein structure prediction architectures): Can accurately predict static, ground-state 3D tertiary coordinates (backbone and side chains) and provide local/global confidence metrics (pLDDT, PAE). Cannot reliably predict dynamic conformational ensembles, folding kinetics/pathways, environmental effects (e.g., pH, temperature, membrane environments), or bound states involving cofactors, small-molecule ligands, and post-translational modifications without specialized multi-modal models.

---

## [279] source=multitask_sft_big

**USER:** Could you predict the aqueous solubility (logS) and distribution coefficient (logD at pH 7.4) for these two SMILES strings from our lead optimization series: 'Cc1nc(Nc2ccc(O)cc2)nc(N3CCNCC3)n1' and 'O=C(Nc1cccc(Cl)c1)c2cccnc2'?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) or Pretrained Molecular Transformer (e.g., ChemBERTa-2) fine-tuned on ADMET regression datasets: Can accurately predict standard equilibrium thermodynamic properties (logS, logD) from 2D topological/chemical graph representations and rank analogs within drug-like chemical space. Cannot account for solid-state crystal polymorphism, kinetic dissolution rates, temperature/salt-dependent formulation effects, or dynamic in vivo metabolic and pharmacokinetics behaviors.

---

## [280] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in SCN1A (c.4942C>T, p.Arg1648Cys) in an infant presenting with severe focal seizures. Can you predict the pathogenicity score and classification for this variant?

**ASSISTANT:** Deep Learning Variant Effect Predictor / Protein Language Model (e.g., AlphaMissense, ESM-1v, EVE): Can quantify evolutionary constraint, structural perturbation, and the likelihood of protein biochemical dysfunction for missense single nucleotide variants. Cannot evaluate non-coding or structural variations, determine variable clinical penetrance, predict specific syndromic phenotypes, or replace comprehensive ACMG/AMP clinical diagnostic guidelines.

---

## [281] source=multitask_sft_big

**USER:** We identified a novel de novo missense variant in SCN1A (p.Met1328Val) in an infant presenting with intractable seizures. Can you predict the pathogenicity score for this variant to help us assess whether it is likely disease-causing?

**ASSISTANT:** Structural-evolutionary variant effect predictor (e.g., AlphaMissense, EVE, ESM-1v): {'can': ['Predict whether single-nucleotide missense variants are likely pathogenic or benign based on protein structure, sequence homology, and evolutionary conservation.', 'Provide calibrated pathogenicity risk scores or continuous fitness-disruption estimates for amino acid substitutions.', 'Help prioritize Variants of Uncertain Significance (VUS) for targeted functional validation assays.'], 'cant': ['Account for complex patient-specific factors such as variable expressivity, incomplete penetrance, epigenetic context, or modifier genes.', 'Assess non-coding, deep-intronic, splicing, frame-shift, copy-number, or structural variations (unless coupled to genome-wide regulatory models).', 'Provide a standalone, definitive clinical diagnosis without meeting broader ACMG/AMP evidentiary standards and experimental validation.']}

---

## [282] source=multitask_sft_big

**USER:** We identified a novel de novo missense substitution, c.1558C>T (p.Arg520Trp), in the SCN2A gene in an infant presenting with early-onset epileptic encephalopathy. Could you predict whether this specific variant is likely pathogenic or benign?

**ASSISTANT:** AlphaMissense (Deep learning-based missense variant effect predictor): Can speak to: The structural plausibility and evolutionary likelihood of whether this single amino acid change disrupts protein function (pathogenicity score vs. benign probability). Can't speak to: Non-coding or splice-site effects, indel/structural variants, specific clinical phenotypes (e.g., gain-of-function vs. loss-of-function distinctions), incomplete penetrance, or standalone definitive clinical diagnosis without ACMG/AMP guideline integration.

---

## [283] source=multitask_sft_big

**USER:** I have an AnnData count matrix from a 10x Genomics 3' single-cell RNA-seq run of human bone marrow aspirate. Can you run this profile through a model to predict the fine-grained cell types for each cluster and identify any rare hematopoietic stem/progenitor sub-populations?

**ASSISTANT:** Pretrained single-cell foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): Can reliably predict discrete canonical cell identities, developmental states, and general lineage mappings based on normalized or rank-value gene expression embeddings across common human tissues. Cannot reliably annotate novel/unseen rare phenotypes absent from the pretraining reference, infer absolute spatial microenvironment/tissue architecture, resolve cell-cell communications purely from expression counts, or correct for severe technical confounders like unremoved doublets or low-quality sequencing artifacts.

---

## [284] source=multitask_sft_big

**USER:** I have the 3D structure of our target kinase catalytic domain (PDB: 7XYZ) and docked poses for 15 small-molecule lead candidates. Can you predict the binding affinity (pKd/Ki) for each compound-protein complex to help us prioritize which analogues to synthesize?

**ASSISTANT:** Equivariant 3D Geometric Graph Neural Network (e.g., GNINA, TankBind, or PLANET architectures): Can speak to: Relative binding strength ranking, predicted dissociation constants (pKd/pKi), and structural contact scoring based on spatial, electrostatic, and van der Waals complementarity in static poses. Can't speak to: Binding kinetics (association/dissociation rates kon/koff), conformational dynamics/induced-fit transitions not captured in the static snapshot, explicit water thermodynamics/entropy compensation, or downstream pharmacological suitability (ADMET, membrane permeability, and off-target cross-reactivity).

---

## [285] source=multitask_sft_big

**USER:** I have the PDB file for the human CDK2 kinase domain and a series of 50 synthesized small-molecule analogs as SMILES strings. Can you predict the binding affinity (pKd or pIC50) of these ligands to the ATP-binding pocket to help prioritize compounds for our next synthesis round?

**ASSISTANT:** 3D Structure-Based Equivariant Graph Neural Network / 3D CNN (e.g., GNINA, TankBind, Pafnucy): Can speak to: relative binding affinity rankings (pKd/pKi/pIC50), high-throughput screening prioritization, and key spatial contact interactions derived from static 3D binding poses. Cannot speak to: exact absolute thermodynamic free energies (entropic penalties, solvent reorganization), induced-fit dynamic structural changes, allosteric regulation, kinetic parameters (k_on/k_off), or downstream ADMET/cellular bioavailability.

---

## [286] source=multitask_sft_big

**USER:** I have synthesized a library of 25 novel small-molecule lead candidates represented as SMILES strings. Could you run an in silico ADMET profiling screen to predict their hERG-mediated cardiotoxicity liability, CYP3A4/CYP2D6 inhibition, and human oral bioavailability percentages to prioritize which analogues to advance into in vitro assays?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop trained on Therapeutics Data Commons / ChEMBL ADMET benchmarks): Can speak to: Rapid quantitative or binary classification scoring of surrogate in vitro endpoints (e.g., hERG inhibition risk, specific CYP isoform inhibition, and standard bioavailability classification) for conventional drug-like small molecules based on 2D molecular graph topology. Cannot speak to: Dynamic multi-compartment in vivo pharmacokinetics (e.g., non-linear clearance, volume of distribution over time), formulation- or food-dependent absorption, active transport/efflux mechanisms not explicitly trained, dynamic metabolite profiling, stereospecific effects without 3D conformer modeling, or molecules significantly outside the chemical training domain (such as PROTACs, macrocycles, and biologics).

---

## [287] source=multitask_sft_big

**USER:** I have a library of 50 novel small-molecule kinase inhibitors as SMILES strings. Can you predict their aqueous solubility (logS) and distribution coefficient (logD at physiological pH 7.4) to help us triage candidates for oral bioavailability before ordering in vitro ADME assays?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) pretrained on curated molecular property datasets: Can speak to: Standard equilibrium 2D molecular graph-level physicochemical descriptors (logS, logD) for single-molecule organic compounds that fall within the chemical diversity and functional group space of its training set. Cannot speak to: Solid-state crystal lattice energies (polymorph-dependent solubility), dynamic multi-component formulation effects (excipients, co-solvents, precipitation kinetics), pH-dependent ionization behavior outside standard calibrated physiological buffer conditions, or non-covalent aggregate/colloid formation.

---

## [288] source=multitask_sft_big

**USER:** Here is a list of five lead candidate SMILES for an oncology program. Could you predict their ADMET profiles, specifically flag potential cardiotoxicity via hERG inhibition, assess CYP3A4 and CYP2D6 inhibition risk, and estimate percentage oral bioavailability (%F) to guide compound selection for rodent PK studies?

**ASSISTANT:** Chemprop (Directed Message Passing Neural Network / D-MPNN) pretrained on Therapeutics Data Commons (TDC) ADMET datasets: Can reliably predict qualitative and semi-quantitative endpoints for drug-like small molecules, such as binary classification of hERG liability, substrate/inhibitor status for major CYP isozymes, and categorized oral bioavailability likelihood based on chemical structure. Cannot predict dynamic physiological concentration-time profiles, formulation-dependent bioavailability (e.g., amorphous solid dispersions vs. crystalline salts), dose-dependent saturation kinetics, or properties for modalities well outside the training domain such as large cyclic peptides and PROTACs.

---

## [289] source=multitask_sft_big

**USER:** I have an unannotated single-cell RNA-seq dataset from human peripheral blood mononuclear cells (PBMCs) formatted as a raw count matrix in an AnnData (.h5ad) file. Can you use a pretrained model to predict the specific immune cell types for each individual cell?

**ASSISTANT:** Pretrained single-cell transformer foundation model (e.g., scGPT, Geneformer): Can speak to: predicting known cell types and developmental states by capturing complex gene-gene interactions and expression profiles across broad reference atlases. Cannot speak to: reliably identifying entirely novel or uncharacterized cell populations (risks force-classifying them into existing categories), inferring spatial distribution, or accounting for post-translational modifications and protein-level behaviors based solely on transcriptomic abundance.

---

## [290] source=multitask_sft_big

**USER:** I have an AnnData object with processed single-cell RNA-seq count matrices from human peripheral blood mononuclear cells (PBMCs). Can you use a pretrained model to classify and annotate the specific cell types present in this sample?

**ASSISTANT:** Single-cell foundation model (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): Can accurately identify annotated cell types, map non-linear gene expression patterns, and transfer labels across datasets with batch variations; cannot definitively characterize entirely novel or disease-altered cell states absent from training references, infer spatial tissue context from dissociated cells, or confirm in vivo functional behavior without experimental validation.

---

## [291] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in the SCN1A gene (p.Arg1648His) in a child presenting with severe myoclonic epilepsy. Can you predict whether this specific amino acid substitution is pathogenic or benign?

**ASSISTANT:** AlphaMissense: Can speak to the predicted probability that a specific missense single-nucleotide variant disrupts human protein structure and evolutionary fitness (classifying it as likely benign, likely pathogenic, or ambiguous). Cannot speak to non-coding variants, insertions/deletions, splice-site alterations, variable clinical penetrance, specific phenotypic manifestations, or patient-specific modifiers.

---

## [292] source=multitask_sft_big

**USER:** I have the 3D co-crystal structure of the human CDK2 kinase domain (PDB: 1HCK) and an SDF file containing 120 novel pyrrolopyrimidine derivatives. Could you predict the absolute binding affinities (expressed as pKd or pIC50) to prioritize the top 10 candidates for synthesis and biochemical assay validation?

**ASSISTANT:** 3D SE(3)-Equivariant Graph Neural Network (e.g., TankBind, EquiBind with an affinity regression head, or GNINA 3D-CNN scoring function): The model can evaluate spatial interaction geometry (hydrogen bonding, steric clash, hydrophobic contacts) and rank the relative binding strength of structural congeners against a fixed target pocket. It cannot reliably predict kinetic rates (k_on, k_off), account for large induced-fit conformational changes or target flexibility, compute explicit solvent-mediated entropic penalties, or infer cellular efficacy, pharmacokinetic stability, or off-target selectivity.

---

## [293] source=multitask_sft_big

**USER:** We are evaluating a series of 15 newly designed small-molecule kinase inhibitors. Could you predict their aqueous solubility (logS) and distribution coefficient at physiological pH (logD7.4) from their SMILES strings so we can prioritize lead candidates for in vitro ADME profiling?

**ASSISTANT:** Pretrained Directed Message Passing Neural Network (D-MPNN / Chemprop) or Molecular Graph Transformer (e.g., ChemBERTa) fine-tuned on ADMET datasets (e.g., TDC, ChEMBL): Can reliably predict estimated thermodynamic aqueous solubility (logS) and distribution coefficients (logD7.4) for drug-like small organic molecules, providing rapid relative ranking and triaging based on molecular graph/SMILES representations. Cannot accurately account for solid-state effects (polymorphism, crystal lattice energy, salt forms), specific experimental conditions (exact buffer formulations, ionic strength, temperature), or complex macrocycles/novel chemical scaffolds that fall significantly outside the model's training distribution.

---

## [294] source=multitask_sft_big

**USER:** I have the 3D co-crystal structure of human CDK2 (PDB: 1HCK) and a library of 50 novel pyrazole derivatives as SDF files. Can you predict the binding affinity (pKd/delta G) for each protein-ligand complex so we can prioritize the top 5 compounds for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (e.g., TankBind, EquiBind, or SIGN): Can predict: Quantitative binding affinity scores (pKd, pKi, or contact energetics) and identify critical 3D spatial interaction residues from static receptor-ligand conformations. Cannot predict: Real-time induced-fit dynamics, solvent/entropy changes over time, kinetic on/off rates (kon/koff), or broader pharmacokinetic viability and off-target toxicity.

---

## [295] source=multitask_sft_big

**USER:** I have the co-crystal structure of human CDK2 (PDB format) and a library of 150 novel small-molecule inhibitors in SMILES format. Can you predict the binding affinity (pKd or binding free energy) of each molecule docked into the ATP-binding pocket so we can prioritize the top 10 leads for in vitro validation?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) for Protein-Ligand Interaction (e.g., TankBind, GNINA, or EquiBind-derived scoring functions): Can speak to: Quantitative relative ranking of small-molecule binding affinities, predicted binding free energy (ΔG/pKd), and spatial complementary interactions within the defined pocket. Cannot speak to: In vivo efficacy, whole-body pharmacokinetics/ADMET profiles, potential off-target cross-reactivity across the broader kinome, or protein conformational changes (induced fit) beyond the provided static coordinates.

---

## [296] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the LDLR gene (c.1246C>T, p.Arg416Trp) in a patient with suspected familial hypercholesterolemia. Can you predict whether this single-nucleotide alteration is pathogenic or benign?

**ASSISTANT:** Protein language model / structural missense variant effect predictor (e.g., AlphaMissense, ESM-1v): Can evaluate evolutionary conservation, protein structural destabilization, and statistical likelihood of a missense variant being damaging. Cannot assess non-coding or splicing-regulatory impacts, establish clinical penetrance, determine patient-specific disease phenotype/expressivity, or substitute for formal ACMG/AMP clinical guidelines.

---

## [297] source=multitask_sft_big

**USER:** I have an AnnData object containing normalized scRNA-seq expression counts from 15,000 human peripheral blood mononuclear cells (PBMCs). Can you predict the canonical cell types and fine-grained immune subsets for each cell barcoded in this dataset?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer fine-tuned for cell-type classification): Can speak to: Accurately mapping discrete transcriptional profiles to standard cell ontologies, generalizing across distinct sequencing chemistries (e.g., 10x v2 vs. v3), and capturing non-linear gene-gene co-expression dynamics. Cannot speak to: Protein-level phenotype variations, functional TCR/BCR antigen binding specificities, spatial tissue localization, or reliably classifying novel, transitional, or disease-specific cell states that were unrepresented in the pretraining and fine-tuning reference datasets.

---

## [298] source=multitask_sft_big

**USER:** Here is the FASTA sequence for an uncharacterized bacterial enzyme: 'MKVLWAALLVTFLAGCQAKVEQAVETEPEPELRQQ...'. Can you generate its predicted 3D atomic coordinates (PDB format) and provide per-residue confidence scores?

**ASSISTANT:** Deep learning-based protein structure prediction models (e.g., AlphaFold2, ESMFold): Can reliably predict static 3D coordinates (backbone and side chains), secondary structure elements, tertiary domain folds, and local/global confidence metrics (pLDDT, PAE) to identify structured versus intrinsically disordered regions. Cannot reliably model dynamic conformational transitions/ensembles, real-time folding pathways, enzyme kinetics/catalytic rates, or the structural effects of non-protein cofactors, ligands, and post-translational modifications unless explicitly trained on multimolecular complexes.

---

## [299] source=multitask_sft_big

**USER:** We have designed 35 novel small-molecule analogs targeting the catalytic site of human CDK2 (PDB ID: 1HCK). Given the 3D structure of the kinase and the SMILES strings of these candidates, can you predict their binding affinities (pK_d or Delta G) to prioritize the top 5 compounds for synthesis and surface plasmon resonance (SPR) assays?

**ASSISTANT:** 3D Equivariant Graph Neural Network / Structure-Based Scoring Function (e.g., TankBind, GNINA, or PLANET): Can speak to: Relative binding ranking, estimated thermodynamic affinity values (pK_d, pK_i, or Delta G), and structural pose viability based on geometric complementarity and non-covalent interactions (hydrogen bonds, pi-stacking, steric clash avoidance). Cannot speak to: Covalent binding mechanisms, binding/unbinding kinetics (k_on and k_off rates), explicit thermodynamic entropy changes without molecular dynamics, induced-fit protein dynamics far outside the crystallized conformation, or downstream functional efficacy, cell permeability, and ADMET profiles.

---

## [300] source=multitask_sft_big

**USER:** Here is the FASTA sequence for an uncharacterized kinase domain from a newly sequenced fungal isolate: 'MAPRLLVL...'. Can you predict its high-resolution 3D tertiary fold and identify which regions are modeled with high confidence?

**ASSISTANT:** Attention-based end-to-end protein structure prediction model (e.g., AlphaFold2, ESMFold): Can determine static 3D atomic coordinates (PDB format), backbone and side-chain orientations, overall tertiary fold, and local prediction reliability via per-residue confidence scores (pLDDT) and Predicted Aligned Error (PAE). Cannot model dynamic conformational landscapes, real-time folding kinetics, solvent/pH-dependent conformational changes, or the structural effects of post-translational modifications and bound small-molecule ligands without specialized multi-state/all-atom architectures.

---

## [301] source=multitask_sft_big

**USER:** I have a library of 1,500 drug-like small molecules as SMILES strings. Can you predict their aqueous solubility (LogS) and physiological lipophilicity (LogD at pH 7.4) to help us triage candidates for oral bioavailability?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Chemical Foundation Transformer (e.g., ChemBERTa, Uni-Mol) fine-tuned on ADMET benchmarks: Can speak to: Fast in silico estimation and relative ranking of equilibrium aqueous solubility and LogD for small organic molecules within drug-like chemical space. Cannot speak to: Physical formulation impacts (polymorphs, particle size, crystalline vs. amorphous forms), non-standard conditions (unusual buffers, extreme pH, complex biological matrices), or molecules outside the training domain (large peptides, metal complexes, covalent aggregates).

---

## [302] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human CDK2 (PDB ID: 1HCK) and a library of 50 novel sulfonamide derivatives in SMILES format. Can you predict the binding affinity (pIC50 or Kd) of these compounds against the CDK2 ATP-binding pocket and rank-order them for synthesis?

**ASSISTANT:** Structure-Aware 3D Graph Neural Network (e.g., TankBind, GNINA, EquiBind): Can speak to: relative binding affinity ranking, high-throughput virtual screening enrichment, and identification of key residue-level spatial contacts in a static complex conformation. Can't speak to: rigorous absolute thermodynamic free energies (enthalpic/entropic balance, explicit solvent effects), protein conformational flexibility/allosteric induced-fit effects, binding kinetics (kon/koff rates), or covalent reaction mechanisms.

---

## [303] source=multitask_sft_big

**USER:** I have an uncharacterized 240-residue sequence from an extremophile bacterium: 'MKTIIALSYIFCLVFAQD...'. Can you predict its 3D tertiary structure and generate the atomic coordinates in PDB format so I can visualize potential active site pockets?

**ASSISTANT:** Attention-based end-to-end protein structure prediction model (e.g., AlphaFold2, ESMFold): Can predict static 3D Cartesian coordinates (backbone and side-chain atoms) and provide residue-level confidence metrics (pLDDT, PAE). Cannot simulate time-resolved folding dynamics, compute thermodynamic kinetics, accurately model novel cofactors/ligands without specialized multi-modal inputs, or reliably resolve intrinsically disordered regions.

---

## [304] source=multitask_sft_big

**USER:** I have the 3D crystal structure of human CDK2 (PDB ID: 1HCK) and a series of 30 novel small-molecule kinase inhibitors as SMILES strings. Can you predict the absolute binding affinity (pKd or delta G in kcal/mol) for each ligand docked into the ATP-binding site and rank the top candidates for subsequent synthesis?

**ASSISTANT:** Structure-Based Equivariant Graph Neural Network (e.g., TankBind, GNINA, or EquiBind-derived scoring models): It can estimate relative binding affinities, predict protein-ligand contact interactions, and rank candidate congeners based on geometric and physicochemical complementarity within the target pocket. It cannot reliably predict kinetic parameters (residence time, Kon/Koff), account for large induced-fit conformational changes not captured in the input structure, guarantee true thermodynamic delta G (due to approximations in explicit desolvation and entropy), or assess downstream cell permeability, ADMET profiles, and off-target cross-reactivity.

---

## [305] source=multitask_sft_big

**USER:** I have the amino acid sequence of a putative novel esterase from a metagenomic sample: 'MNIFEMLRIDERLRLKIYKDTEGYYTIGIGHLLTKSPSLNAAKSELDKAIGRNT...'. Can you predict the 3D atomic coordinates in PDB format, along with per-residue confidence scores (pLDDT) and a predicted aligned error (PAE) matrix to check inter-domain confidence?

**ASSISTANT:** AlphaFold2 / ESMFold (Deep Learning-based Protein Structure Prediction Models): Can speak to: High-accuracy static 3D Cartesian coordinates (backbone and side chains), secondary and tertiary fold topologies, local residue confidence metrics (pLDDT), and relative inter-domain orientation reliability (PAE). Cannot speak to: Conformational dynamics and folding pathways over time, explicit thermodynamics/kinetics (e.g., kcat, Km, folding free energy), non-standard post-translational modifications (PTMs), or conformational changes driven by unmodeled cofactors, ions, and small-molecule ligands.

---

## [306] source=multitask_sft_big

**USER:** Here is the SMILES string for our lead compound: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'. Could you predict its aqueous solubility (LogS) and distribution coefficient (LogD at pH 7.4) to help us evaluate its oral bioavailability profile?

**ASSISTANT:** Pretrained Molecular Graph Neural Network / Chemical Language Model (e.g., ChemBERTa-2 or Chemprop D-MPNN fine-tuned on ADMET/physicochemical property datasets): Can speak to: Quantitative scalar predictions (LogS, LogD), standard error bounds, relative property ranking compared to known drug-like training chemical spaces, and structural substructure/atom-attribution for lipophilicity and solubility. Cannot speak to: Real-world physical variations (polymorph-dependent crystal lattice energy, particle size, salt form differences), dynamic temperature/pH buffer anomalies outside standard assay conditions, formulation/excipient solubility effects, or non-equilibrium dissolution kinetics.

---

## [307] source=multitask_sft_big

**USER:** I have the amino acid sequence for a newly isolated bacterial esterase: MKTIIALSYIFCLVFAADYKDDDDK... Could you generate its 3D atomic coordinates (PDB file) and evaluate the structural confidence around the catalytic triad?

**ASSISTANT:** Evoformer-based Protein Structure Prediction Model (e.g., AlphaFold2) / Protein Language Model Folder (e.g., ESMFold): Can accurately predict static ground-state 3D coordinates, backbone and side-chain conformations, domain architecture, and provide per-residue prediction confidence scores (pLDDT) and pairwise alignment errors (PAE). Cannot speak to folding kinetics/pathways, continuous thermodynamic conformational dynamics under physiological conditions, or the structural effects of unmodeled post-translational modifications, small-molecule cofactors, or environmental solvent conditions (e.g., pH, ionic strength).

---

## [308] source=multitask_sft_big

**USER:** I have an AnnData object containing normalized scRNA-seq expression counts from a human PBMC sample generated via 10x Chromium. Can you use a pretrained foundation model to predict and annotate the discrete cell type labels for each individual cell?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer): Can speak to: automated zero-shot or fine-tuned classification of canonical and standard immune cell types represented in reference cell atlases, resolving batch effects across standard sequencing platforms, and contextualizing gene co-expression patterns. Cannot speak to: confidently identifying entirely novel, rare, or diseased cell states absent from its training distribution; determining dynamic functional responses or spatial tissue context; or substituting for wet-lab lineage tracing and orthogonal validation.

---

## [309] source=multitask_sft_big

**USER:** We identified a novel heterozygous missense variant in the BRCA1 gene (c.5095C>T, p.Arg1699Trp) in a patient with a family history of breast cancer. Can you evaluate whether this amino acid substitution is pathogenic or benign and estimate its impact on protein function?

**ASSISTANT:** AlphaMissense (Structural and Evolutionary Deep Learning Variant Predictor): Can speak to: categorical classification (likely benign, ambiguous, likely pathogenic) and continuous pathogenicity scores for single amino acid substitutions (missense variants) in human proteins based on evolutionary conservation and 3D structural context. Cannot speak to: non-coding mutations, synonymous changes, frame-shifts, insertions/deletions, gene-gene interactions, variant penetrance, patient-specific disease manifestation, or direct clinical treatment decisions.

---

## [310] source=multitask_sft_big

**USER:** I identified a novel de novo missense mutation in SCN1A (chr2:165999023 A>G, p.Met1528Val) in a pediatric patient with early-onset intractable seizures. Can you evaluate whether this variant is pathogenic and likely causative of Dravet syndrome?

**ASSISTANT:** AlphaMissense (Supervised deep learning-based missense variant effect predictor built on AlphaFold): It can accurately predict the probability that a human missense variant alters protein structural integrity or biochemical function and classifies it into categorical bins (likely benign, ambiguous, or likely pathogenic) based on structural biology and evolutionary conservation. It cannot evaluate non-coding, frameshift, or splice-site alterations; predict gene-specific clinical penetrance or patient phenotype severity; replace ACMG/AMP clinical variant classification guidelines; or account for compound heterozygous or modifier genetic backgrounds.

---

## [311] source=multitask_sft_big

**USER:** I have the crystallized apo structure of human CDK2 (PDB: 1HCK) and a series of 25 novel pyrazole-based small-molecule derivatives provided as SMILES strings. Can you predict the binding affinity (pKd values) of these ligands against CDK2 to help prioritize compounds for synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (E-GNN) / Structure-Based Multimodal Deep Learning Model (e.g., TankBind, GNINA, or PIGNet): Can speak to: predicting static thermodynamic binding strength (e.g., pKd, pKi, or ΔG), ranking relative compound affinities within homologous series, and identifying favorable spatial and steric interactions between protein residues and ligand atoms. Can't speak to: binding kinetics (on/off rates like k_on and k_off), large induced-fit structural rearrangements not captured in the static receptor input, allosteric regulation, cellular permeability/ADMET properties, or precise binding thermodynamics that require explicit solvent/entropic free energy perturbation (FEP) calculations.

---

## [312] source=multitask_sft_big

**USER:** We have generated docked complexes for a library of 20 novel small-molecule inhibitors in the ATP-binding site of human CDK2. Can you run these protein-ligand structures through a model to predict their binding affinities (pKd/pKi) and rank the candidates for lead optimization?

**ASSISTANT:** 3D Equivariant Graph Neural Network (EGNN) / Structure-Based Deep Learning Scoring Function (e.g., GNINA, TankBind): Can speak to: Predicting relative and absolute binding affinity values (pKd, pKi, or affinity scores) and identifying key spatial residue-ligand interactions from 3D atomic coordinates. Cannot speak to: Binding kinetics (association/dissociation rates like kon and koff), explicit solvent entropy/thermodynamics, conformational flexibility or large induced-fit shifts absent from the static input pose, and off-target kinome selectivity.

---

## [313] source=multitask_sft_big

**USER:** I am working on lead optimization and need to estimate the aqueous solubility (logS) and distribution coefficient (logD at pH 7.4) for our candidate molecule. Here is the SMILES string: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5. Can you predict these properties?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) / Chemprop or Molecular Graph Transformer pretrained on ChEMBL/PubChem: Can speak to: Estimated relative in silico physicochemical values (logS, logD) based on 2D chemical structure, molecular graphs, and historical training data distributions (e.g., ChEMBL, ESOL). Cannot speak to: Experimental crystal packing/polymorphism influences on solubility, non-standard formulation excipient interactions, temperature-dependent variations, or downstream in vivo pharmacokinetics and metabolic clearance without separate specialized models.

---

## [314] source=multitask_sft_big

**USER:** I have a raw UMI count matrix from a droplet-based single-cell RNA sequencing (10x Genomics) experiment on human peripheral blood mononuclear cells (PBMCs). Could you identify and assign specific cell-type labels to each cell cluster or individual barcode based on their gene expression profiles?

**ASSISTANT:** Single-cell Foundation Transformer (e.g., scGPT or Geneformer fine-tuned for cell-type annotation): It can accurately predict canonical cell types, map transcriptional profiles to standardized cell ontologies, and handle batch variation across common tissues present in large-scale training atlases. It cannot infer spatial organization or microenvironment context from dissociated data alone, detect entirely novel cell lineages not represented in reference data, or confirm post-transcriptional protein expression, functional activation states, or downstream clinical significance.

---

## [315] source=multitask_sft_big

**USER:** We have synthesized a series of 30 novel small-molecule kinase inhibitors as SMILES strings. Before advancing to in vitro assays, can you run an in silico ADMET profiling to flag potential cardiac toxicity via hERG liability, evaluate inhibition across major metabolizing enzymes (CYP3A4, CYP2D6, CYP2C9), and estimate percentage human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Message Passing Neural Network (D-MPNN / Chemprop) or Pretrained Molecular Transformer fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: Fast, 2D structure-based empirical risk categorization, relative ranking within chemical series, binary liabilities (e.g., hERG blocker vs. non-blocker at standard cutoff concentrations, CYP inhibitor status), and baseline oral bioavailability score estimates based on structural descriptors and learned representations. Cannot speak to: Absolute in vivo pharmacokinetic profiles, non-linear dose-dependent clearance, formulation and food-effect impacts, active transporter interactions (e.g., complex P-gp/OATP efflux/uptake interplay), species-specific systemic toxicity, or reliable predictions for novel chemical scaffolds far outside the model's training applicability domain without experimental validation.

---

## [316] source=multitask_sft_big

**USER:** I have the 3D docked poses of 50 novel heterocyclic small-molecule candidates against the human CDK2 binding pocket in PDB/SDF format. Can you predict their binding affinity (in pKd or delta G) so we can rank and select the top 5 for chemical synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network / Geometric Deep Learning (e.g., TankBind, PIGNet, GNINA scoring function): Can speak to: Relative binding ranking, continuous affinity scores (e.g., pKd, pKi, or kcal/mol), and spatial interaction energetics based on 3D contact geometry. Cannot speak to: Binding kinetics (kon/koff rates), solvent entropy/thermodynamic dynamics, receptor conformational changes (induced-fit effects not captured in static poses), or downstream ADMET and in vivo efficacy.

---

## [317] source=multitask_sft_big

**USER:** We identified a novel de novo missense mutation in SCN1A (c.4943G>A, p.Arg1648His) from whole exome sequencing in a pediatric patient with refractory seizures. Can you predict whether this variant is likely pathogenic or benign?

**ASSISTANT:** AlphaMissense (or deep learning missense pathogenicity predictor): Can evaluate the likelihood of single amino acid substitutions disrupting protein function based on evolutionary conservation and structural context; cannot evaluate non-coding, frameshift, or splicing variants, nor can it determine patient-specific penetrance, inheritance patterns, or establish definitive clinical diagnosis without experimental/clinical evidence.

---

## [318] source=multitask_sft_big

**USER:** I have an uncharacterized 320-amino-acid enzyme sequence from a newly isolated marine bacterium: 'MKTIIALSYIFCLVFA...'. Can you predict its 3D tertiary structure, output a PDB file with atomic coordinates, and provide per-residue confidence scores to identify potential catalytic domains?

**ASSISTANT:** Deep learning-based biomolecular structure prediction model (e.g., AlphaFold2, ESMFold): Can accurately predict static single-state 3D Cartesian coordinates (tertiary and quaternary structure) and estimate local and global structural confidence (e.g., pLDDT, PAE). Cannot reliably speak to dynamic conformational ensembles, transition pathways, the functional impact of point mutations on stability/activity without specialized tuning, explicit ligand-binding kinetics, or post-translational modifications.

---

## [319] source=multitask_sft_big

**USER:** I have an AnnData (.h5ad) object containing normalized single-cell RNA-seq expression profiles from human peripheral blood mononuclear cells (PBMCs). I need an automated pipeline to predict fine-grained cell-type labels for each individual cell barcode without performing manual marker gene curation.

**ASSISTANT:** Single-cell foundation transformer (e.g., scGPT or Geneformer fine-tuned for cell-type classification): {'can_speak_to': ['Discrete cell-type and sub-lineage identity mapped to learned reference ontologies (e.g., Cell Ontology terms)', 'High-dimensional transcriptional state embeddings and cell clustering based on gene expression patterns', 'Relative confidence or probability scores for predicted known cell categories across diverse sequencing batches'], 'cannot_speak_to': ['Unseen, novel, or disease-specific cell types absent from the pretraining and fine-tuning reference sets (often forced into the nearest known category)', 'Proteomic, epigenetic, or post-translational ground truth unless multi-modal data is explicitly integrated', 'Spatial localization or tissue microenvironment dynamics from dissociated single-cell data alone']}

---

## [320] source=multitask_sft_big

**USER:** I have an AnnData (.h5ad) file containing raw count scRNA-seq profiles from roughly 25,000 human peripheral blood mononuclear cells (PBMCs) sequenced via 10x Genomics v3. Could you automatically predict and assign cell-type annotations to each cell without requiring manual marker-gene curation?

**ASSISTANT:** scGPT (Single-cell Generative Pretrained Transformer) fine-tuned for cell-type annotation: Can accurately map gene expression patterns to discrete reference cell types across known hematologic and immune lineages, generalize across batches, and identify subtle transcriptomic subtypes represented in its reference atlas. Cannot reliably classify entirely novel or unseen pathological cell states, resolve continuous developmental transitions into rigid discrete bins, infer spatial tissue context, or distinguish true biological phenotypes from severe uncorrected technical artifacts (e.g., high-droplet ambient RNA contamination or unflagged doublets).

---

## [321] source=multitask_sft_big

**USER:** I have the PDB structure of human CDK2 (crystallized with an ATP-competitive ligand) and a library of 150 novel purine analogs in SMILES format. Can you predict their binding affinities (pKd or delta G) against the CDK2 active site to prioritize candidates for wet-lab synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (e.g., TankBind, GNINA, or Uni-Mol for structure-based binding affinity prediction): Can rapidly predict numerical binding affinity scores (e.g., pKd, pIC50) and rank relative binding potencies based on learned 3D geometric and physicochemical complementarity. Cannot definitively model large-scale induced-fit conformational dynamics, explicit solvent entropy/thermodynamic pathways, or predict downstream functional efficacy, cell membrane permeability, and ADMET profiles.

---

## [322] source=multitask_sft_big

**USER:** I have five novel small-molecule kinase inhibitor candidates (provided as SMILES strings) in lead optimization. Can you predict their ADMET profiles, specifically hERG cardiotoxicity liability (IC50 < 10 µM), inhibition against major CYP enzymes (CYP3A4, CYP2D6, CYP2C9), and expected human oral bioavailability (%F)?

**ASSISTANT:** Multi-Task Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks: Can speak to: Quantitative/binary statistical likelihood of hERG channel blockade, CYP450 isoform-specific competitive inhibition probabilities, and empirical rankings of oral bioavailability based on structure-property relationships learned from historical in vitro assays and pharmacokinetic datasets. Cannot speak to: Full dynamic Physiologically Based Pharmacokinetic (PBPK) profiles over time, formulation-dependent absorption mechanics (e.g., crystalline form, excipient effects), downstream reactive metabolite formation, or idiosyncratic human toxicities.

---

## [323] source=multitask_sft_big

**USER:** I have a library of 150 novel small-molecule kinase inhibitors represented as SMILES strings. Can you predict their aqueous solubility (LogS) and distribution coefficient (LogD at pH 7.4) to help prioritize candidates for downstream pharmacokinetic and oral bioavailability screening?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN) fine-tuned for ADMET molecular property prediction (e.g., Chemprop / MolNet-based architectures): Can speak to: predicting thermodynamic/kinetic solubility and LogD values directly from 2D molecular graph topology, ranking analogs by relative lipophilicity and polarity, and identifying substructures driving poor solubility. Can't speak to: solid-state polymorph effects and crystal lattice energy differences, dynamic formulation/co-solvent behavior, precipitation kinetics in complex biological media, or pH dependency outside the fixed pH (7.4) training distribution.

---

## [324] source=multitask_sft_big

**USER:** We identified a novel missense variant, NM_007294.4:c.5095C>T (p.Arg1699Trp), in the BRCA1 gene in a patient with early-onset breast cancer. Can you predict whether this variant is likely pathogenic or benign based on protein structure and evolutionary conservation?

**ASSISTANT:** Evolutionary Protein Language Models / Deep Learning Missense Variant Predictors (e.g., AlphaMissense, ESM-1v, EVE): {'can_speak_to': ['Likelihood of functional disruption caused by single amino acid substitutions (missense mutations)', 'Evolutionary constraint and cross-species conservation at the specific residue position', 'Structural tolerance and biophysical impact of the substitution on protein stability'], 'cannot_speak_to': ['Non-coding, synonymous, frameshift, or splice-altering variants not primarily affecting protein sequence', 'Clinical penetrance, expressivity, age-of-onset, or patient-specific disease outcomes', 'Full ACMG/AMP clinical classification, which requires orthogonal evidence such as population allele frequency, family segregation, and validated in vitro functional assays']}

---

## [325] source=multitask_sft_big

**USER:** I have the solved 3D crystal structure of human CDK2 (PDB ID: 1HCK) and a library of 120 novel purine-based small molecule analogs in SMILES format. Can you predict the binding affinity (expressed as pKd or pIC50) for each compound docked into the ATP-binding pocket so we can prioritize top candidates for in vitro synthesis and testing?

**ASSISTANT:** Equivariant 3D Graph Neural Network (3D-GNN) for Protein-Ligand Scoring and Affinity Prediction: Can speak to: Relative binding ranking, estimated binding free energies (Kd/Ki/IC50) for rigid or semi-rigid docked poses, and structural interaction hotspots (e.g., hydrogen bonding and hydrophobic contacts). Cannot speak to: In vivo efficacy, downstream pharmacokinetics/ADMET profiles, off-target promiscuity/selectivity across the full proteome, solvent/entropic effects requiring extensive molecular dynamics, or chemical synthetic feasibility.

---

## [326] source=multitask_sft_big

**USER:** I have an AnnData object containing 10x Genomics 3' single-cell RNA-seq raw count matrices from human peripheral blood mononuclear cells (PBMCs). Could you identify and annotate the specific cell types and immune subsets (e.g., distinguishing CD4+ naive T cells from memory T cells, and classical vs. non-classical monocytes) for each cell in this dataset?

**ASSISTANT:** scGPT (Single-Cell Generative Pretrained Transformer): It can accurately predict known discrete cell types, resolve fine-grained immune cell subsets using contextual gene-gene interaction embeddings, and normalize across technical batch effects. It cannot reliably determine post-transcriptional protein abundance or spatial context, infer functional activation states unrepresented in its training ontology, or classify entirely novel or aberrantly altered disease-specific cell types without misassigning them to the nearest known reference class.

---

## [327] source=multitask_sft_big

**USER:** I have designed a series of small-molecule drug candidates. Can you predict the aqueous solubility (logS) and the distribution coefficient at physiological pH (logD at pH 7.4) for this lead compound using its SMILES string: 'CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5'?

**ASSISTANT:** Directed Message Passing Neural Network (D-MPNN, e.g., Chemprop) fine-tuned on ADMET benchmark datasets: It can estimate thermodynamic aqueous solubility (logS) and lipophilicity/distribution coefficients (logD) based on 2D chemical structure, functional group environments, and empirical ADMET data distributions. It cannot account for solid-state crystal lattice energy, polymorph formation, dissolution kinetics, formulation/excipient effects, or experimental temperature/salt-buffer variations not represented in the training data.

---

## [328] source=multitask_sft_big

**USER:** We have docked 45 novel small-molecule kinase inhibitors into the ATP-binding site of human EGFR (PDB: 7A2A). Could you predict their binding affinities (expressed as pKd or pIC50) using the 3D complex coordinates so we can prioritize the top five compounds for wet-lab synthesis?

**ASSISTANT:** 3D Equivariant Graph Neural Network (3D-EGNN) for protein-ligand complexes: Can speak to: Relative binding affinity ranking, continuous affinity values (e.g., pKd, pIC50, or Delta-G) derived from spatial atom configurations, and geometric fit within the active pocket. Cannot speak to: Dynamic induced-fit conformational shifts, free-energy contributions from explicit solvent displacement, functional efficacy (e.g., agonist versus antagonist effects), off-target selectivity across the wider kinome, or ADMET/pharmacokinetic profiles.

---

## [329] source=multitask_sft_big

**USER:** We are optimizing a small-molecule kinase inhibitor series and need to screen our top lead (SMILES: CC1=C(C=C(C=C1)NC(=O)C2=CC=C(C=C2)CN3CCN(CC3)C)NC4=NC=CC(=N4)C5=CN=CC=C5). Can you predict its cardiotoxicity risk via hERG inhibition, determine its potential to inhibit major CYP enzymes (specifically CYP3A4 and CYP2D6), and estimate its human oral bioavailability percentage?

**ASSISTANT:** Pretrained Multi-Task Directed Message Passing Neural Network (D-MPNN / Chemprop) or Molecular Graph Transformer fine-tuned on Therapeutics Data Commons (TDC) ADMET benchmarks.: Can predict categorical and regression scores for standard in vitro ADMET endpoints (hERG IC50/blockade probability, specific CYP450 isozyme inhibition, and categorized oral bioavailability) based on small-molecule 2D topological structures within its chemical training space. Cannot model complex, time-dependent in vivo pharmacokinetic parameters (Cmax, Tmax, AUC), physiological multi-compartment dynamics, formulation/solubility-limited absorption effects, or toxicity mediated by reactive in vivo metabolites.

---

