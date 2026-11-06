"""Tier audit decisions (workstream K, 2026-10-29, after the coordinator's reconciliation request).

RULE (stated here once, applied to every entry): the tier follows the PROVENANCE OF THE QUOTED STATEMENT, not the article type.
  T1  the quote reports a result or method obtained in the source's own experiment, simulation, benchmark or data analysis
      (article type is irrelevant: a review that analyses its own dataset can yield T1; a research article that restates cited work yields T2).
  T2  the quote is a review summary of other people's work, a restatement of a result the source cites to another paper, a textbook rule,
      authors' background or motivation, or a project goal. The cited primary study was NOT opened by workstream K unless stated.
  When the stored text does not let us establish that a number is the source's own result, the default is T2.
Weight eligibility depends only on tier in {T1, T2} (plus verified quote, kind, direction, computable feature), so tier moves between T1 and
T2 do not change eligibility; they change provenance reporting only.

CHANGES = {entry_id: (tier_before, tier_after, quote_character, reason)}   # entries not listed keep their tier
CHARACTER for every T2 entry is recorded in T2_CHARACTER below.
"""
CHANGES = {
    # T1 -> T2: the quoted sentence restates a result or limit that the source cites to other work
    "LIT-3DPSA-001": ("T1", "T2", "restates_cited_primary_result", "'reported to correlate better to permeability than MW, TPSA, cLogP' summarises prior reports; the source's own work follows ('we therefore characterized')"),
    "LIT-EPSA-001": ("T1", "T2", "restates_cited_primary_result", "the 90 A^2 EPSA limit 'has been reported' elsewhere; only griselimycin's 74 A^2 is the source's own value"),
    "LIT-NMEPOS-002": ("T1", "T2", "restates_cited_primary_result", "'was previously observed in N-methylated analogues of sanguinamide' refers to an earlier study"),
    "LIT-SIZE-001": ("T1", "T2", "restates_cited_primary_result", "the size dependence of fully N-methylated 8-10-mers is described as 'observed in a study' by Pye et al. 2017 (cited), not measured in this paper"),
    "LIT-NME-006": ("T1", "T2", "restates_cited_primary_result", "source is a review; the 30-member N-methylated library with Caco-2 4e-6 cm/s is an earlier study described in the review (refs 8, 9, 11 near the quote)"),
    "LIT-IMHB-004": ("T1", "T2", "restates_cited_primary_result", "aMD donor-contribution vs PAMPA correlation is followed by citation 109 (earlier work); permeability values come from the experimental study it cites"),
    "LIT-NME-003": ("T1", "T2", "restates_cited_primary_result", "the PAMPA values of the 47-macrocycle set are taken from the cited experimental study (ref 109 in the adjacent sentence); the paper's own contribution is the simulation"),
    "LIT-CHAM-002": ("T1", "T2", "uncertain_default_T2", "the stored text does not state that the PROTAC permeability comparison (20-fold / ~1000-fold) was measured in this paper; no citation marker either; default rule -> T2"),
    "LIT-OB-001": ("T1", "T2", "project_goal", "'we focused our optimization on improving oral bioavailability with a target of >=20%' is a design goal, not a measured result"),
    # T2 -> T1: the quoted statement is the source's own data analysis although the article type is review / data paper
    "CARD-MACRODRUG-001": ("T2", "T1", "own_analysis", "review analysed FDA-approved macrocycles, clinical candidates and ChEMBL macrocycles itself ('We have analyzed ...'); quotes are its own findings"),
    "LIT-CLIN-002": ("T2", "T1", "own_analysis", "CAS Content Collection analysis performed by the source ('Our analysis shows', MW-PSA plot): polarity distribution result"),
    "LIT-CLIN-003": ("T2", "T1", "own_analysis", "MW distribution of the analysed cyclic-peptide data set, stratified by ring size and topology (Supplementary Figure S7)"),
    "LIT-PEP-001": ("T2", "T1", "own_analysis", "data paper's own descriptor comparison of cyclic peptides vs nonpeptidic macrocycles in its database (Fig. 4)"),
}

