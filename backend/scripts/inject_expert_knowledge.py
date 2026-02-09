#!/usr/bin/env python3
"""
Inject expert domain knowledge into tool_knowledge recommended_parameters.

Reads JSON files from domain_knowledge/ directory and maps topics to actual
biomni tool IDs, then updates the recommended_parameters field with
situation-aware parameter guidance.
"""

import json
import os
import sqlite3
import sys
from pathlib import Path

# Mapping from knowledge topic keys to biomni tool IDs
# Each topic can map to multiple tools
TOPIC_TO_TOOLS = {
    # === Genomics ===
    "gsea_enrichment_analysis": [
        "biomni/genomics/gene_set_enrichment_analysis",
        "biomni/genomics/get_gene_set_enrichment_analysis_supported_database_list",
    ],
    "chip_seq_peak_calling_macs2": [
        "biomni/genomics/perform_chipseq_peak_calling_with_macs2",
    ],
    "motif_enrichment_homer": [
        "biomni/genomics/find_enriched_motifs_with_homer",
    ],
    "scrna_seq_integration": [
        "biomni/genomics/create_harmony_embeddings_scRNA",
        "biomni/genomics/create_scvi_embeddings_scRNA",
        "biomni/genomics/unsupervised_celltype_transfer_between_scRNA_datasets",
    ],
    "cell_type_annotation_scrnaseq": [
        "biomni/genomics/annotate_celltype_scRNA",
        "biomni/genomics/annotate_celltype_with_panhumanpy",
        "biomni/genomics/map_to_ima_interpret_scRNA",
    ],
    "protein_language_models_esm2": [
        "biomni/genomics/generate_gene_embeddings_with_ESM_models",
        "biomni/genomics/generate_transcriptformer_embeddings",
        "biomni/genomics/generate_embeddings_with_state",
    ],
    "crispr_guide_design": [
        "biomni/molecular_biology/design_knockout_sgrna",
        "biomni/molecular_biology/crispr_gene_editing_design_pipeline",
        "biomni/bioengineering/perform_crispr_cas9_genome_editing",
        "biomni/genetics/analyze_crispr_genome_editing",
        "biomni/genetics/analyze_cas9_mutation_outcomes",
    ],
    "atac_seq_analysis": [
        "biomni/immunology/analyze_atac_seq_differential_accessibility",
    ],
    "tfbs_analysis_jaspar": [
        "biomni/genetics/identify_transcription_factor_binding_sites",
    ],
    "genomic_coordinate_liftover": [
        "biomni/genetics/liftover_coordinates",
    ],

    # === Molecular Biology ===
    "pcr_primer_design": [
        "biomni/molecular_biology/design_primer",
        "biomni/molecular_biology/design_verification_primers",
        "biomni/molecular_biology/pcr_simple",
        "biomni/genetics/perform_pcr_and_gel_electrophoresis",
    ],
    "golden_gate_assembly": [
        "biomni/molecular_biology/golden_gate_assembly",
        "biomni/molecular_biology/design_golden_gate_oligos",
        "biomni/molecular_biology/get_golden_gate_assembly_protocol",
    ],
    "restriction_enzyme_analysis": [
        "biomni/molecular_biology/find_restriction_enzymes",
        "biomni/molecular_biology/find_restriction_sites",
        "biomni/molecular_biology/digest_sequence",
    ],
    "sequence_alignment": [
        "biomni/molecular_biology/align_sequences",
    ],
    "orf_finding": [
        "biomni/molecular_biology/annotate_open_reading_frames",
        "biomni/molecular_biology/find_orfs_in_frame",
        "biomni/molecular_biology/get_coding_sequences",
        "biomni/molecular_biology/get_gene_coding_sequence",
    ],
    "blast_sequence_search": [
        "biomni/database/blast_sequence",
    ],
    "plasmid_annotation": [
        "biomni/molecular_biology/annotate_plasmid",
        "biomni/molecular_biology/get_plasmid_sequence",
    ],
    "mutation_detection": [
        "biomni/molecular_biology/find_sequence_mutations",
    ],
    "codon_optimization": [
        "biomni/synthetic_biology/optimize_codons_for_heterologous_expression",
    ],

    # === Microbiology & Systems Biology ===
    "bacterial_growth_modeling": [
        "biomni/microbiology/model_bacterial_growth_dynamics",
        "biomni/microbiology/bacterial_dynamics",
        "biomni/immunology/analyze_bacterial_growth_curve",
        "biomni/immunology/logistic_growth",
        "biomni/synthetic_biology/analyze_bacterial_growth_rate",
        "biomni/synthetic_biology/gompertz_model",
    ],
    "lotka_volterra_community_dynamics": [
        "biomni/microbiology/simulate_generalized_lotka_volterra_dynamics",
        "biomni/microbiology/glv_equations",
        "biomni/microbiology/microbial_community_dynamics_pipeline",
        "biomni/microbiology/simulate_microbial_population_dynamics",
    ],
    "anaerobic_digestion_adm1": [
        "biomni/microbiology/optimize_anaerobic_digestion_process",
        "biomni/microbiology/methane_yield_model",
        "biomni/microbiology/vfa_production_model",
    ],
    "flux_balance_analysis": [
        "biomni/systems_biology/perform_flux_balance_analysis",
        "biomni/systems_biology/simulate_metabolic_network_perturbation",
    ],
    "michaelis_menten_kinetics": [
        "biomni/biochemistry/michaelis_menten",
        "biomni/biochemistry/analyze_enzyme_kinetics_assay",
        "biomni/biochemistry/analyze_protease_kinetics",
        "biomni/systems_biology/mass_action_kinetics",
    ],
    "hill_function_dose_response": [
        "biomni/systems_biology/hill_function",
        "biomni/biochemistry/dose_response",
        "biomni/pharmacology/sigmoid",
    ],
    "gene_circuit_design": [
        "biomni/synthetic_biology/gene_circuit_odes",
        "biomni/synthetic_biology/simulate_gene_circuit_with_growth_feedback",
        "biomni/synthetic_biology/circuit_design_pipeline",
        "biomni/synthetic_biology/analyze_bifurcation_diagram",
    ],
    "sbml_model_building": [
        "biomni/synthetic_biology/create_biochemical_network_sbml_model",
    ],
    "rna_secondary_structure_prediction": [
        "biomni/microbiology/predict_rna_secondary_structure",
        "biomni/biochemistry/analyze_rna_secondary_structure_features",
    ],
    "biofilm_quantification_crystal_violet": [
        "biomni/microbiology/quantify_biofilm_biomass_crystal_violet",
    ],
    "circular_dichroism_analysis": [
        "biomni/biochemistry/analyze_circular_dichroism_spectra",
    ],
    "itc_binding_thermodynamics": [
        "biomni/biochemistry/analyze_itc_binding_thermodynamics",
        "biomni/biochemistry/one_site_model",
    ],

    # === Bioimaging & Bioengineering ===
    "nnunet_medical_image_segmentation": [
        "biomni/bioimaging/segment_with_nn_unet",
        "biomni/bioimaging/setup_nnunet_environment",
        "biomni/bioimaging/prepare_input_for_nnunet",
    ],
    "image_registration": [
        "biomni/bioimaging/register_images",
        "biomni/bioimaging/batch_register_images",
        "biomni/bioimaging/create_rigid_transform",
        "biomni/bioimaging/create_affine_transform",
        "biomni/bioimaging/create_deformable_transform",
        "biomni/bioimaging/setup_registration_method",
        "biomni/bioimaging/quick_rigid_registration",
        "biomni/bioimaging/quick_affine_registration",
        "biomni/bioimaging/quick_deformable_registration",
    ],
    "drug_release_kinetics": [
        "biomni/bioengineering/analyze_in_vitro_drug_release_kinetics",
        "biomni/bioengineering/zero_order",
        "biomni/bioengineering/first_order",
        "biomni/bioengineering/higuchi",
        "biomni/bioengineering/korsmeyer_peppas",
        "biomni/bioengineering/exp_decay",
    ],
    "calcium_imaging_analysis": [
        "biomni/bioengineering/analyze_calcium_imaging_data",
        "biomni/pathology/analyze_intracellular_calcium_with_rhod2",
        "biomni/pathology/analyze_endolysosomal_calcium_dynamics" if False else None,
    ],
    "cell_migration_analysis": [
        "biomni/bioengineering/analyze_cell_migration_metrics",
    ],
    "neural_trajectory_decoding": [
        "biomni/bioengineering/decode_behavior_from_neural_trajectories",
    ],
    "myofiber_morphology_analysis": [
        "biomni/bioengineering/analyze_myofiber_morphology",
    ],
    "tissue_deformation_strain_analysis": [
        "biomni/biophysics/analyze_tissue_deformation_flow",
    ],
    "whole_cell_ode_modeling": [
        "biomni/bioengineering/simulate_whole_cell_ode_model",
        "biomni/bioengineering/default_whole_cell_model",
        "biomni/systems_biology/ode_system",
        "biomni/systems_biology/simulate_protein_signaling_network",
        "biomni/systems_biology/simulate_renin_angiotensin_system_dynamics",
    ],

    # === Cell Biology, Immunology, Pathology ===
    "facs_cell_sorting": [
        "biomni/cell_biology/perform_facs_cell_sorting",
        "biomni/cell_biology/analyze_flow_cytometry_immunophenotyping",
    ],
    "flow_cytometry_facs": [  # alias from cellbio_immuno agent
        "biomni/cell_biology/perform_facs_cell_sorting",
        "biomni/cell_biology/analyze_flow_cytometry_immunophenotyping",
    ],
    "cell_cycle_quantification": [
        "biomni/cell_biology/quantify_cell_cycle_phases_from_microscopy",
        "biomni/immunology/estimate_cell_cycle_phase_durations",
    ],
    "cell_cycle_analysis": [  # alias from cellbio_immuno agent
        "biomni/cell_biology/quantify_cell_cycle_phases_from_microscopy",
        "biomni/immunology/estimate_cell_cycle_phase_durations",
    ],
    "cell_motility_tracking": [
        "biomni/cell_biology/quantify_and_cluster_cell_motility",
        "biomni/immunology/track_immune_cells_under_flow",
    ],
    "mitochondrial_morphology_potential": [
        "biomni/cell_biology/analyze_mitochondrial_morphology_and_potential",
    ],
    "cell_senescence_apoptosis": [
        "biomni/cancer_biology/analyze_cell_senescence_and_apoptosis",
    ],
    "cell_senescence_and_apoptosis": [  # alias from cellbio_immuno agent
        "biomni/cancer_biology/analyze_cell_senescence_and_apoptosis",
    ],
    "cfse_cell_proliferation": [
        "biomni/immunology/analyze_cfse_cell_proliferation",
    ],
    "copy_number_analysis": [
        "biomni/cancer_biology/analyze_copy_number_purity_ploidy_and_focal_events",
        "biomni/cancer_biology/norm_chr",
    ],
    "cancer_copy_number_analysis": [  # alias from cellbio_immuno agent
        "biomni/cancer_biology/analyze_copy_number_purity_ploidy_and_focal_events",
        "biomni/cancer_biology/norm_chr",
    ],
    "ddr_network_cancer": [
        "biomni/cancer_biology/analyze_ddr_network_in_cancer",
    ],
    "somatic_mutation_detection": [
        "biomni/cancer_biology/detect_and_annotate_somatic_mutations",
    ],
    "structural_variation_detection": [
        "biomni/cancer_biology/detect_and_characterize_structural_variations",
    ],
    "nmf_gene_expression": [
        "biomni/cancer_biology/perform_gene_expression_nmf_analysis",
    ],
    "nmf_cancer_subtypes": [  # alias from cellbio_immuno agent
        "biomni/cancer_biology/perform_gene_expression_nmf_analysis",
    ],
    "corneal_nerve_quantification": [
        "biomni/pathology/quantify_corneal_nerve_fibers",
    ],
    "hemodynamic_analysis": [
        "biomni/physiology/analyze_hemodynamic_data",
    ],
    "fatty_acid_gc": [
        "biomni/physiology/analyze_fatty_acid_composition_by_gc",
    ],
    "n_glycosylation_prediction": [
        "biomni/glycoengineering/find_n_glycosylation_motifs",
        "biomni/glycoengineering/predict_o_glycosylation_hotspots",
    ],
    "glycosylation_prediction": [  # alias from cellbio_immuno agent
        "biomni/glycoengineering/find_n_glycosylation_motifs",
        "biomni/glycoengineering/predict_o_glycosylation_hotspots",
    ],
    "bone_micro_ct_morphometry": [
        "biomni/pathology/analyze_bone_microct_morphometry",
    ],
    "multiplexed_tissue_imaging": [
        "biomni/pathology/segment_and_quantify_cells_in_multiplexed_images",
    ],
    "western_blot_quantification": [
        "biomni/pharmacology/analyze_western_blot",
    ],
    "amyloid_plaque_quantification": [
        "biomni/physiology/quantify_amyloid_beta_plaques",
    ],
    "cosinor_circadian_analysis": [
        # No direct biomni tool for circadian analysis yet
    ],

    # === Pharmacology ===
    "molecular_docking_vina": [
        "biomni/pharmacology/docking_autodock_vina",
        "biomni/pharmacology/run_autosite",
        "biomni/pharmacology/run_diffdock_with_smiles",
    ],
    "molecular_docking_autodock_vina": [  # alias from pharmacology agent
        "biomni/pharmacology/docking_autodock_vina",
        "biomni/pharmacology/run_autosite",
        "biomni/pharmacology/run_diffdock_with_smiles",
    ],
    "admet_prediction": [
        "biomni/pharmacology/ADMET_pred",
        "biomni/pharmacology/predict_admet_properties",
        "biomni/pharmacology/calculate_physicochemical_properties",
    ],
    "admet_property_prediction": [  # alias from pharmacology agent
        "biomni/pharmacology/ADMET_pred",
        "biomni/pharmacology/predict_admet_properties",
        "biomni/pharmacology/calculate_physicochemical_properties",
    ],
    "pharmacokinetic_modeling": [
        "biomni/pharmacology/bi_exp_model",
        "biomni/physiology/simulate_thyroid_hormone_pharmacokinetics",
        "biomni/physiology/pk_ode_system",
        "biomni/physiology/mono_exp_model",
    ],
    "drug_drug_interaction": [

        "biomni/pharmacology/check_drug_combination_safety",
        "biomni/pharmacology/find_alternative_drugs_ddinter",
        "biomni/pharmacology/analyze_interaction_mechanisms",
    ],
    "drug_drug_interaction_prediction": [  # alias from pharmacology agent

        "biomni/pharmacology/check_drug_combination_safety",
        "biomni/pharmacology/find_alternative_drugs_ddinter",
        "biomni/pharmacology/analyze_interaction_mechanisms",
    ],
    "lead_optimization": [
        "biomni/pharmacology/drug_discovery_screening_pipeline",
    ],
    "virtual_screening": [
        "biomni/pharmacology/drug_discovery_screening_pipeline",
        "biomni/pharmacology/predict_binding_affinity_protein_1d_sequence",
    ],
    "dose_response_fitting": [
        "biomni/biochemistry/dose_response",
        "biomni/pharmacology/sigmoid",
    ],
    "dose_response_curve_fitting": [  # alias from pharmacology agent
        "biomni/biochemistry/dose_response",
        "biomni/pharmacology/sigmoid",
    ],
    "drug_release_kinetics_pharma": [
        "biomni/bioengineering/analyze_in_vitro_drug_release_kinetics",
        "biomni/bioengineering/korsmeyer_peppas",
        "biomni/bioengineering/higuchi",
        "biomni/bioengineering/zero_order",
        "biomni/bioengineering/first_order",
    ],
    "chemical_fingerprint_similarity": [
        "biomni/pharmacology/calculate_physicochemical_properties",
    ],
    "receptor_ligand_binding": [
        "biomni/biochemistry/one_site_model",
        "biomni/biochemistry/analyze_itc_binding_thermodynamics",
    ],
    "receptor_ligand_binding_analysis": [  # alias from pharmacology agent
        "biomni/biochemistry/one_site_model",
        "biomni/biochemistry/analyze_itc_binding_thermodynamics",
    ],
    "target_identification_and_validation": [
        "biomni/pharmacology/retrieve_topk_repurposing_drugs_from_disease_txgnn",
    ],
    "molecular_dynamics_drug_binding": [
        # No direct biomni tool for MD simulation yet
    ],
    "toxicity_prediction": [
        "biomni/pharmacology/ADMET_pred",
        "biomni/pharmacology/predict_admet_properties",
        "biomni/pharmacology/query_fda_adverse_events",
        "biomni/pharmacology/analyze_fda_safety_signals",
    ],
}

