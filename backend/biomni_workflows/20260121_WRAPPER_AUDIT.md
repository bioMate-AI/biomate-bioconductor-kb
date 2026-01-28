# Biomni Wrapper Audit Report
Date: 2026-01-21

## Summary After Cleanup
- **XML tool files**: 238
- **Wrapper files**: 258
- **Workflow files (.ga)**: 227
- **Broken wrappers (missing imports)**: ~66 (after removing query tools)

## CRITICAL: Cannot Remove Broken Wrappers
All 111 broken wrappers ARE referenced in Galaxy workflows. Removing them will break workflows.

## Fixes Completed
1. **reverse_complement** (`molecular_biology/reverse_complement_wrapper.py`)
   - Changed from: `from biomni.tool.molecular_biology import reverse_complement`
   - Changed to: Direct implementation using `Bio.Seq.reverse_complement()`

2. **analyze_enzyme_kinetics_assay** (`biochemistry/analyze_enzyme_kinetics_assay_wrapper.py`)
   - Added list parsing for `substrate_concentrations` and `time_points`
   - Added dict parsing for `modulators`

## Files Removed (Query tools - Galaxy has these natively)
- All `query_*.xml` and `query_*_wrapper.py` from `/database/`
- All `query_*.xml` and `query_*_wrapper.py` from `/literature/`
- All `query_*.xml` and `query_*_wrapper.py` from `/pharmacology/`
- Entire `/protocols/` folder (module doesn't exist)
- `search_google.*` from `/literature/`

## Remaining Broken Wrappers (111 total)
These import internal helper functions that are not exported at module level:

### Biochemistry (3)
- dose_response, michaelis_menten, one_site_model

### Bioengineering (6)
- default_whole_cell_model, exp_decay, first_order, higuchi, korsmeyer_peppas, zero_order

### Bioimaging (11)
- check_model_files_exist, command_iteration, create_affine_transform, create_deformable_transform
- create_rigid_transform, load_image, patched_torch_load, register_images, save_image
- setup_nnunet_environment, setup_registration_method, verify_nifti_input

### Cancer Biology (1)
- norm_chr

### Database (1)
- reduce_tokens

### Genetics (2)
- elbo_loss, forward

### Genomics (7)
- annotate_celltype_scRNA, check_ensembl_patterns, conda_env_exists, create_panhumanpy_env
- custom_mode, get_matrix, is_model_downloaded

### Immunology (3)
- logistic_growth, objective_function, simulate_cell_population

### Lab Automation (3)
- pick_first, run_async, target

### Literature (1)
- advanced_web_search_claude

### Microbiology (4)
- bacterial_dynamics, glv_equations, methane_yield_model, vfa_production_model

### Molecular Biology (7)
- find_orfs_in_frame, get_coding_sequences, get_refseq_id
- is_position_covered, is_region_fully_covered, merge_overlapping_regions, search_gene

### Pharmacology (4)
- ADMET_pred, apply_vcog_grade, bi_exp_model, sigmoid

### Physiology (3)
- cosinor_model, mono_exp_model, pk_ode_system

### Synthetic Biology (3)
- gene_circuit_odes, gompertz_model, hamming_distance

### Systems Biology (5)
- dimerization_odes, hill_function, mass_action_kinetics, ode_system, ras_ode_system

## Recommended Fix Strategy
For each broken wrapper:
1. Check if function is a simple helper that can be reimplemented (like reverse_complement)
2. If complex, consider promoting the helper function to module level in biomni source
3. Test in Docker container before deploying