# Character of every entry that is T2 AFTER the changes (a restatement/background/goal statement of the stated kind).
T2_CHARACTER = {
    "CARD-ROMI-001": ("review_own_wording", "review's description of a clinical case (romidepsin) and of earlier SAR work; no data of its own"),
    "LIT-BRO5-005": ("restates_cited_primary_result", "AB-MPS cutoff 'was found' in an earlier AbbVie study (ref 4)"),
    "LIT-BRO5-006": ("restates_cited_primary_result", "Kihlberg-group heuristic criteria 'established' in earlier work (refs 1, 14-16)"),
    "LIT-CHAM-001": ("restates_cited_primary_result", "'was recently reported to provide up to a 2-fold improvement in oral absorption' (earlier report)"),
    "LIT-CYC-001": ("author_background", "introduction of the C2PO paper: chameleonic explanation of cyclic vs linear permeability"),
    "LIT-CYC-002": ("review_own_wording", "review's mechanistic summary (refs 26-34)"),
    "LIT-HBD-001": ("author_background", "authors' remark on HBD count and macrocycle size being detrimental, in discussion of their analogues"),
    "LIT-LIAB-001": ("author_background", "introduction: Gln glutarimide deamidation kinetics (refs 13, 14)"),
    "LIT-NCAA-001": ("author_background", "limitations paragraph of a generative-design paper"),
    "LIT-NH-002": ("author_background", "introduction of the benchmarking paper (refs 8-11)"),
    "LIT-NME-007": ("review_own_wording", "review's literature summary preceding 'Our analysis shows'"),
    "LIT-NMEPOS-003": ("restates_cited_primary_result", "small-molecule position-dependent methylation examples described in a review (Table of earlier studies)"),
    "LIT-POL-002": ("restates_cited_primary_result", "commentary summarising the POL rules of the PEGASUS paper (the commentary is not a data paper)"),
    "LIT-RO5-001": ("textbook_rule", "Lipinski rule of 5 as stated in the introduction of a data-analysis paper"),
    "LIT-SD-001": ("review_own_wording", "review summary of lipophilicity-permeability correlation (Overton's rule)"),
    "LIT-SIZE-003": ("author_background", "introduction of the Keap1-Nrf2 paper (refs 8-10): cyclosporine example"),
    "LIT-STAB-002": ("review_own_wording", "review summary of modifications that reduce HBD and proteolytic susceptibility"),
    "LIT-STAB-003": ("review_own_wording", "review summary of cyclization effects"),
    "LIT-STAB-004": ("restates_cited_primary_result", "half-life data of M2pep variants from a follow-up study (ref 51) described in a review"),
    "LIT-STAB-005": ("restates_cited_primary_result", "MiniAp-4 lactam vs disulfide half-lives from an earlier study, shown in a review figure"),
    "LIT-STAB-006": ("review_own_wording", "review's comparison of cyclization vs retro-enantio strategies"),
    "LIT-STAB-007": ("review_own_wording", "review's mechanism-level statement on N-methylation"),
    "LIT-STAB-008": ("restates_cited_primary_result", "Lip7 D-amino-acid half-life gain from cited studies (refs 67, 68)"),
    "LIT-STAB-009": ("review_own_wording", "review's mechanistic rationale for stapling and proteolysis"),
    "LIT-STAB-011": ("restates_cited_primary_result", "monocyclic -> bicyclic hit-to-lead result of the MK-0616 campaign (ref 9), in the introduction"),
    "LIT-TPSA-002": ("review_own_wording", "review's statement of the classical TPSA > 140 A^2 guideline (Fernandes and Gattass 2009 cited)"),
    "LIT-TRADE-001": ("review_own_wording", "review's general statement on the solubility-permeability trade-off"),
}