# Clean None values from lists
for k in TOPIC_TO_TOOLS:
    TOPIC_TO_TOOLS[k] = [t for t in TOPIC_TO_TOOLS[k] if t is not None]


def load_knowledge_files(knowledge_dir):
    """Load all expert knowledge JSON files."""
    all_knowledge = {}
    for fname in os.listdir(knowledge_dir):
        if fname.startswith("expert_knowledge_") and fname.endswith(".json"):
            fpath = os.path.join(knowledge_dir, fname)
            with open(fpath) as f:
                data = json.load(f)
            domain = fname.replace("expert_knowledge_", "").replace(".json", "")
            all_knowledge[domain] = data
            print(f"  Loaded {domain}: {len(data)} topics")
    return all_knowledge


def build_tool_knowledge_map(all_knowledge):
    """Map tool_ids to their expert knowledge."""
    tool_map = {}  # tool_id -> list of knowledge dicts

    for domain, topics in all_knowledge.items():
        for topic_key, topic_data in topics.items():
            tool_ids = TOPIC_TO_TOOLS.get(topic_key, [])
            if not tool_ids:
                print(f"  WARNING: No tool mapping for topic '{topic_key}' (domain: {domain})")
                continue
            for tool_id in tool_ids:
                if tool_id not in tool_map:
                    tool_map[tool_id] = []
                tool_map[tool_id].append({
                    "source_domain": domain,
                    "source_topic": topic_key,
                    "data": topic_data
                })

    return tool_map


def merge_knowledge_for_tool(knowledge_entries):
    """Merge multiple knowledge entries for a single tool into one structured dict."""
    merged_params = {}
    merged_refs = []
    merged_notes = []

    for entry in knowledge_entries:
        data = entry["data"]

        # Merge key_parameters
        for param_name, param_data in data.get("key_parameters", {}).items():
            if param_name not in merged_params:
                merged_params[param_name] = param_data
            else:
                # Merge situations
                existing = merged_params[param_name]
                for sit_name, sit_data in param_data.get("situations", {}).items():
                    if "situations" not in existing:
                        existing["situations"] = {}
                    existing["situations"][sit_name] = sit_data
                # Merge common_mistakes
                existing_mistakes = set(existing.get("common_mistakes", []))
                new_mistakes = param_data.get("common_mistakes", [])
                existing["common_mistakes"] = list(existing_mistakes | set(new_mistakes))

        # Merge references
        for ref in data.get("key_references", []):
            if ref not in merged_refs:
                merged_refs.append(ref)

        # Merge notes
        notes = data.get("best_practice_notes", "")
        if notes and notes not in merged_notes:
            merged_notes.append(notes)

    return {
        "expert_parameters": merged_params,
        "expert_references": merged_refs,
        "expert_notes": " ".join(merged_notes) if merged_notes else "",
    }


def inject_into_database(db_path, tool_knowledge_map, dry_run=False):
    """Update recommended_parameters in tool_knowledge table."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    updated = 0
    skipped = 0
    not_found = 0

    for tool_id, entries in tool_knowledge_map.items():
        # Check tool exists
        cursor.execute("SELECT tool_id FROM tool_knowledge WHERE tool_id = ?", (tool_id,))
        row = cursor.fetchone()
        if not row:
            print(f"  NOT IN DB: {tool_id}")
            not_found += 1
            continue

        # Get existing recommended_parameters
        cursor.execute(
            "SELECT recommended_parameters FROM tool_knowledge WHERE tool_id = ?",
            (tool_id,)
        )
        existing_row = cursor.fetchone()
        existing_params = {}
        if existing_row and existing_row[0]:
            try:
                existing_params = json.loads(existing_row[0])
            except json.JSONDecodeError:
                existing_params = {}

        # Merge expert knowledge
        expert_knowledge = merge_knowledge_for_tool(entries)

        # Build new recommended_parameters:
        # Keep existing param descriptions, add expert_guidance section
        new_params = existing_params.copy()
        new_params["_expert_guidance"] = expert_knowledge

        new_json = json.dumps(new_params, ensure_ascii=False)

        if dry_run:
            print(f"  WOULD UPDATE: {tool_id} ({len(entries)} knowledge sources)")
        else:
            cursor.execute(
                "UPDATE tool_knowledge SET recommended_parameters = ? WHERE tool_id = ?",
                (new_json, tool_id)
            )
            updated += 1

    if not dry_run:
        conn.commit()
    conn.close()

    return updated, skipped, not_found


def main():
    script_dir = Path(__file__).parent
    knowledge_dir = script_dir / "domain_knowledge"
    db_path = script_dir.parent / "galaxy_ai_tools.db"

    dry_run = "--dry-run" in sys.argv

    print("=== Expert Knowledge Injection ===")
    print(f"Knowledge dir: {knowledge_dir}")
    print(f"Database: {db_path}")
    print(f"Dry run: {dry_run}")
    print()

    # 1. Load knowledge files
    print("Loading knowledge files...")
    all_knowledge = load_knowledge_files(knowledge_dir)
    total_topics = sum(len(v) for v in all_knowledge.values())
    print(f"  Total: {len(all_knowledge)} domains, {total_topics} topics")
    print()

    # 2. Map to tools
    print("Building tool-knowledge mapping...")
    tool_map = build_tool_knowledge_map(all_knowledge)
    print(f"  Mapped to {len(tool_map)} unique tools")
    print()

    # 3. Inject
    print("Injecting into database...")
    updated, skipped, not_found = inject_into_database(db_path, tool_map, dry_run=dry_run)
    print(f"\nResults:")
    print(f"  Updated: {updated}")
    print(f"  Not in DB: {not_found}")
    print(f"  Total tools with expert knowledge: {len(tool_map)}")

    # 4. Summary of unmapped topics
    mapped_topics = set()
    for topic_key in TOPIC_TO_TOOLS:
        for domain, topics in all_knowledge.items():
            if topic_key in topics:
                mapped_topics.add(topic_key)

    all_topics = set()
    for domain, topics in all_knowledge.items():
        all_topics.update(topics.keys())

    unmapped = all_topics - set(TOPIC_TO_TOOLS.keys())
    if unmapped:
        print(f"\n  Unmapped topics (need TOPIC_TO_TOOLS entries): {unmapped}")


if __name__ == "__main__":
    main()
