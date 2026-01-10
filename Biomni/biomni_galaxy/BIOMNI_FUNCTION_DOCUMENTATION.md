# Biomni Function Documentation Report

---

## Summary Statistics

| Metric | Count | Percentage |
|--------|-------|------------|
| Total functions | 295 | 100% |
| With docstrings | 241 | 81.7% |
| With parameters | 285 | 96.6% |
| Missing docs | 54 | 18.3% |


## Biochemistry (10 functions)

### `analyze_circular_dichroism_spectra`
**Summary**: Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.

**Parameters**:
- `sample_name` (str): Name of the biomolecule sample (e.g., "Znf706", "G-quadruplex")
- `sample_type` (str): Type of biomolecule ("protein" or "nucleic_acid")
- `wavelength_data` (list or numpy.ndarray): Wavelength values in nm for CD spectrum
- `cd_signal_data` (list or numpy.ndarray): CD signal intensity values (typically in mdeg or Δε)
- `temperature_data` (list or numpy.ndarray, optional): Temperature values (°C) for thermal denaturation experiment
- `thermal_cd_data` (list or numpy.ndarray, optional): CD signal values at specific wavelength across different temperatures
- `output_dir` (str, optional): Directory to save result files, defaults to current directory

**Returns**: str
    Research log summarizing the CD analysis steps and results

*Documentation quality*: Complete

### `analyze_rna_secondary_structure_features`
**Summary**: Calculate numeric values for various structural features of an RNA secondary structure.

**Parameters**:
- `dot_bracket_structure` (str): RNA secondary structure in dot-bracket notation (e.g., "(((...)))"). Parentheses represent base pairs, dots represent unpaired bases.
- `sequence` (str, optional): The RNA sequence corresponding to the structure. If provided, sequence-dependent energy calculations will be performed.

**Returns**: str
    A research log summarizing the calculated structural features and analysis steps.

*Documentation quality*: Complete

### `analyze_protease_kinetics`
**Summary**: Analyze protease kinetics data from fluorogenic peptide cleavage assays.

**Parameters**:
- `time_points` (numpy.ndarray): Array of time points (in seconds) at which measurements were taken
- `fluorescence_data` (numpy.ndarray): 2D array of fluorescence measurements where each row corresponds to a different substrate concentration and each column corresponds to a time point
- `substrate_concentrations` (numpy.ndarray): Array of substrate concentrations (in μM) corresponding to each row in fluorescence_data
- `enzyme_concentration` (float): Concentration of the protease enzyme (in μM)
- `output_prefix` (str, optional): Prefix for output files (default: "protease_kinetics")
- `output_dir` (str, optional): Directory to save output files (default: "./")

**Returns**: str
    A research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `michaelis_menten`

**Parameters**:
- `s`
- `vmax`
- `km`

*Documentation quality*: Missing

### `analyze_enzyme_kinetics_assay`
**Summary**: Performs in vitro enzyme kinetics assay and analyzes the dose-dependent effects of modulators.

**Parameters**:
- `enzyme_name` (str): Name of the purified enzyme being tested
- `substrate_concentrations` (list or numpy.ndarray): List of substrate concentrations in μM for kinetic analysis
- `enzyme_concentration` (float): Concentration of the enzyme in nM
- `modulators` (dict, optional): Dictionary of modulators where keys are modulator names and values are lists of concentrations in μM. Default is None (no modulators).
- `time_points` (list or numpy.ndarray, optional): Time points in minutes for time-course measurements. Default is None, which uses [0, 5, 10, 15, 20, 30, 45, 60].
- `output_dir` (str, optional): Directory to save output files. Default is current directory.

**Returns**: str
    Research log summarizing the enzyme kinetics assay procedure and results

*Documentation quality*: Complete

### `michaelis_menten`

**Parameters**:
- `s`
- `vmax`
- `km`

*Documentation quality*: Missing

### `dose_response`

**Parameters**:
- `x`
- `ic50`
- `hill`

*Documentation quality*: Missing

### `analyze_itc_binding_thermodynamics`
**Summary**: Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.

**Parameters**:
- `itc_data_path` (str, optional): Path to CSV or TSV file containing ITC thermogram data with columns for injection number, injection volume, and heat released/absorbed. Expected columns: 'injection', 'volume', 'heat'
- `itc_data` (numpy.ndarray, optional): Raw ITC thermogram data as a numpy array. Expected shape: (n_injections, 3) with columns for injection number, injection volume, and heat This parameter is provided for backward compatibility and will be deprecated.
- `temperature` (float, optional): Temperature in Kelvin at which the experiment was conducted. Default is 298.15 K (25°C).
- `protein_concentration` (float, optional): Initial concentration of protein in the cell in molar (M). Required for accurate fitting.
- `ligand_concentration` (float, optional): Concentration of ligand in the syringe in molar (M). Required for accurate fitting.

**Returns**: str
    A research log summarizing the analysis steps and results, including binding affinity (Kd),
    binding enthalpy (ΔH), binding entropy (ΔS), and Gibbs free energy (ΔG).

*Documentation quality*: Complete

### `one_site_model`
**Summary**: One-site binding model for ITC data.

**Parameters**:
- `x` (Molar ratio [ligand]/[protein])
- `Kd` (Dissociation constant (M)
- `dH` (Enthalpy change (cal/mol)
- `n` (Stoichiometry)

*Documentation quality*: Complete

### `analyze_protein_conservation`
**Summary**: Perform multiple sequence alignment and phylogenetic analysis to identify conserved protein regions.

**Parameters**:
- `protein_sequences` (list of str): List of protein sequences in FASTA format from multiple organisms.
- `output_dir` (str, optional): Directory to save output files (default: "./output")

**Returns**: str
    Research log summarizing the analysis steps and results, including filenames of saved outputs.

*Documentation quality*: Complete

## Bioengineering (13 functions)

### `analyze_cell_migration_metrics`
**Summary**: Analyze cell migration metrics from time-lapse microscopy images.

**Parameters**:
- `image_sequence_path` (str): Path to the directory containing time-lapse images or path to a multi-frame TIFF file
- `pixel_size_um` (float): Conversion factor from pixels to micrometers (default: 1.0)
- `time_interval_min` (float): Time interval between consecutive frames in minutes (default: 1.0)
- `min_track_length` (int): Minimum number of frames a cell must be tracked to be included in analysis (default: 10)
- `output_dir` (str): Directory to save output files (default: "./")

**Returns**: str
    Research log summarizing the cell migration analysis process and results

*Documentation quality*: Complete

### `perform_crispr_cas9_genome_editing`
**Summary**: Simulates CRISPR-Cas9 genome editing process including guide RNA design, delivery, and analysis.

**Parameters**:
- `guide_rna_sequences` (list of str): List of guide RNA sequences (20 nucleotides each) targeting the genomic region of interest
- `target_genomic_loci` (str): Target genomic sequence to be edited (should be longer than guide RNA and contain the target sites)
- `cell_tissue_type` (str): Type of cell or tissue being edited (affects delivery efficiency and editing outcomes)

**Returns**: str
    Research log detailing the CRISPR-Cas9 editing process, including steps taken and results

*Documentation quality*: Complete

### `analyze_calcium_imaging_data`
**Summary**: Analyze calcium imaging data to quantify neuronal activity metrics.

**Parameters**:
- `image_stack_path` (str): Path to the time-series stack of fluorescence microscopy images (TIFF format)
- `output_dir` (str, optional): Directory to save output files (default: "./")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `exp_decay`

**Parameters**:
- `x`
- `a`
- `tau`
- `c`

*Documentation quality*: Missing

### `analyze_in_vitro_drug_release_kinetics`
**Summary**: Analyzes in vitro drug release kinetics from biomaterial formulations.

**Parameters**:
- `time_points` (list or numpy.ndarray): Time points at which drug concentrations were measured (in hours)
- `concentration_data` (list or numpy.ndarray): Measured drug concentration at each time point
- `drug_name` (str, optional): Name of the drug being analyzed (default: "Drug")
- `total_drug_loaded` (float, optional): Total amount of drug initially loaded in the formulation. If None, the maximum concentration is used as 100% (default: None)
- `output_dir` (str, optional): Directory to save output files (default: "./")

**Returns**: str
    Research log summarizing the analysis steps, results, and saved file locations

*Documentation quality*: Complete

### `zero_order`

**Parameters**:
- `t`
- `k`

*Documentation quality*: Missing

### `first_order`

**Parameters**:
- `t`
- `k`

*Documentation quality*: Missing

### `higuchi`

**Parameters**:
- `t`
- `k`

*Documentation quality*: Missing

### `korsmeyer_peppas`

**Parameters**:
- `t`
- `k`
- `n`

*Documentation quality*: Missing

### `analyze_myofiber_morphology`
**Summary**: Quantifies morphological properties of myofibers in microscopy images of tissue sections.

**Parameters**:
- `image_path` (str): Path to the microscopy image file (typically a multichannel image with nuclei and myofiber staining)
- `nuclei_channel` (int, default=2): Channel index containing nuclei staining (DAPI, Hoechst, etc.)
- `myofiber_channel` (int, default=1): Channel index containing myofiber staining (α-Actinin, etc.)
- `threshold_method` (str, default='otsu'): Method for thresholding ('otsu', 'adaptive', or 'manual')
- `output_dir` (str, default='./'): Directory to save output files

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `decode_behavior_from_neural_trajectories`
**Summary**: Model neural activity trajectories and decode behavioral variables.

**Parameters**:
- `neural_data` (numpy.ndarray): Neural spiking activity data, shape (n_timepoints, n_neurons)
- `behavioral_data` (numpy.ndarray): Behavioral data, shape (n_timepoints, n_behavioral_variables)
- `n_components` (int, optional): Number of principal components to use for dimensionality reduction, default is 10
- `output_dir` (str, optional): Directory to save output files, default is "./"

**Returns**: str
    Research log summarizing the steps taken and results

*Documentation quality*: Complete

### `simulate_whole_cell_ode_model`
**Summary**: Simulate a whole-cell model represented as a system of ordinary differential equations (ODEs).

**Parameters**:
- `initial_conditions` (dict or array-like): Initial values for each state variable in the model. If dict, keys are variable names and values are initial concentrations/values. If array-like, order must match the order expected by the ODE function.
- `parameters` (dict): Model parameters required by the ODE function. Keys are parameter names and values are parameter values.
- `ode_function` (callable, optional): Function defining the system of ODEs. Should take arguments ``(t, y, *args)`` where ``t`` is time, ``y`` is the state vector, and ``args`` contains additional parameters. If None, a simple example whole-cell model will be used.
- `time_span` (tuple, default=(0, 100): Tuple of (start_time, end_time) for the simulation.
- `time_points` (int, default=1000): Number of time points to evaluate.
- `method` (str, default='LSODA'): Numerical integration method to use (e.g., 'RK45', 'LSODA', 'BDF').

**Returns**: str
    Research log summarizing the simulation steps and results. Results are saved
    to a CSV file and the filename is included in the log.

*Documentation quality*: Complete

### `default_whole_cell_model`

**Parameters**:
- `t`
- `y`
- `params`

*Documentation quality*: Missing

## Bioimaging (28 functions)

### `split_modalities`
**Summary**: Split a 4D NIfTI file into separate modality files for nnUNet

**Parameters**:
- `self`
- `input_file`
- `output_dir`
- `case_name`

**Returns**: output_dir: Path to directory containing split modality files

*Documentation quality*: Complete

### `prepare_input_for_nnunet`
**Summary**: Prepare input data for nnUNet by handling both 4D and pre-split modality files

**Parameters**:
- `self`
- `input_path`
- `output_dir`
- `case_name`

**Returns**: prepared_dir: Path to directory with nnUNet-ready files

*Documentation quality*: Complete

### `setup_nnunet_environment`
**Summary**: Setup nnU-Net environment variables according to official documentation

**Parameters**:
- `self`
- `results_folder`
- `raw_data_base`
- `preprocessed`

*Documentation quality*: Complete

### `segment_with_nn_unet`
**Summary**: Segment images using nnUNet with proper environment setup and automatic model downloading

**Parameters**:
- `self`
- `image_path`
- `output_dir`
- `task_id`
- `model_type`
- `folds`
- `use_tta`
- `num_threads`
- `mixed_precision`
- `verbose`
- `auto_prepare_input`
- `results_folder`
- `auto_download`

*Documentation quality*: Complete

### `verify_nifti_input`

**Parameters**:
- `image_path`

*Documentation quality*: Missing

### `check_model_files_exist`
**Summary**: Check if actual model weight files exist for the specified folds

**Parameters**:
- `model_folder`
- `folds`

*Documentation quality*: Complete

### `patched_torch_load`

*Documentation quality*: Missing

### `create_segmentation_visualization`
**Summary**: Create and save visualization of segmentation results using nilearn

**Parameters**:
- `self`
- `original_mri`
- `segmentation`
- `output_dir`

**Returns**: list: List of saved image file paths

*Documentation quality*: Complete

### `load_image`
**Summary**: Load a medical image using SimpleITK.

**Parameters**:
- `self`
- `image_path` (str)

**Returns**: SimpleITK Image object

*Documentation quality*: Complete

### `save_image`
**Summary**: Save a SimpleITK image to file.

**Parameters**:
- `self`
- `image` (sitk.Image)
- `output_path` (str)

*Documentation quality*: Complete

### `preprocess_image`
**Summary**: Preprocess an image with denoising and normalization.

**Parameters**:
- `self`
- `image` (sitk.Image)
- `denoise` (bool)
- `normalize` (bool)

**Returns**: Preprocessed SimpleITK image

*Documentation quality*: Complete

### `create_rigid_transform`
**Summary**: Create a rigid transform for image registration.

**Parameters**:
- `self`
- `fixed_image` (sitk.Image)
- `moving_image` (sitk.Image)
- `initial_transform` (sitk.Transform | None)

**Returns**: Rigid transform object

*Documentation quality*: Complete

### `create_affine_transform`
**Summary**: Create an affine transform for image registration.

**Parameters**:
- `self`
- `fixed_image` (sitk.Image)
- `moving_image` (sitk.Image)
- `initial_transform` (sitk.Transform | None)

**Returns**: Affine transform object

*Documentation quality*: Complete

### `create_deformable_transform`
**Summary**: Create a deformable (B-spline) transform for image registration.

**Parameters**:
- `self`
- `fixed_image` (sitk.Image)
- `moving_image` (sitk.Image)
- `number_of_control_points` (int)

**Returns**: Deformable transform object

*Documentation quality*: Complete

### `setup_registration_method`
**Summary**: Setup the registration method with specified parameters.

**Parameters**:
- `self`
- `transform` (sitk.Transform)
- `metric` (str)
- `optimizer` (str)
- `learning_rate` (float)
- `number_of_iterations` (int)
- `gradient_convergence_tolerance` (float)

**Returns**: Configured registration method

*Documentation quality*: Complete

### `register_images`
**Summary**: Perform image registration.

**Parameters**:
- `self`
- `fixed_image` (sitk.Image)
- `moving_image` (sitk.Image)
- `transform` (sitk.Transform)
- `registration_method` (sitk.ImageRegistrationMethod)

**Returns**: Tuple of (final_transform, registered_image)

*Documentation quality*: Complete

### `command_iteration`

*Documentation quality*: Missing

### `calculate_similarity_metrics`
**Summary**: Calculate similarity metrics between two images.

**Parameters**:
- `self`
- `image1` (sitk.Image)
- `image2` (sitk.Image)

**Returns**: Dictionary of similarity metrics

*Documentation quality*: Complete

### `split_modalities`
**Summary**: Convenience function for splitting modalities

**Parameters**:
- `input_file`
- `output_dir`
- `case_name`

*Documentation quality*: Complete

### `prepare_input_for_nnunet`
**Summary**: Convenience function for preparing nnUNet input

**Parameters**:
- `input_path`
- `output_dir`
- `case_name`

*Documentation quality*: Complete

### `segment_with_nn_unet`
**Summary**: Convenience function for nnUNet segmentation

**Parameters**:
- `image_path`
- `output_dir`
- `task_id`
- `model_type`
- `folds`
- `use_tta`
- `num_threads`
- `mixed_precision`
- `verbose`
- `auto_prepare_input`
- `results_folder`

*Documentation quality*: Complete

### `create_segmentation_visualization`
**Summary**: Convenience function for segmentation visualization

**Parameters**:
- `original_mri`
- `segmentation`
- `output_dir`

*Documentation quality*: Complete

### `preprocess_image`
**Summary**: Standalone image preprocessing function for Biomni integration.

**Parameters**:
- `image_path` (str)
- `output_path` (str)
- `denoise` (bool)
- `normalize` (bool)

**Returns**: Path to the saved preprocessed image

*Documentation quality*: Complete

### `quick_rigid_registration`
**Summary**: Quick rigid registration function for Biomni integration.

**Parameters**:
- `fixed_image_path` (str)
- `moving_image_path` (str)
- `output_dir` (str)
- `metric` (str)
- `optimizer` (str)
- `preprocess` (bool)
- `create_visualizations` (bool)
- `learning_rate` (float)
- `number_of_iterations` (int)
- `gradient_convergence_tolerance` (float)

**Returns**: Dictionary with registration results

*Documentation quality*: Complete

### `quick_affine_registration`
**Summary**: Quick affine registration function for Biomni integration.

**Parameters**:
- `fixed_image_path` (str)
- `moving_image_path` (str)
- `output_dir` (str)
- `metric` (str)
- `optimizer` (str)
- `preprocess` (bool)
- `create_visualizations` (bool)
- `learning_rate` (float)
- `number_of_iterations` (int)
- `gradient_convergence_tolerance` (float)

**Returns**: Dictionary with registration results

*Documentation quality*: Complete

### `quick_deformable_registration`
**Summary**: Quick deformable registration function for Biomni integration.

**Parameters**:
- `fixed_image_path` (str)
- `moving_image_path` (str)
- `output_dir` (str)
- `metric` (str)
- `optimizer` (str)
- `preprocess` (bool)
- `create_visualizations` (bool)
- `learning_rate` (float)
- `number_of_iterations` (int)
- `gradient_convergence_tolerance` (float)
- `number_of_control_points` (int)

**Returns**: Dictionary with registration results

*Documentation quality*: Complete

### `batch_register_images`
**Summary**: Batch registration of multiple images to a single reference.

**Parameters**:
- `fixed_image_path` (str)
- `moving_images_dir` (str)
- `output_dir` (str)
- `transform_type` (str)
- `metric` (str)
- `optimizer` (str)
- `preprocess` (bool)
- `create_visualizations` (bool)
- `learning_rate` (float)
- `number_of_iterations` (int)
- `gradient_convergence_tolerance` (float)

**Returns**: Dictionary with batch registration results

*Documentation quality*: Complete

### `calculate_similarity_metrics`
**Summary**: Calculate similarity metrics between two images.

**Parameters**:
- `image1_path` (str)
- `image2_path` (str)

**Returns**: Dictionary of similarity metrics

*Documentation quality*: Complete

## Biophysics (3 functions)

### `predict_protein_disorder_regions`
**Summary**: Predicts intrinsically disordered regions (IDRs) in a protein sequence using IUPred2A.

**Parameters**:
- `protein_sequence` (str): The amino acid sequence of the protein to analyze
- `threshold` (float, optional): The disorder score threshold above which a residue is considered disordered (default: 0.5)
- `output_file` (str, optional): Filename to save the per-residue disorder scores (default: "disorder_prediction_results.csv")

**Returns**: str
    A research log summarizing the prediction process and results

*Documentation quality*: Complete

### `analyze_cell_morphology_and_cytoskeleton`
**Summary**: Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.

**Parameters**:
- `image_path` (str): Path to the fluorescence microscopy image file
- `output_dir` (str, optional): Directory to save output files (default: './results')
- `threshold_method` (str, optional): Method for cell segmentation ('otsu', 'adaptive', or 'manual') (default: 'otsu')

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_tissue_deformation_flow`
**Summary**: Quantify tissue deformation and flow dynamics from microscopy image sequence.

**Parameters**:
- `image_sequence` (list or numpy.ndarray): Sequence of microscopy images (either a list of file paths or a 3D numpy array [time, height, width])
- `output_dir` (str, optional): Directory to save results (default: "results")
- `pixel_scale` (float, optional): Physical scale of pixels (e.g., μm/pixel) for proper scaling of metrics (default: 1.0)

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

## Cancer_Biology (7 functions)

### `analyze_ddr_network_in_cancer`
**Summary**: Analyze DNA Damage Response (DDR) network alterations and dependencies in cancer samples.

**Parameters**:
- `expression_data_path` (str): Path to gene expression data file (CSV format with genes as rows, samples as columns)
- `mutation_data_path` (str): Path to mutation data file (CSV format with genes as rows, samples as columns, values indicating mutation status)
- `output_dir` (str, optional): Directory to save output files (default: "./results")

**Returns**: str
    Research log summarizing the DDR network analysis, findings about disruptions,
    and potential therapeutic vulnerabilities

*Documentation quality*: Complete

### `analyze_cell_senescence_and_apoptosis`
**Summary**: Analyze flow cytometry data to quantify senescent and apoptotic cell populations.

**Parameters**:
- `fcs_file_path` (str): Path to the FCS file containing flow cytometry data with measurements for senescence-associated β-galactosidase (SA-β-Gal) and Annexin V/7-AAD staining

**Returns**: str
    A research log summarizing the analysis steps and results, including percentages
    of senescent and apoptotic cell populations

*Documentation quality*: Complete

### `detect_and_annotate_somatic_mutations`
**Summary**: Detects and annotates somatic mutations in tumor samples compared to matched normal samples.

**Parameters**:
- `tumor_bam` (str): Path to the tumor sample BAM file
- `normal_bam` (str): Path to the matched normal sample BAM file
- `reference_genome` (str): Path to the reference genome FASTA file
- `output_prefix` (str): Prefix for output files
- `snpeff_database` (str, optional): SnpEff database to use for annotation (default: "GRCh38.105")

**Returns**: str
    A research log summarizing the steps performed and results obtained

*Documentation quality*: Complete

### `detect_and_characterize_structural_variations`
**Summary**: Detects and characterizes structural variations (SVs) in genomic sequencing data.

**Parameters**:
- `bam_file_path` (str): Path to the aligned sequencing data in BAM format
- `reference_genome_path` (str): Path to the reference genome in FASTA format
- `output_dir` (str): Directory where results will be saved
- `cosmic_db_path` (str, optional): Path to the COSMIC database for cancer annotation
- `clinvar_db_path` (str, optional): Path to the ClinVar database for clinical annotation

**Returns**: str
    A research log summarizing the steps performed and results obtained

*Documentation quality*: Complete

### `perform_gene_expression_nmf_analysis`
**Summary**: Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract

**Parameters**:
- `expression_data_path` (str): Path to a CSV or TSV file containing gene expression data with genes as rows and samples as columns. Values should be non-negative (e.g., normalized counts or expression values).
- `n_components` (int, default=10): Number of metagenes (components) to extract.
- `normalize` (bool, default=True): Whether to normalize the expression data before applying NMF.
- `output_dir` (str, default="nmf_results"): Directory to save the output files.
- `random_state` (int, default=42): Random seed for reproducibility.

**Returns**: str
    Research log summarizing the analysis steps and results.

*Documentation quality*: Complete

### `analyze_copy_number_purity_ploidy_and_focal_events`
**Summary**: CNVkit-based copy number workflow: CNV segmentation, purity/ploidy & HRD approximation, focal events.

**Parameters**:
- `tumor_bam` (str): Path to tumor BAM (indexed)
- `reference_genome` (str): Path to reference FASTA (with index files present)
- `normal_bam` (str, optional): Matched normal BAM (recommended for allele-specific & purity inference)
- `output_dir` (str, default "cn_analysis_results"): Directory for all outputs
- `targets_bed` (str, optional): BED of target regions (e.g. exome / panel) for CNVkit / gCNV
- `antitargets_bed` (str, optional): BED of antitarget regions for CNVkit (if panel / exome)
- `gene_bed` (str, optional): BED file with gene coordinates (chrom, start, end, gene). Used for focal event annotation
- `focal_genes` (list[str], optional): List of genes to highlight for focal amplification/deletion; defaults to ["MYC","ERBB2","CDKN2A"]
- `log2_amp_threshold` (float, default 1.0): Log2 ratio threshold to call focal amplification (~ >2x copy relative to baseline)
- `log2_del_threshold` (float, default -1.0): Log2 ratio threshold to call focal deep deletion (~ homozygous loss)

**Returns**: str
    Research log summarizing steps, tool executions, and findings.

*Documentation quality*: Complete

### `norm_chr`

**Parameters**:
- `x`

*Documentation quality*: Missing

## Cell_Biology (5 functions)

### `quantify_cell_cycle_phases_from_microscopy`
**Summary**: Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.

**Parameters**:
- `image_paths` (list of str): List of file paths to microscopy images of cells stained with Calcofluor white
- `output_dir` (str, optional): Directory to save results (default: './results')

**Returns**: str
    Research log summarizing the analysis process and results

*Documentation quality*: Complete

### `quantify_and_cluster_cell_motility`
**Summary**: Quantify cell motility features from time-lapse microscopy images and cluster cells based on motility patterns.

**Parameters**:
- `image_sequence_path` (str): Path to directory containing time-lapse microscopy images in sequential order
- `output_dir` (str): Directory to save output files (default: "./results")
- `num_clusters` (int): Number of motility pattern clusters to identify (default: 3)

**Returns**: str
    Research log summarizing the analysis process and results

*Documentation quality*: Complete

### `perform_facs_cell_sorting`
**Summary**: Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.

**Parameters**:
- `cell_suspension_data` (str): Path to the FCS file containing flow cytometry data
- `fluorescence_parameter` (str): The fluorescence parameter to use for sorting (e.g., 'GFP', 'FITC', 'PE')
- `threshold_min` (float, optional): Minimum threshold for the fluorescence parameter. Cells below this value will be excluded
- `threshold_max` (float, optional): Maximum threshold for the fluorescence parameter. Cells above this value will be excluded
- `output_file` (str, optional): Filename to save the sorted cell population data

**Returns**: str
    Research log detailing the FACS cell sorting process

*Documentation quality*: Complete

### `analyze_flow_cytometry_immunophenotyping`
**Summary**: Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.

**Parameters**:
- `fcs_file_path` (str): Path to the FCS file containing flow cytometry data
- `gating_strategy` (dict): Dictionary defining the gating strategy. Each key is a population name, and each value is a list of tuples (marker, operator, threshold). For example: {'HSCs': [('Lin', '<', 100), ('Sca1', '>', 1000), ...]}
- `compensation_matrix` (numpy.ndarray, optional): Spillover/compensation matrix to correct for fluorescence overlap
- `output_dir` (str, optional): Directory to save the results

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_mitochondrial_morphology_and_potential`
**Summary**: Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.

**Parameters**:
- `morphology_image_path` (str): Path to the fluorescence microscopy image showing mitochondrial morphology (e.g., MTS-GFP)
- `potential_image_path` (str): Path to the fluorescence microscopy image showing mitochondrial membrane potential (e.g., TMRE staining)
- `output_dir` (str, optional): Directory to save output files, default is "./output"

**Returns**: str
    A research log summarizing the analysis steps and results

*Documentation quality*: Complete

## Database (42 functions)

### `get_hpo_names`
**Summary**: Retrieve the names of given HPO terms.

**Parameters**:
- `hpo_terms` (list[str])
- `data_lake_path` (str)

**Returns**: List[str]: A list of corresponding HPO term names.

*Documentation quality*: Complete

### `query_uniprot`
**Summary**: Query the UniProt REST API using either natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about proteins (e.g., "Find information about human insulin")
- `endpoint` (str, optional): Full or partial UniProt API endpoint URL to query directly): (e.g., "https://rest.uniprot.org/uniprotkb/P01308")
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the query information and the UniProt API results

*Documentation quality*: Complete

### `query_alphafold`
**Summary**: Query the AlphaFold Database API for protein structure predictions.

**Parameters**:
- `uniprot_id` (str): UniProt accession ID (e.g., "P12345")
- `endpoint` (str, optional): Specific AlphaFold API endpoint to query:): "prediction", "summary", or "annotations"
- `residue_range` (str, optional): Specific residue range in format "start-end" (e.g., "1-100")
- `download` (bool): Whether to download structure files)
- `output_dir` (str, optional): Directory to save downloaded files (default: current directory)
- `file_format` (str): Format of the structure file to download - "pdb" or "cif")
- `model_version` (str): AlphaFold model version - "v4" (latest) or "v3", "v2", "v1")
- `model_number` (int): Model number (1-5, with 1 being the highest confidence model)

**Returns**: dict: Dictionary containing both the query information and the AlphaFold results

*Documentation quality*: Complete

### `query_interpro`
**Summary**: Query the InterPro REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about protein domains or families)
- `endpoint` (str, optional): Direct endpoint path or full URL (e.g., "/entry/interpro/IPR023411"): or "https://www.ebi.ac.uk/interpro/api/entry/interpro/IPR023411")
- `max_results` (int): Maximum number of results to return per page)

**Returns**: dict: Dictionary containing both the query information and the InterPro API results

*Documentation quality*: Complete

### `query_pdb`
**Summary**: Query the RCSB PDB database using natural language or a direct structured query.

**Parameters**:
- `prompt` (str, required): Natural language query about protein structures)
- `query` (dict, optional): Direct structured query in RCSB Search API format (overrides prompt)
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the structured query, search results, and identifiers

*Documentation quality*: Complete

### `query_pdb_identifiers`
**Summary**: Retrieve detailed data and/or download files for PDB identifiers.

**Parameters**:
- `identifiers` (list): List of PDB identifiers (from query_pdb)
- `return_type` (str): Type of results: "entry", "assembly", "polymer_entity", etc.)
- `download` (bool): Whether to download PDB structure files)
- `attributes` (list, optional): List of specific attributes to retrieve)

**Returns**: dict: Dictionary containing the detailed data and file paths if downloaded

*Documentation quality*: Complete

### `query_kegg`
**Summary**: Take a natural language prompt and convert it to a structured KEGG API query.

**Parameters**:
- `prompt` (str): Natural language query about KEGG data (e.g., "Find human pathways related to glycolysis")
- `endpoint` (str, optional): Direct KEGG API endpoint to query)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing both the structured query and the KEGG results

*Documentation quality*: Complete

### `query_stringdb`
**Summary**: Query the STRING protein interaction database using natural language or direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about protein interactions)
- `endpoint` (str, optional): Full URL to query directly (overrides prompt)
- `download_image` (bool): Whether to download image results (for image endpoints)
- `output_dir` (str, optional): Directory to save downloaded files (default: current directory)
- `verbose`

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_iucn`
**Summary**: Query the IUCN Red List API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about species conservation status)
- `endpoint` (str, optional): API endpoint name (e.g., "species/id/12392") or full URL)
- `token` (str): IUCN API token - required for all queries)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_paleobiology`
**Summary**: Query the Paleobiology Database (PBDB) API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about fossil records)
- `endpoint` (str, optional): API endpoint name or full URL)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_jaspar`
**Summary**: Query the JASPAR REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about transcription factor binding profiles)
- `endpoint` (str, optional): API endpoint path (e.g., "/matrix/MA0002.2/") or full URL)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_worms`
**Summary**: Query the World Register of Marine Species (WoRMS) REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about marine species)
- `endpoint` (str, optional): Full URL or endpoint specification)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_cbioportal`
**Summary**: Query the cBioPortal REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about cancer genomics data)
- `endpoint` (str, optional): API endpoint path (e.g., "/studies/brca_tcga/patients") or full URL)
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_clinvar`
**Summary**: Take a natural language prompt and convert it to a structured ClinVar query.

**Parameters**:
- `prompt` (str): Natural language query about genetic variants (e.g., "Find pathogenic BRCA1 variants")
- `search_term` (str): Direct search term in ClinVar syntax)
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing both the structured query and the ClinVar results

*Documentation quality*: Complete

### `query_geo`
**Summary**: Query the NCBI Gene Expression Omnibus (GEO) using natural language or a direct search term.

**Parameters**:
- `prompt` (str, required): Natural language query about RNA-seq, microarray, or other expression data)
- `search_term` (str, optional): Direct search term in GEO syntax)
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_dbsnp`
**Summary**: Query the NCBI dbSNP database using natural language or a direct search term.

**Parameters**:
- `prompt` (str, required): Natural language query about genetic variants/SNPs)
- `search_term` (str, optional): Direct search term in dbSNP syntax)
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_ucsc`
**Summary**: Query the UCSC Genome Browser API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about genomic data)
- `endpoint` (str, optional): Full URL or endpoint specification with parameters)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_ensembl`
**Summary**: Query the Ensembl REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about genomic data)
- `endpoint` (str, optional): Direct API endpoint to query (e.g., "lookup/symbol/human/BRCA2") or full URL)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_opentarget`
**Summary**: Query the OpenTargets Platform API using natural language or a direct GraphQL query.

**Parameters**:
- `prompt` (str, required): Natural language query about drug targets, diseases, and mechanisms)
- `query` (str, optional): Direct GraphQL query string)
- `variables` (dict, optional): Variables for the GraphQL query)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_monarch`
**Summary**: Query the Monarch Initiative API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, optional): Natural language query about genes, diseases, phenotypes, etc.)
- `endpoint` (str, optional): Direct Monarch API endpoint or full URL)
- `max_results` (int): Maximum number of results to return (if supported by endpoint)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_openfda`
**Summary**: Query the OpenFDA API using natural language or direct parameters.

**Parameters**:
- `prompt` (str, optional): Natural language query about drugs, adverse events, recalls, etc.)
- `endpoint` (str, optional): Direct OpenFDA API endpoint or full URL)
- `max_results` (int): Maximum number of results to return (if supported by endpoint)
- `verbose` (bool): Whether to return detailed results)
- `search_params` (dict, optional): Search parameters in format {"field": "term"} or {"field": ["term1", "term2"]})
- `sort_params` (dict, optional): Sort parameters in format {"field": "asc|desc"})
- `count_params` (str, optional): Field to count unique values for)
- `skip_results` (int): Number of results to skip for pagination (max 25000)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_gwas_catalog`
**Summary**: Query the GWAS Catalog API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about GWAS data)
- `endpoint` (str, optional): Full API endpoint to query (e.g., "https://www.ebi.ac.uk/gwas/rest/api/studies?diseaseTraitId=EFO_0001360")
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_gnomad`
**Summary**: Query gnomAD for variants in a gene using natural language or direct gene symbol.

**Parameters**:
- `prompt` (str, required): Natural language query about genetic variants)
- `gene_symbol` (str, optional): Gene symbol (e.g., "BRCA1")
- `verbose` (bool): Whether to print verbose output)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `blast_sequence`
**Summary**: Identifies a DNA sequence using NCBI BLAST with improved error handling, timeout management, and debugging.

**Parameters**:
- `sequence` (str)
- `database` (str)
- `program` (str)

**Returns**: dict: A dictionary containing the title, e-value, identity percentage, and coverage percentage of the best alignment

*Documentation quality*: Complete

### `query_reactome`
**Summary**: Query the Reactome database using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about biological pathways)
- `endpoint` (str, optional): Direct API endpoint or full URL)
- `download` (bool): Whether to download pathway diagrams)
- `output_dir` (str, optional): Directory to save downloaded files)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_regulomedb`
**Summary**: Query the RegulomeDB database using natural language or direct variant/coordinate specification.

**Parameters**:
- `prompt` (str, required): Natural language query about regulatory elements)
- `endpoint` (str, optional): The full endpoint to query (e.g., "https://regulomedb.org/regulome-search/?regions=chr11:5246919-5246919&genome=GRCh38")
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_pride`
**Summary**: Query the PRIDE (PRoteomics IDEntifications) database using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about proteomics data)
- `endpoint` (str, optional): The full endpoint to query (e.g., "https://www.ebi.ac.uk/pride/ws/archive/v2/projects?keyword=breast%20cancer")
- `max_results` (int): Maximum number of results to return)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_gtopdb`
**Summary**: Query the Guide to PHARMACOLOGY database (GtoPdb) using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about drug targets, ligands, and interactions)
- `endpoint` (str, optional): Full API endpoint to query (e.g., "https://www.guidetopharmacology.org/services/targets?type=GPCR&name=beta-2")
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `region_to_ccre_screen`
**Summary**: Given starting and ending coordinates, this function retrieves information of intersecting cCREs.

**Parameters**:
- `coord_chrom` (str)
- `coord_start` (int)
- `coord_end` (int)
- `assembly` (str)

**Returns**: str: A detailed string explaining the steps and the intersecting cCRE data or any error encountered.

*Documentation quality*: Complete

### `reduce_tokens`

**Parameters**:
- `res_json`

*Documentation quality*: Missing

### `get_genes_near_ccre`
**Summary**: Given a cCRE (Candidate cis-Regulatory Element), this function returns a string containing the

**Parameters**:
- `accession` (str)
- `assembly` (str)
- `chromosome` (str)
- `k` (int)

**Returns**: - str: Steps performed and the result.

*Documentation quality*: Complete

### `query_remap`
**Summary**: Query the ReMap database for regulatory elements and transcription factor binding sites.

**Parameters**:
- `prompt` (str, required): Natural language query about transcription factors and binding sites)
- `endpoint` (str, optional): Full API endpoint to query (e.g., "https://remap.univ-amu.fr/api/v1/catalogue/tf?tf=CTCF")
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_mpd`
**Summary**: Query the Mouse Phenome Database (MPD) for mouse strain phenotype data.

**Parameters**:
- `prompt` (str, required): Natural language query about mouse phenotypes, strains, or measurements)
- `endpoint` (str, optional): Full API endpoint to query (e.g., "https://phenomedoc.jax.org/MPD_API/strains")
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_emdb`
**Summary**: Query the Electron Microscopy Data Bank (EMDB) for 3D macromolecular structures.

**Parameters**:
- `prompt` (str, required): Natural language query about EM structures and associated data)
- `endpoint` (str, optional): Full API endpoint to query (e.g., "https://www.ebi.ac.uk/emdb/api/search")
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_synapse`
**Summary**: Query Synapse REST API for biomedical datasets and files.

**Parameters**:
- `prompt` (str | None): Natural language query about biomedical data (e.g., "Find drug screening datasets")
- `query_term` (str | list[str] | None): Specific search terms for Synapse search. When multiple terms are provided as a list, they are combined with AND logic (more terms = more restrictive). Start with 1-2 most relevant search terms.
- `return_fields` (list[str] | None): Fields to return in results. Default: ["name", "node_type", "description"]
- `max_results` (int): Maximum number of results to return. Default 20 is optimal for most searches. Use up to 50 if extensive results are desired for comprehensive analysis.
- `query_type` (str): Type of entity to search for ("dataset", "file", "folder")
- `verbose` (bool): Whether to return full API response or formatted results

**Returns**: dict
    Dictionary containing query information and Synapse API results

*Documentation quality*: Complete

### `query_pubchem`
**Summary**: Query the PubChem PUG-REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about chemical compounds)
- `endpoint` (str, optional): Direct PubChem API endpoint to query)
- `max_results` (int): Maximum number of results to return)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_chembl`
**Summary**: Query the ChEMBL REST API using natural language, direct endpoint, or specific identifiers.

**Parameters**:
- `prompt` (str, optional): Natural language query about bioactivity data)
- `endpoint` (str, optional): Direct ChEMBL API endpoint to query)
- `chembl_id` (str, optional): Specific ChEMBL ID to query (e.g., 'CHEMBL25')
- `smiles` (str, optional): SMILES string for similarity/substructure search)
- `molecule_name` (str, optional): Molecule name for lookup)
- `max_results` (int): Maximum number of results to return)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_unichem`
**Summary**: Query the UniChem 2.0 REST API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, optional): Natural language query about chemical cross-references)
- `endpoint` (str, optional): Direct UniChem API endpoint to query)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_clinicaltrials`
**Summary**: Query the ClinicalTrials.gov API v2 using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, required): Natural language query about clinical trials)
- `endpoint` (str, optional): Direct ClinicalTrials.gov API endpoint to query)
- `max_results` (int): Maximum number of results to return)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_dailymed`
**Summary**: Query the DailyMed RESTful API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, optional): Natural language query about drug labeling information)
- `endpoint` (str, optional): Direct DailyMed API endpoint to query)
- `format` (str): Response format ('json' or 'xml')
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_quickgo`
**Summary**: Query the QuickGO API using natural language or a direct endpoint.

**Parameters**:
- `prompt` (str, optional): Natural language query about Gene Ontology terms, annotations, or gene products)
- `endpoint` (str, optional): Direct QuickGO API endpoint to query)
- `max_results` (int): Maximum number of results to return (max 100)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results or error information

*Documentation quality*: Complete

### `query_encode`
**Summary**: Query the ENCODE Portal API to help users locate functional genomics data.

**Parameters**:
- `prompt` (str, required): Natural language query about functional genomics data you want to find)
- `endpoint` (str, optional): Direct ENCODE Portal API endpoint to query)
- `max_results` (int): Maximum number of results to return (use "all" for all results)
- `verbose` (bool): Whether to return detailed results)

**Returns**: dict: Dictionary containing the query results with data location information

*Documentation quality*: Complete

## Genetics (11 functions)

### `liftover_coordinates`
**Summary**: Perform liftover of genomic coordinates between hg19 and hg38 formats with detailed intermediate steps.

**Parameters**:
- `chromosome` (str)
- `position` (int)
- `input_format` (str)
- `output_format` (str)
- `data_path` (str)

**Returns**: str: A detailed string explaining the steps and the final result or any error encountered.

*Documentation quality*: Complete

### `bayesian_finemapping_with_deep_vi`
**Summary**: Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference.

**Parameters**:
- `gwas_summary_path` (str): Path to CSV or TSV file containing GWAS summary statistics. Expected columns: - 'variant_id': Identifier for each variant - 'effect_size': Effect size (beta) for each variant - 'pvalue': P-value for each variant - 'se': Standard error for each variant (optional)
- `ld_matrix` (numpy.ndarray): Linkage disequilibrium matrix with pairwise correlations between variants.
- `n_iterations` (int, optional): Number of training iterations for the variational inference algorithm. Default is 5000.
- `learning_rate` (float, optional): Learning rate for the optimization algorithm. Default is 0.01.
- `hidden_dim` (int, optional): Hidden dimension size for the neural network. Default is 64.
- `credible_threshold` (float, optional): Threshold for defining the credible set (e.g., 0.95 for a 95% credible set). Default is 0.95.

**Returns**: str
    A detailed research log of the fine-mapping analysis including:
    - Number of variants analyzed
    - Top variants ranked by posterior inclusion probability
    - Credible set variants
    - Visualizations of the posterior distributions

*Documentation quality*: Complete

### `forward`

**Parameters**:
- `self`
- `x`

*Documentation quality*: Missing

### `elbo_loss`

**Parameters**:
- `self`
- `z_scores`
- `ld_matrix`
- `pips`
- `n_samples`

*Documentation quality*: Missing

### `analyze_cas9_mutation_outcomes`
**Summary**: Analyzes and categorizes mutations induced by Cas9 at target sites.

**Parameters**:
- `reference_sequences` (dict): Dictionary mapping sequence IDs to reference DNA sequences (strings)
- `edited_sequences` (dict of dict): Nested dictionary: {sequence_id: {read_id: sequence}} Contains the edited/mutated sequences for each reference
- `cell_line_info` (dict, optional): Dictionary mapping sequence IDs to cell line information (e.g., wildtype, knockout gene)
- `output_prefix` (str, optional): Prefix for output files

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_crispr_genome_editing`
**Summary**: Analyzes CRISPR-Cas9 genome editing results by comparing original and edited sequences.

**Parameters**:
- `original_sequence` (str): The original DNA sequence before CRISPR-Cas9 editing
- `edited_sequence` (str): The DNA sequence after CRISPR-Cas9 editing
- `guide_rna` (str): The CRISPR guide RNA (crRNA) sequence used for targeting
- `repair_template` (str, optional): The homology-directed repair template sequence, if used

**Returns**: str
    A research log summarizing the CRISPR-Cas9 editing analysis, including identified
    mutations and characterization of the edited loci

*Documentation quality*: Complete

### `simulate_demographic_history`
**Summary**: Simulate DNA sequences with specified demographic and coalescent histories using msprime.

**Parameters**:
- `num_samples`
- `sequence_length`
- `recombination_rate`
- `mutation_rate`
- `demographic_model`
- `demographic_params`
- `coalescent_model` (str): Type of coalescent model to use. Options: - "kingman": Standard Kingman coalescent - "beta": Beta-coalescent model
- `beta_coalescent_param` (float): Parameter for beta-coalescent model (required if coalescent_model="beta")
- `random_seed` (int): Seed for random number generator (for reproducibility)
- `output_file` (str): Filename to save the simulated sequences (VCF format)

**Returns**: str
    Research log summarizing the simulation parameters and results

*Documentation quality*: Complete

### `identify_transcription_factor_binding_sites`
**Summary**: Identifies binding sites for a specific transcription factor in a genomic sequence.

**Parameters**:
- `sequence` (str): The genomic DNA sequence to analyze
- `tf_name` (str): Name of the transcription factor to search for (e.g., 'Hsf1', 'GATA1')
- `threshold` (float, optional): Minimum score threshold for reporting binding sites (0.0-1.0, default: 0.8)
- `output_file` (str, optional): Path to save the results (default: None, results only in log)

**Returns**: str
    Research log detailing the binding site identification process and results

*Documentation quality*: Complete

### `fit_genomic_prediction_model`
**Summary**: Fit a linear mixed model for genomic prediction using genotype and phenotype data.

**Parameters**:
- `genotypes` (numpy.ndarray): Matrix of genotype data, with individuals in rows and markers in columns. Values are typically coded as 0, 1, 2 for additive models or with specific encoding for dominance effects.
- `phenotypes` (numpy.ndarray): Vector or matrix of phenotype data, with individuals in rows and traits in columns.
- `fixed_effects` (numpy.ndarray, optional): Matrix of fixed effects (e.g., environment, management), with individuals in rows and effects in columns.
- `model_type` (str, optional): Type of genetic model to fit: "additive" or "additive_dominance".
- `output_file` (str, optional): File name to save the results.

**Returns**: str
    Research log summarizing the genomic prediction analysis, including model parameters,
    variance components, breeding values, and prediction accuracy metrics.

*Documentation quality*: Complete

### `perform_pcr_and_gel_electrophoresis`
**Summary**: Performs PCR amplification of a target transgene and visualizes results using agarose gel electrophoresis.

**Parameters**:
- `genomic_dna` (str): Path to file containing genomic DNA sequence in FASTA format or the sequence itself
- `forward_primer` (str, optional): Forward primer sequence. If not provided, will be designed based on target_region
- `reverse_primer` (str, optional): Reverse primer sequence. If not provided, will be designed based on target_region
- `target_region` (tuple, optional): Tuple of (start, end) positions for the target region in the genomic DNA
- `annealing_temp` (float, default=58): Annealing temperature for PCR in °C
- `extension_time` (int, default=30): Extension time in seconds
- `cycles` (int, default=35): Number of PCR cycles
- `gel_percentage` (float, default=2.0): Percentage of agarose gel
- `output_prefix` (str, default="pcr_result"): Prefix for output files

**Returns**: str
    Research log summarizing the PCR and gel electrophoresis procedures and results

*Documentation quality*: Complete

### `analyze_protein_phylogeny`
**Summary**: Perform phylogenetic analysis on a set of protein sequences.

**Parameters**:
- `fasta_sequences` (str): Path to a FASTA file containing protein sequences or a string with FASTA-formatted sequences
- `output_dir` (str, optional): Directory to save output files (default: current directory)
- `alignment_method` (str, optional): Method for sequence alignment: "clustalw", "muscle", or "pre-aligned" (default: "clustalw")
- `tree_method` (str, optional): Method for tree construction: "iqtree" (default: "iqtree")

**Returns**: str
    Research log summarizing the phylogenetic analysis process

*Documentation quality*: Complete

## Genomics (25 functions)

### `unsupervised_celltype_transfer_between_scRNA_datasets`

**Parameters**:
- `path_to_annotated_h5ad` (str)
- `path_to_not_annotated_h5ad` (str)
- `ref_labels_key` (str)
- `query_batch_key` (str)
- `ref_batch_key` (str)
- `CELLTYPIST`
- `KNN_BBKNN`
- `KNN_HARMONY`
- `KNN_SCANORAMA`
- `KNN_SCVI`
- `ONCLASS`
- `Random_Forest`
- `SCANVI_POPV`
- `Support_Vector`
- `XGboost`
- `n_jobs` (int)
- `output_folder` (str)
- `n_samples_per_label` (int)

*Documentation quality*: Missing

### `interspecies_gene_conversion`
**Summary**: Convert ENSEMBL gene IDs between different species using BioMart homology mapping.

**Parameters**:
- `gene_list` (list[str]): List of ENSEMBL gene IDs to convert (e.g., ['ENSG00000007372', 'ENSG00000181449'])
- `source_species` (str): Source species name. Supported species: human, mouse, rat, zebrafish, fly, drosophila, worm, yeast, chicken, pig, cow, dog, macaque
- `target_species` (str): Target species name. Same supported species as source_species.

**Returns**: str
    Multi-line string containing the steps performed and file paths where
    results were saved. Returns empty string if source and target species are the same.

*Documentation quality*: Complete

### `generate_gene_embeddings_with_ESM_models`
**Summary**: Generate average protein embeddings for a list of Ensembl gene IDs.

**Parameters**:
- `ensembl_gene_ids` (list[str])
- `model_name` (str)
- `layer` (int)
- `save_path` (str | None)
- `batch_size` (int)
- `max_sequence_length` (int)

**Returns**: String containing the steps performed during the embedding generation process

*Documentation quality*: Complete

### `annotate_celltype_scRNA`
**Summary**: Annotate cell types based on gene markers and transferred labels using LLM.

**Parameters**:
- `adata_filename` (str): Name of the AnnData file containing scRNA-seq data)
- `data_dir` (str): Directory containing the data files)
- `data_info` (str): Information about the scRNA-seq data (e.g., "homo sapiens, brain tissue, normal")
- `data_lake_path` (str): Path to the data lake)
- `cluster`
- `llm` (str): Language model instance for cell type prediction, such as 'claude-3-haiku-20240307')
- `composition` (pd.DataFrame, optional): Transferred cell type composition for each cluster)

**Returns**: - str: Steps performed and file paths where results were saved

*Documentation quality*: Complete

### `annotate_celltype_with_panhumanpy`
**Summary**: Perform hierarchical cell type annotation using panhumanpy and Azimuth Neural Network.

**Parameters**:
- `adata_path` (str): Path to the AnnData file containing scRNA-seq data
- `feature_names_col` (str, optional): Column name in adata.var containing gene names (default: None, uses index)
- `refine` (bool, optional): Whether to perform label refinement for consistent granularity (default: True)
- `umap` (bool, optional): Whether to generate ANN embeddings and UMAP (default: True)
- `output_dir` (str, optional): Directory to save results (default: "./output")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `conda_env_exists`

**Parameters**:
- `env_name`

*Documentation quality*: Missing

### `create_panhumanpy_env`

**Parameters**:
- `env_name`

*Documentation quality*: Missing

### `create_scvi_embeddings_scRNA`

**Parameters**:
- `adata_filename`
- `batch_key`
- `label_key`
- `data_dir`

*Documentation quality*: Missing

### `create_harmony_embeddings_scRNA`

**Parameters**:
- `adata_filename`
- `batch_key`
- `data_dir`

*Documentation quality*: Missing

### `get_uce_embeddings_scRNA`
**Summary**: The UCE embeddings are usually our default tools to get cell embeddings, we map UCE embeddings to IMA referece dataset and get the cell types for a better understanding.

**Parameters**:
- `adata_filename`
- `data_dir`
- `DATA_ROOT`
- `custom_args`

*Documentation quality*: Complete

### `map_to_ima_interpret_scRNA`
**Summary**: Map cell embeddings from the input dataset to the Integrated Megascale Atlas reference dataset using UCE embeddings.

**Parameters**:
- `adata_filename`
- `data_dir`
- `custom_args`

*Documentation quality*: Complete

### `custom_mode`

**Parameters**:
- `x`

*Documentation quality*: Missing

### `get_rna_seq_archs4`
**Summary**: Given a gene name, this function returns the steps it performs and the max K transcripts-per-million (TPM)

**Parameters**:
- `gene_name` (str)
- `K` (int)

**Returns**: - str: The steps performed and the result.

*Documentation quality*: Complete

### `get_gene_set_enrichment_analysis_supported_database_list`

*Documentation quality*: Missing

### `gene_set_enrichment_analysis`
**Summary**: Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.

**Parameters**:
- `genes` (list)
- `top_k` (int)
- `database` (str): Popular options include: - 'pathway'      (KEGG_2021_Human) - 'transcription'   (ChEA_2016) - 'ontology'     (GO_Biological_Process_2021) - 'diseases_drugs'  (GWAS_Catalog_2019) - 'celltypes'     (PanglaoDB_Augmented_2021) - 'kinase_interactions' (KEA_2015) You can use get_gene_set_enrichment_analysis_supported_database_list tool to get the list of supported databases.
- `background_list` (list)
- `plot` (bool)

**Returns**: - str: The steps performed and the top K enrichment results.

*Documentation quality*: Complete

### `analyze_chromatin_interactions`
**Summary**: Analyze chromatin interactions from Hi-C data to identify enhancer-promoter interactions and TADs.

**Parameters**:
- `hic_file_path` (str): Path to the Hi-C data file (.cool or .hic format)
- `regulatory_elements_bed` (str): Path to BED file containing genomic coordinates of regulatory elements (enhancers, promoters, CTCF sites, etc.)
- `output_dir` (str): Directory to save output files (default: "./output")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `get_matrix`

**Parameters**:
- `chrom`
- `balance_if_possible`

*Documentation quality*: Missing

### `analyze_comparative_genomics_and_haplotypes`
**Summary**: Perform comparative genomics and haplotype analysis on multiple genome samples.

**Parameters**:
- `sample_fasta_files` (list of str): Paths to FASTA files containing whole-genome sequences to be analyzed
- `reference_genome_path` (str): Path to the reference genome FASTA file
- `output_dir` (str, optional): Directory to store output files (default: "./output")

**Returns**: str
    A research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `perform_chipseq_peak_calling_with_macs2`
**Summary**: Perform ChIP-seq peak calling using MACS2 to identify genomic regions with significant binding.

**Parameters**:
- `chip_seq_file` (str): Path to the ChIP-seq read data file (BAM, BED, or other supported format)
- `control_file` (str): Path to the control/input data file (BAM, BED, or other supported format)
- `output_name` (str, optional): Prefix for output files (default: "macs2_output")
- `genome_size` (str, optional): Effective genome size shorthand: 'hs' for human, 'mm' for mouse, etc. (default: "hs")
- `q_value` (float, optional): q-value (minimum FDR) cutoff for peak calling (default: 0.05)

**Returns**: str
    A research log summarizing the peak calling process and results

*Documentation quality*: Complete

### `find_enriched_motifs_with_homer`
**Summary**: Find DNA sequence motifs enriched in genomic regions using the HOMER motif discovery software.

**Parameters**:
- `peak_file` (str): Path to peak file in BED format containing genomic regions to analyze for motif enrichment
- `genome` (str, optional): Reference genome for sequence extraction (default: "hg38")
- `background_file` (str, optional): Path to BED file with background regions for comparison. If None, HOMER will generate random background sequences automatically (default: None)
- `motif_length` (str, optional): Comma-separated list of motif lengths to discover (default: "8,10,12")
- `output_dir` (str, optional): Directory to save output files (default: "./homer_motifs")
- `num_motifs` (int, optional): Number of motifs to find (default: 10)
- `threads` (int, optional): Number of CPU threads to use (default: 4)

**Returns**: str
    A research log summarizing the motif discovery process and results

*Documentation quality*: Complete

### `analyze_genomic_region_overlap`
**Summary**: Analyze overlaps between two or more sets of genomic regions.

**Parameters**:
- `region_sets` (list): List of genomic region sets. Each item can be either: - A string path to a BED file - A list of tuples/lists with format (chrom, start, end) or (chrom, start, end, name)
- `output_prefix` (str, optional): Prefix for output files (default: "overlap_analysis")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `generate_embeddings_with_state`
**Summary**: Generate State embeddings for single-cell RNA-seq data using the SE-600M model.

**Parameters**:
- `adata_filename` (str): Name of the input AnnData file (.h5ad format)
- `data_dir` (str): Directory containing the input data file
- `model_folder` (str): Directory where the SE-600M model will be downloaded and stored
- `output_filename` (str, optional): Name of the output file. If None, will use input filename with '_state_embeddings' suffix
- `checkpoint` (str, optional): Path to the specific model checkpoint. If None, uses the latest checkpoint in model_folder
- `embed_key` (str, default="X_state"): Name of key to store embeddings in the output AnnData object
- `protein_embeddings` (str, optional): Path to protein embeddings override (.pt). If omitted, auto-detects in model folder
- `batch_size` (int, default=500): Batch size for embedding forward pass. Increase to use more VRAM and speed up embedding

**Returns**: str
    Research log summarizing the steps performed and results

*Documentation quality*: Complete

### `generate_transcriptformer_embeddings`
**Summary**: Generate Transcriptformer embeddings for single-cell RNA-seq data.

**Parameters**:
- `adata_filename` (str): Name of the input AnnData file (.h5ad format)
- `data_dir` (str): Directory containing the input data file
- `output_filename` (str): Name of the output embeddings file. If None, will use input filename with '_transcriptformer_embeddings' suffix
- `model_type` (str): Type of transcriptformer model to download and use. Options: "tf-sapiens", "tf-exemplar", "tf-metazoa" (default: "tf-sapiens")
- `checkpoint_path` (str): Path to the transcriptformer checkpoint directory. If None, will use "./checkpoints/{model_type}" (default: None)
- `batch_size` (int): Batch size for inference (default: 8)
- `precision` (str): Precision for inference. Options: "16-mixed", "32" (default: "16-mixed")
- `clip_counts` (int): Maximum count value to clip to (default: 30)
- `embedding_layer_index` (int): Which layer to extract embeddings from (default: -1, last layer)
- `num_gpus` (int): Number of GPUs to use (default: 1)
- `n_data_workers` (int): Number of data loading workers (default: 0)
- `gene_col_name` (str): Column name in AnnData.var containing gene identifiers (default: "ensembl_id")
- `pretrained_embedding` (str): Path to pretrained embeddings for out-of-distribution species (default: None)
- `filter_to_vocabs` (bool): Whether to filter genes to only those in the vocabulary (default: True)
- `use_raw` (str): Whether to use raw counts from AnnData.raw.X (True), adata.X (False), or auto-detect (None/auto) (default: "None")
- `emb_type` (str): Type of embeddings to extract: 'cell' for mean-pooled cell embeddings or 'cge' for contextual gene embeddings (default: "cell")
- `remove_duplicate_genes` (bool): Remove duplicate genes if found instead of raising an error (default: False)
- `oom_dataloader` (bool): Use map-style out-of-memory DataLoader (DistributedSampler-friendly) (default: False)

**Returns**: str
    Path to the generated embeddings file

*Documentation quality*: Complete

### `is_model_downloaded`
**Summary**: Check if model is already downloaded by looking for key files

**Parameters**:
- `checkpoint_path`
- `model_type`

*Documentation quality*: Complete

### `check_ensembl_patterns`

**Parameters**:
- `gene_index`

*Documentation quality*: Missing

## Glycoengineering (3 functions)

### `find_n_glycosylation_motifs`
**Summary**: Scan a protein sequence for N-linked glycosylation sequons (N-X-[S/T]).

**Parameters**:
- `sequence` (str)
- `allow_overlap` (bool)

**Returns**: - Research log string summarizing motif locations and counts

*Documentation quality*: Complete

### `predict_o_glycosylation_hotspots`
**Summary**: Heuristic O-glycosylation hotspot scoring.

**Parameters**:
- `sequence` (str)
- `window` (int)
- `min_st_fraction` (float)
- `disallow_proline_next` (bool)

**Returns**: - Research log string with candidate sites and scores

*Documentation quality*: Complete

### `list_glycoengineering_resources`
**Summary**: Curate and summarize external glycoengineering tools and resources.

*Documentation quality*: Partial

## Immunology (13 functions)

### `analyze_atac_seq_differential_accessibility`
**Summary**: Perform ATAC-seq peak calling and differential accessibility analysis using MACS2.

**Parameters**:
- `treatment_bam` (str): Path to the treatment condition BAM file with aligned ATAC-seq reads
- `control_bam` (str): Path to the control condition BAM file with aligned ATAC-seq reads
- `output_dir` (str): Directory to save output files (default: "./atac_results")
- `genome_size` (str): Genome size parameter for MACS2 (default: "hs" for human)
- `q_value` (float): q-value cutoff for peak detection (default: 0.05)
- `name_prefix` (str): Prefix for output file names (default: "atac")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_bacterial_growth_curve`
**Summary**: Analyzes bacterial growth curve data to determine growth parameters.

**Parameters**:
- `time_points` (list or numpy.ndarray): Time points of measurements in hours
- `od_values` (list or numpy.ndarray): Optical density measurements corresponding to each time point
- `strain_name` (str): Name of the bacterial strain being analyzed
- `output_dir` (str, optional): Directory where output files will be saved (default: current directory)

**Returns**: str
    A research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `logistic_growth`
**Summary**: Logistic growth model: N(t) = K / (1 + ((K - N0) / N0) * exp(-r*t)).

**Parameters**:
- `t` (time)
- `k` (carrying capacity (maximum population size)
- `n0` (initial population)
- `r` (growth rate)

*Documentation quality*: Complete

### `isolate_purify_immune_cells`
**Summary**: Simulates the isolation and purification of immune cells from tissue samples.

**Parameters**:
- `tissue_type` (str): The type of tissue sample (e.g., 'adipose', 'kidney', 'liver', 'lung', 'spleen')
- `target_cell_type` (str): The immune cell population to isolate (e.g., 'macrophages', 'leukocytes', 'T cells')
- `enzyme_type` (str, optional): The enzyme used for tissue digestion (default: 'collagenase')
- `macs_antibody` (str, optional): Specific antibody for magnetic-assisted cell sorting (default: None, will be set based on target cell type)
- `digestion_time_min` (int, optional): Digestion time in minutes (default: 45)

**Returns**: str
    A research log describing the cell isolation and purification process

*Documentation quality*: Complete

### `estimate_cell_cycle_phase_durations`
**Summary**: Estimate cell cycle phase durations using dual-nucleoside pulse labeling data and mathematical modeling.

**Parameters**:
- `flow_cytometry_data` (dict): Dictionary containing experimental data from flow cytometry with EdU and BrdU labeling. Expected format:: { 'time_points': list of time points (hours), 'edu_positive': list of percentages of EdU+ cells at each time point, 'brdu_positive': list of percentages of BrdU+ cells at each time point, 'double_positive': list of percentages of EdU+BrdU+ cells at each time point }
- `initial_estimates` (dict): Initial estimates for cell cycle phase durations and death rates. Expected format:: { 'g1_duration': float (hours), 's_duration': float (hours), 'g2m_duration': float (hours), 'death_rate': float (fraction per hour) }

**Returns**: str
    Research log summarizing the cell cycle phase duration estimation process and results.

*Documentation quality*: Complete

### `objective_function`

**Parameters**:
- `params`

*Documentation quality*: Missing

### `simulate_cell_population`

**Parameters**:
- `time_points`
- `g1_duration`
- `s_duration`
- `g2m_duration`
- `death_rate`

*Documentation quality*: Missing

### `track_immune_cells_under_flow`
**Summary**: Track immune cells under flow conditions and classify their behaviors.

**Parameters**:
- `image_sequence_path`
- `output_dir`
- `pixel_size_um`
- `time_interval_sec`
- `flow_direction`

**Returns**: str: Log of the analysis process.

*Documentation quality*: Complete

### `analyze_cfse_cell_proliferation`
**Summary**: Analyze CFSE-labeled cell samples to quantify cell division and proliferation.

**Parameters**:
- `fcs_file_path` (str): Path to the FCS file containing flow cytometry data from CFSE-labeled cells
- `cfse_channel` (str, optional): Name of the channel containing CFSE fluorescence data (default: 'FL1-A')
- `lymphocyte_gate` (tuple or None, optional): Tuple of (min_fsc, max_fsc, min_ssc, max_ssc) for lymphocyte gating If None, automatic gating will be attempted (default: None)

**Returns**: str
    Research log summarizing the analysis steps and results, including cell division
    index and percentage of proliferating cells

*Documentation quality*: Complete

### `analyze_cytokine_production_in_cd4_tcells`
**Summary**: Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.

**Parameters**:
- `fcs_files_dict` (dict): Dictionary mapping stimulation conditions to FCS file paths. Expected keys: 'unstimulated', 'Mtb300', 'CMV', 'SEB' Example: {'unstimulated': 'path/to/unstim.fcs', 'Mtb300': 'path/to/mtb.fcs'}
- `output_dir` (str, optional): Directory to save the results file (default: './results')

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_ebv_antibody_titers`
**Summary**: Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.

**Parameters**:
- `raw_od_data` (dict): Dictionary containing optical density (OD) readings for each sample. Format: {sample_id: {'VCA_IgG': float, 'VCA_IgM': float, 'EA_IgG': float, 'EA_IgM': float, 'EBNA1_IgG': float, 'EBNA1_IgM': float}}
- `standard_curve_data` (dict): Dictionary containing standard curve data for each antibody type. Format: {antibody_type: [(concentration, OD), ...]}
- `sample_metadata` (dict): Dictionary containing metadata for each sample. Format: {sample_id: {'group': str, 'collection_date': str}}
- `output_dir` (str, optional): Directory to save output files. Default is current directory.

**Returns**: str
    Research log summarizing the analysis process and results.

*Documentation quality*: Complete

### `analyze_cns_lesion_histology`
**Summary**: Analyzes histological images of CNS lesions to quantify immune cell infiltration,

**Parameters**:
- `image_path` (str): Path to the microscopy image file of brain or spinal cord tissue section
- `output_dir` (str, optional): Directory to save output files (default: "./output")
- `stain_type` (str, optional): Type of histological stain used (default: "H&E", other options: "LFB", "IHC")

**Returns**: str
    Research log summarizing the analysis steps, findings, and saved file paths

*Documentation quality*: Complete

### `analyze_immunohistochemistry_image`
**Summary**: Analyzes immunohistochemistry images to quantify protein expression and spatial distribution.

**Parameters**:
- `image_path` (str): Path to the microscopy image of tissue section stained with antibodies
- `protein_name` (str, optional): Name of the protein being analyzed (default: "Unknown")
- `output_dir` (str, optional): Directory to save output files (default: "./ihc_results/")

**Returns**: str
    Research log summarizing the analysis steps, results, and saved file locations

*Documentation quality*: Complete

## Lab_Automation (6 functions)

### `pick_first`

**Parameters**:
- `keywords` (list[str])

*Documentation quality*: Missing

### `get_pylabrobot_documentation_liquid`
**Summary**: Get the documentation for a specific section of the PyLabRobot tutorial.

*Documentation quality*: Partial

### `get_pylabrobot_documentation_material`

*Documentation quality*: Missing

### `test_pylabrobot_script`
**Summary**: Test a PyLabRobot script using simulation and validation.

**Parameters**:
- `script_input` (str)
- `enable_tracking` (bool)
- `timeout_seconds` (int)
- `save_test_report` (bool)
- `test_report_dir` (str)

**Returns**: dict: Dictionary containing:
        - success (bool): Whether the script passed all tests
        - test_results (dict): Detailed test results for each validation step
        - execution_summary (dict): Summary of operations performed
        - errors (list): List of errors encountered
        - warnings (list): List of warnings
        - test_report_path (str): Path to saved report if requested

*Documentation quality*: Complete

### `target`

*Documentation quality*: Missing

### `run_async`

*Documentation quality*: Missing

## Literature (8 functions)

### `fetch_supplementary_info_from_doi`
**Summary**: Fetches supplementary information for a paper given its DOI and returns a research log.

**Parameters**:
- `doi` (str)
- `output_dir` (str)

**Returns**: dict: A dictionary containing a research log and the downloaded file paths.

*Documentation quality*: Complete

### `query_arxiv`
**Summary**: Query arXiv for papers based on the provided search query.

**Parameters**:
- `query` (str)
- `max_papers` (int)

**Returns**: - str: The formatted search results or an error message.

*Documentation quality*: Complete

### `query_scholar`
**Summary**: Query Google Scholar for papers based on the provided search query.

**Parameters**:
- `query` (str)

**Returns**: - str: The first search result formatted or an error message.

*Documentation quality*: Complete

### `query_pubmed`
**Summary**: Query PubMed for papers based on the provided search query.

**Parameters**:
- `query` (str)
- `max_papers` (int)
- `max_retries` (int)

**Returns**: - str: The formatted search results or an error message.

*Documentation quality*: Complete

### `search_google`
**Summary**: Search using Google search.

**Parameters**:
- `query` (str)
- `num_results` (int)
- `language` (str)

**Returns**: List[dict]: List of dictionaries containing search results with title and URL

*Documentation quality*: Complete

### `advanced_web_search_claude`
**Summary**: Initiate an advanced web search by launching a specialized agent to collect relevant information and citations through multiple rounds of web searches for a given query.

**Parameters**:
- `query` (str): The search phrase you want Claude to look up.
- `max_searches` (int): Upper-bound on searches Claude may issue inside this request.
- `max_retries` (int): Maximum number of retry attempts with exponential backoff.

**Returns**: full_text : str
    A formatted string containing the full text response from Claude and the citations.

*Documentation quality*: Complete

### `extract_url_content`
**Summary**: Extract the text content of a webpage using requests and BeautifulSoup.

**Parameters**:
- `url` (str)

**Returns**: Text content of the webpage

*Documentation quality*: Complete

### `extract_pdf_content`
**Summary**: Extract the text content of a PDF file given its URL.

**Parameters**:
- `url` (str)

**Returns**: The extracted text content from the PDF

*Documentation quality*: Complete

## Microbiology (16 functions)

### `optimize_anaerobic_digestion_process`
**Summary**: Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.

**Parameters**:
- `waste_characteristics` (dict): Dictionary containing waste characteristics such as: - total_solids (float): Total solids content (%) - volatile_solids (float): Volatile solids content (%) - cod (float): Chemical oxygen demand (mg/L)
- `operational_parameters` (dict): Dictionary containing operational parameters and their ranges: - hrt (tuple): Hydraulic retention time range in days (min, max) - olr (tuple): Organic loading rate range in kg VS/(m³·d) (min, max) - if_ratio (tuple): Inoculum-to-feedstock ratio range (min, max) - temperature (tuple): Temperature range in °C (min, max) - ph (tuple): pH range (min, max)
- `target_output` (str, optional): Target output to maximize, either 'vfa_production' or 'methane_yield'. Default is 'methane_yield'.
- `optimization_method` (str, optional): Method used for optimization, either 'rsm' (Response Surface Methodology) or 'genetic' (Genetic Algorithm). Default is 'rsm'.

**Returns**: str
    Research log summarizing the optimization process and results.

*Documentation quality*: Complete

### `vfa_production_model`

**Parameters**:
- `params`

*Documentation quality*: Missing

### `methane_yield_model`

**Parameters**:
- `params`

*Documentation quality*: Missing

### `analyze_arsenic_speciation_hplc_icpms`
**Summary**: Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.

**Parameters**:
- `sample_data` (dict): Dictionary containing sample data with keys as sample IDs and values as dictionaries with retention times (in minutes) as keys and signal intensities as values.
- `sample_name` (str, optional): Name of the sample being analyzed (default: "Unknown Sample")
- `calibration_data` (dict, optional): Dictionary containing calibration standards data with known concentrations for each arsenic species. If None, default calibration values will be used.

**Returns**: str
    A research log summarizing the steps of the analysis and results.

*Documentation quality*: Complete

### `count_bacterial_colonies`
**Summary**: Count bacterial colonies from an image of agar plate using computer vision techniques.

**Parameters**:
- `image_path` (str): Path to the image file containing bacterial colonies on agar plate
- `dilution_factor` (float): Dilution factor of the plated sample (default=1)
- `plate_area_cm2` (float): Area of the agar plate in square centimeters (default=65.0, standard Petri dish)
- `output_dir` (str): Directory to save output images and results (default="./output")

**Returns**: str
    Research log summarizing the colony counting process and results

*Documentation quality*: Complete

### `annotate_bacterial_genome`
**Summary**: Annotate a bacterial genome using Prokka to identify genes, proteins, and functional features.

**Parameters**:
- `genome_file_path` (str): Path to the assembled genome sequence file in FASTA format
- `output_dir` (str, optional): Directory where annotation results will be saved (default: "annotation_results")
- `genus` (str, optional): Genus name for the organism (default: "")
- `species` (str, optional): Species name for the organism (default: "")
- `strain` (str, optional): Strain identifier (default: "")
- `prefix` (str, optional): Prefix for output files (default: "")

**Returns**: str
    Research log summarizing the annotation process and results

*Documentation quality*: Complete

### `enumerate_bacterial_cfu_by_serial_dilution`
**Summary**: Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.

**Parameters**:
- `initial_sample_volume_ml` (float): Volume of the initial bacterial sample in milliliters
- `estimated_concentration` (float): Estimated concentration of bacteria in the initial sample (CFU/mL)
- `dilution_factor` (int): Factor by which each dilution reduces the concentration (typically 10)
- `num_dilutions` (int): Number of serial dilutions to perform
- `spots_per_dilution` (int): Number of replicate spots to plate for each dilution
- `output_file` (str): Filename to save the CFU enumeration results

**Returns**: str
    Research log summarizing the CFU enumeration process

*Documentation quality*: Complete

### `model_bacterial_growth_dynamics`
**Summary**: Model bacterial population dynamics over time using ordinary differential equations.

**Parameters**:
- `initial_population` (float): Initial bacterial population size (CFU/ml or cells)
- `growth_rate` (float): Bacterial growth rate (per hour)
- `clearance_rate` (float): Rate at which bacteria are cleared from the system (per hour)
- `niche_size` (float): Maximum carrying capacity of the environment (CFU/ml or cells)
- `simulation_time` (float, optional): Total simulation time in hours (default: 24)
- `time_step` (float, optional): Time step for simulation output (default: 0.1)

**Returns**: str
    Research log summarizing the bacterial growth dynamics simulation

*Documentation quality*: Complete

### `bacterial_dynamics`

**Parameters**:
- `t`
- `N`

*Documentation quality*: Missing

### `quantify_biofilm_biomass_crystal_violet`
**Summary**: Quantifies biofilm biomass using crystal violet staining assay data.

**Parameters**:
- `od_values` (list or numpy.ndarray): Optical density measurements from crystal violet staining. Each value represents the absorbance reading for a sample.
- `sample_names` (list, optional): Names of the biofilm samples corresponding to od_values. If None, samples will be labeled as Sample 1, Sample 2, etc.
- `control_index` (int, optional): Index of the negative control sample in od_values. Default is 0.
- `save_path` (str, optional): Path to save the results. If None, results won't be saved to a file.

**Returns**: str
    Research log detailing the quantification process and results.

*Documentation quality*: Complete

### `segment_and_analyze_microbial_cells`
**Summary**: Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.

**Parameters**:
- `image_path` (str): Path to the fluorescence microscopy image file
- `output_dir` (str, optional): Directory to save output files (default: './output')
- `min_cell_size` (int, optional): Minimum cell size in pixels to filter noise (default: 50)

**Returns**: str
    Research log summarizing the segmentation process, metrics calculated, and output file paths

*Documentation quality*: Complete

### `segment_cells_with_deep_learning`
**Summary**: Perform cell segmentation on fluorescence microscopy images using deep learning.

**Parameters**:
- `image_path` (str): Path to the fluorescence microscopy image file
- `model_type` (str, optional): Name of the pre-trained model to use (default: 'bact_fluor_omni') Options include: 'bact_fluor_omni', 'cyto', 'nuclei', etc.
- `diameter` (float, optional): Expected diameter of cells in pixels. If None, diameter is automatically estimated.
- `save_dir` (str, optional): Directory to save segmentation results (default: 'segmentation_results')

**Returns**: str
    Research log detailing the segmentation process and results

*Documentation quality*: Complete

### `simulate_generalized_lotka_volterra_dynamics`
**Summary**: Simulate microbial community dynamics using the Generalized Lotka-Volterra (gLV) model.

**Parameters**:
- `initial_abundances` (numpy.ndarray): Initial abundances of each microbial species (1D array)
- `growth_rates` (numpy.ndarray): Intrinsic growth rates for each microbial species (1D array)
- `interaction_matrix` (numpy.ndarray): Matrix of interaction coefficients where A[i,j] represents the effect of species j on species i (2D array)
- `time_points` (numpy.ndarray): Time points at which to evaluate the model
- `output_file` (str, optional): Filename to save the simulation results (default: "glv_simulation_results.csv")

**Returns**: str
    Research log summarizing the simulation process and results

*Documentation quality*: Complete

### `glv_equations`

**Parameters**:
- `abundances`
- `t`
- `growth_rates`
- `interaction_matrix`

*Documentation quality*: Missing

### `predict_rna_secondary_structure`
**Summary**: Predict the secondary structure of an RNA molecule using ViennaRNA.

**Parameters**:
- `rna_sequence` (str): The RNA sequence (consisting of A, U, G, C nucleotides)
- `output_prefix` (str, optional): Prefix for output files (default: "rna_structure")

**Returns**: str
    A research log summarizing the prediction process and results

*Documentation quality*: Complete

### `simulate_microbial_population_dynamics`
**Summary**: Performs stochastic simulation of microbial population dynamics using the Gillespie algorithm.

**Parameters**:
- `initial_populations` (list of int): Initial population sizes for each microbial species
- `growth_rates` (list of float): Per capita growth rates for each species
- `clearance_rates` (list of float): Per capita death/clearance rates for each species
- `carrying_capacities` (list of float): Maximum sustainable population for each species
- `max_time` (float, optional): Maximum simulation time (default: 100)
- `num_simulations` (int, optional): Number of stochastic simulations to run (default: 100)
- `time_points` (int, optional): Number of time points to record for trajectories (default: 100)

**Returns**: str
    Research log summarizing the simulation results, including extinction probabilities and timelines

*Documentation quality*: Complete

## Molecular_Biology (28 functions)

### `annotate_open_reading_frames`
**Summary**: Find all Open Reading Frames (ORFs) in a DNA sequence using Biopython.

**Parameters**:
- `sequence`
- `min_length`
- `search_reverse`
- `filter_subsets`

**Returns**: dict: Dictionary containing:
        - explanation: Explanation of the output fields
        - summary_stats: Statistical overview of found ORFs
        - orfs: List of all found ORFs, where each ORF contains:
            - sequence: Nucleotide sequence of the ORF
            - aa_sequence: Translated amino acid sequence
            - start: Start position in original sequence (0-based)
            - end: End position in original sequence
            - strand: '+' for forward strand, '-' for reverse complement
            - frame: Reading frame (1,2,3 for forward; -1,-2,-3 for reverse)

*Documentation quality*: Complete

### `find_orfs_in_frame`
**Summary**: Helper function to find ORFs in a specific frame.

**Parameters**:
- `seq_str`
- `frame`
- `strand`

*Documentation quality*: Complete

### `annotate_plasmid`
**Summary**: Annotate a DNA sequence using pLannotate's command-line interface.

**Parameters**:
- `sequence` (str)
- `is_circular` (bool)

**Returns**: Dict: Dictionary containing annotation results or None if annotation fails

*Documentation quality*: Complete

### `get_gene_coding_sequence`
**Summary**: Retrieves the coding sequence(s) of a specified gene from NCBI Entrez.

**Parameters**:
- `gene_name` (str)
- `organism` (str)
- `email` (str)

**Returns**: List of dictionaries containing:
        - refseq_id: RefSeq ID of the gene
        - sequence: Coding sequence of the gene

*Documentation quality*: Complete

### `search_gene`
**Summary**: Search for gene ID in NCBI database.

*Documentation quality*: Partial

### `get_refseq_id`
**Summary**: Get RefSeq ID from gene record.

**Parameters**:
- `gene_id` (str)

*Documentation quality*: Complete

### `get_coding_sequences`
**Summary**: Extract coding sequences from RefSeq record.

**Parameters**:
- `refseq_id` (str)

*Documentation quality*: Complete

### `get_plasmid_sequence`
**Summary**: Unified function to retrieve plasmid sequences from either Addgene or NCBI.

**Parameters**:
- `identifier` (str)
- `is_addgene` (bool)

**Returns**: Optional[Dict[str, Any]]: The plasmid sequence and metadata if found, None otherwise

*Documentation quality*: Complete

### `align_sequences`
**Summary**: Align short sequences (primers) to a longer sequence, allowing for one mismatch.

**Parameters**:
- `long_seq` (str)
- `short_seqs` (str | list[str])

**Returns**: List[Dict]: List of alignment results for each short sequence, including:
        - explanation: Explanation of the output fields
        - sequence: the short sequence that was aligned
        - alignments: list of dictionaries containing:
            - position: 0-based start position in the target sequence
            - strand: '+' for forward strand, '-' for reverse complement
            - mismatches: list of tuples (position, expected_base, found_base)
              for any mismatches

*Documentation quality*: Complete

### `reverse_complement`
**Summary**: Helper function to get reverse complement of a sequence.

**Parameters**:
- `seq`

*Documentation quality*: Complete

### `pcr_simple`
**Summary**: Simulate PCR amplification with given primers and sequence.

**Parameters**:
- `sequence` (str)
- `forward_primer` (str)
- `reverse_primer` (str)
- `circular` (bool)

**Returns**: dict: Results of PCR simulation including products and primer binding details

*Documentation quality*: Complete

### `digest_sequence`
**Summary**: Simulates restriction enzyme digestion using Biopython's catalyze method and returns the resulting DNA fragments.

**Parameters**:
- `dna_sequence` (str)
- `enzyme_names` (list[str])
- `is_circular` (bool)

**Returns**: Dict: Dictionary containing the digestion fragments and their properties including positions

*Documentation quality*: Complete

### `find_restriction_sites`
**Summary**: Identifies restriction enzyme sites in a given DNA sequence for specified enzymes.

**Parameters**:
- `dna_sequence` (str)
- `enzymes` (list[str])
- `is_circular` (bool)

**Returns**: Dict: Dictionary containing all identified restriction sites

*Documentation quality*: Complete

### `find_restriction_enzymes`
**Summary**: Finds common restriction enzyme sites in a DNA sequence.

**Parameters**:
- `sequence` (str)
- `is_circular` (bool)

**Returns**: Dict[str, list]: Dictionary of enzymes and their cut positions

*Documentation quality*: Complete

### `find_sequence_mutations`
**Summary**: Compare query sequence against reference sequence to identify mutations.

**Parameters**:
- `query_sequence`
- `reference_sequence`
- `query_start`

**Returns**: list: List of mutations in format RefAA_Position_QueryAA

*Documentation quality*: Complete

### `design_knockout_sgrna`
**Summary**: Design sgRNAs for CRISPR knockout by searching pre-computed sgRNA libraries.

**Parameters**:
- `gene_name` (str)
- `data_lake_path` (str)
- `species` (str)
- `num_guides` (int)

**Returns**: Dict: Dictionary containing:
        - explanation: Explanation of the output fields
        - gene_name: Target gene name
        - species: Target species
        - guides: List of sgRNA sequences

*Documentation quality*: Complete

### `get_oligo_annealing_protocol`
**Summary**: Return a standard protocol for annealing oligonucleotides without phosphorylation.

**Returns**: Dict: Dictionary containing detailed protocol steps for oligo annealing

*Documentation quality*: Partial

### `get_golden_gate_assembly_protocol`
**Summary**: Return a customized protocol for Golden Gate assembly based on the number of inserts

**Parameters**:
- `num_inserts` (int)
- `enzyme_name` (str)
- `vector_length` (int)
- `vector_amount_ng` (float)
- `insert_lengths` (list[int])
- `is_library_prep` (bool)

**Returns**: Dict: Dictionary containing detailed protocol steps for Golden Gate assembly

*Documentation quality*: Complete

### `get_bacterial_transformation_protocol`
**Summary**: Return a standard protocol for bacterial transformation.

**Parameters**:
- `antibiotic` (str)
- `is_repetitive` (bool)

**Returns**: Dict: Dictionary containing detailed protocol steps for bacterial transformation

*Documentation quality*: Complete

### `design_primer`
**Summary**: Design a single primer within the given sequence window.

**Parameters**:
- `sequence` (str)
- `start_pos` (int)
- `primer_length` (int)
- `min_gc` (float)
- `max_gc` (float)
- `min_tm` (float)
- `max_tm` (float)
- `search_window` (int)

**Returns**: Optional[Dict[str, Any]]: Dictionary with primer information or None if no suitable primer found

*Documentation quality*: Complete

### `design_verification_primers`
**Summary**: Design Sanger sequencing primers to verify a specific region in a plasmid.

**Parameters**:
- `plasmid_sequence` (str)
- `target_region` (tuple[int, int])
- `existing_primers` (list[dict[str, str]] | None)
- `is_circular` (bool)
- `coverage_length` (int)
- `primer_length` (int)
- `min_gc` (float)
- `max_gc` (float)
- `min_tm` (float)
- `max_tm` (float)

**Returns**: Dict: Dictionary containing:
        - target_region: The region to be verified
        - recommended_primers: List of primers to use (from existing and/or newly designed)
        - coverage_map: How the primers cover the target region

*Documentation quality*: Complete

### `is_position_covered`
**Summary**: Check if a position is covered by any region.

**Parameters**:
- `pos`
- `covered_regions`

*Documentation quality*: Complete

### `is_region_fully_covered`
**Summary**: Check if the target region is fully covered.

**Parameters**:
- `covered_regions`
- `start`
- `end`

*Documentation quality*: Complete

### `merge_overlapping_regions`
**Summary**: Merge overlapping regions in the list.

**Parameters**:
- `regions`

*Documentation quality*: Complete

### `design_golden_gate_oligos`
**Summary**: Design oligos for Golden Gate assembly by identifying backbone overhangs

**Parameters**:
- `backbone_sequence` (str)
- `insert_sequence` (str)
- `enzyme_name` (str)
- `is_circular` (bool)

**Returns**: Dict: Dictionary containing overhang information and designed oligos

*Documentation quality*: Complete

### `reverse_complement`
**Summary**: Get the reverse complement of a DNA sequence.

**Parameters**:
- `seq`

*Documentation quality*: Complete

### `golden_gate_assembly`
**Summary**: Simulate Golden Gate assembly to predict final construct sequences.

**Parameters**:
- `backbone_sequence` (str)
- `enzyme_name` (str)
- `fragments` (list[dict[str, str]])
- `is_circular` (bool)

**Returns**: Dict: Dictionary containing:
        - success: Boolean indicating if assembly was successful
        - assembled_sequence: The final assembled sequence
        - message: Error message if assembly failed

*Documentation quality*: Complete

### `reverse_complement`
**Summary**: Get the reverse complement of a DNA sequence.

**Parameters**:
- `seq`

*Documentation quality*: Complete

## Pathology (7 functions)

### `analyze_aortic_diameter_and_geometry`
**Summary**: Analyze aortic diameter and geometry from cardiovascular imaging data.

**Parameters**:
- `image_path` (str): Path to the cardiovascular imaging data (DICOM, JPG, PNG)
- `output_dir` (str, optional): Directory to save output files (default: "./output")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_atp_luminescence_assay`
**Summary**: Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.

**Parameters**:
- `data_file` (str): Path to CSV file containing luminescence readings from samples. Expected format: columns for 'Sample_ID' and 'Luminescence_Value'.
- `standard_curve_file` (str): Path to CSV file containing standard curve data. Expected format: columns for 'ATP_Concentration' (in nM) and 'Luminescence_Value'.
- `normalization_method` (str, optional): Method used to normalize ATP values, either 'cell_count' or 'protein_content'. Default is 'cell_count'.
- `normalization_data` (str or dict, optional): Either path to CSV file with normalization data or dictionary with sample IDs as keys. For 'cell_count': values should be cell counts per sample. For 'protein_content': values should be protein concentration (μg/mL).

**Returns**: str
    Research log summarizing the ATP content measurement process and results.

*Documentation quality*: Complete

### `analyze_thrombus_histology`
**Summary**: Analyze histological images of thrombus samples stained with H&E to identify and quantify

**Parameters**:
- `image_path` (str): Path to the histological image of thrombus sample stained with H&E
- `output_dir` (str, optional): Directory to save output files (default: "./output")

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_intracellular_calcium_with_rhod2`
**Summary**: Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.

**Parameters**:
- `background_image_path` (str): Path to the background image (no cells, just media)
- `control_image_path` (str): Path to the control image (cells without calcium stimulus)
- `sample_image_path` (str): Path to the sample image (cells with calcium stimulus)
- `output_dir` (str, optional): Directory to save output files, default is "./output"

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `quantify_corneal_nerve_fibers`
**Summary**: Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.

**Parameters**:
- `image_path` (str): Path to the immunofluorescence microscopy image file
- `marker_type` (str): Type of nerve fiber marker (e.g., 'βIII-tubulin', 'SP', 'L1CAM')
- `output_dir` (str, optional): Directory to save output files (default: './output')
- `threshold_method` (str, optional): Method for thresholding ('otsu', 'adaptive', 'manual'), default is 'otsu'

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `segment_and_quantify_cells_in_multiplexed_images`
**Summary**: Segment cells and quantify protein expression levels from multichannel tissue images.

**Parameters**:
- `image_path` (str): Path to the multichannel image file (tiff stack or similar format)
- `markers_list` (list of str): List of marker names corresponding to each channel in the image
- `nuclear_channel_index` (int, optional): Index of the nuclear marker channel (default: 0, typically DAPI)
- `output_dir` (str, optional): Directory to save output files (default: "./output")

**Returns**: str
    Research log summarizing the steps performed and output file locations

*Documentation quality*: Complete

### `analyze_bone_microct_morphometry`
**Summary**: Analyze bone microarchitecture parameters from 3D micro-CT images.

**Parameters**:
- `input_file_path` (str): Path to the micro-CT scan data file (TIFF stack or similar 3D format)
- `output_dir` (str, optional): Directory to save output files, default is "./results"
- `threshold_value` (float, optional): Threshold value for bone segmentation. If None, Otsu's method will be used

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

## Pharmacology (30 functions)

### `run_diffdock_with_smiles`

**Parameters**:
- `pdb_path`
- `smiles_string`
- `local_output_dir`
- `gpu_device`
- `use_gpu`

*Documentation quality*: Missing

### `docking_autodock_vina`

**Parameters**:
- `smiles_list`
- `receptor_pdb_file`
- `box_center`
- `box_size`
- `ncpu`

*Documentation quality*: Missing

### `run_autosite`

**Parameters**:
- `pdb_file`
- `output_dir`
- `spacing`

*Documentation quality*: Missing

### `retrieve_topk_repurposing_drugs_from_disease_txgnn`
**Summary**: This function computes TxGNN model predictions for drug repurposing. It takes in the paths to the data,

**Parameters**:
- `disease_name` (str): The name of the disease for which the drug predictions are to be retrieved.)
- `data_lake_path` (str): The path to the data lake containing the TxGNN predictions.)
- `k` (int, optional): The number of top drug predictions to return. Defaults to 5.)

**Returns**: - str: A summary of the steps and the top K drug predictions with their scores.

*Documentation quality*: Complete

### `sigmoid`

**Parameters**:
- `x`

*Documentation quality*: Missing

### `predict_admet_properties`

**Parameters**:
- `smiles_list`
- `ADMET_model_type`

*Documentation quality*: Missing

### `ADMET_pred`

**Parameters**:
- `drug`
- `task`
- `unit`

*Documentation quality*: Missing

### `predict_binding_affinity_protein_1d_sequence`

**Parameters**:
- `smiles_list`
- `amino_acid_sequence`
- `affinity_model_type`

*Documentation quality*: Missing

### `analyze_accelerated_stability_of_pharmaceutical_formulations`
**Summary**: Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.

**Parameters**:
- `formulations` (list of dict): List of formulation dictionaries, each containing: - 'name': str, name of the formulation - 'active_ingredient': str, name of the active pharmaceutical ingredient - 'concentration': float, concentration in mg/mL - 'excipients': list, list of excipients
- `storage_conditions` (list of dict): List of storage condition dictionaries, each containing: - 'temperature': float, temperature in °C - 'humidity': float, relative humidity in percentage (optional for solid dosage forms) - 'description': str, description of storage condition (e.g., "Room Temperature", "Accelerated")
- `time_points` (list of int): List of time points in days to evaluate stability

**Returns**: str
    Research log summarizing the stability testing process and results

*Documentation quality*: Complete

### `run_3d_chondrogenic_aggregate_assay`
**Summary**: Generates a detailed protocol for performing a 3D chondrogenic aggregate culture assay to evaluate compounds' effects on chondrogenesis.

**Parameters**:
- `chondrocyte_cells` (dict): Dictionary with cell information including 'source', 'passage_number', and 'cell_density'
- `test_compounds` (list of dict): List of compounds to test, each with 'name', 'concentration', and 'vehicle' keys
- `culture_duration_days` (int): Total duration of the culture period in days (default: 21)
- `measurement_intervals` (int): Interval in days between measurements (default: 7)

**Returns**: str
    Detailed protocol document for the 3D chondrogenic aggregate culture assay

*Documentation quality*: Complete

### `grade_adverse_events_using_vcog_ctcae`
**Summary**: Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.

**Parameters**:
- `clinical_data_file` (str): Path to a CSV file containing clinical evaluation data with columns: subject_id, time_point, symptom, severity, measurement (optional)

**Returns**: str
    A research log summarizing the adverse event grading process and results.
    The graded events are saved to 'vcog_ctcae_graded_events.csv'.

*Documentation quality*: Complete

### `apply_vcog_grade`
**Summary**: Apply VCOG-CTCAE grading criteria to an adverse event.

**Parameters**:
- `symptom` (str): The type of adverse event
- `severity` (str): The severity description
- `measurement` (float or None): Quantitative measurement related to the symptom, if available

**Returns**: int
    The VCOG-CTCAE grade (0-5)
str
    Description of the grading rationale

*Documentation quality*: Complete

### `analyze_radiolabeled_antibody_biodistribution`
**Summary**: Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.

**Parameters**:
- `time_points` (list or numpy.ndarray): Time points (hours) at which measurements were taken
- `tissue_data` (dict): Dictionary where keys are tissue names and values are lists/arrays of %IA/g measurements corresponding to time_points. Must include 'tumor' as one of the keys.

**Returns**: str
    Research log summarizing the biodistribution analysis, pharmacokinetic parameters,
    and tumor-to-normal tissue ratios

*Documentation quality*: Complete

### `bi_exp_model`

**Parameters**:
- `t`
- `A`
- `alpha`
- `B`
- `beta`

*Documentation quality*: Missing

### `estimate_alpha_particle_radiotherapy_dosimetry`
**Summary**: Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.

**Parameters**:
- `biodistribution_data` (dict): Dictionary containing organ/tissue names as keys and a list of time-activity measurements as values. Each measurement should be a tuple of (time_hours, percent_injected_activity). Must include entries for all relevant organs including 'tumor'.
- `radiation_parameters` (dict): Dictionary containing radiation parameters for the alpha-emitting radionuclide: - 'radionuclide': str - Name of the radionuclide (e.g., 'Ac-225') - 'half_life_hours': float - Physical half-life in hours - 'energy_per_decay_MeV': float - Energy released per decay in MeV - 'radiation_weighting_factor': float - Radiation weighting factor for alpha particles - 'S_factors': dict - S-factors (Gy/Bq-s) for each source-target organ pair
- `output_file` (str, optional): Filename to save the dosimetry results (default: "dosimetry_results.csv")

**Returns**: str
    Research log summarizing the dosimetry estimation process and results

*Documentation quality*: Complete

### `perform_mwas_cyp2c19_metabolizer_status`
**Summary**: Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.

**Parameters**:
- `methylation_data_path` (str): Path to CSV or TSV file containing DNA methylation beta values. Rows should be samples, columns should be CpG sites.
- `metabolizer_status_path` (str): Path to CSV or TSV file containing CYP2C19 metabolizer status for each sample. Should have a sample ID column and a status column (e.g., poor, intermediate, normal, rapid, ultrarapid).
- `covariates_path` (str, optional): Path to CSV or TSV file containing covariates to adjust for in the regression model (e.g., age, sex, smoking status).
- `pvalue_threshold` (float, optional): P-value threshold for significance after multiple testing correction. Default is 0.05.
- `output_file` (str, optional): Filename to save significant CpG sites. Default is "significant_cpg_sites.csv".

**Returns**: str
    A research log summarizing the MWAS analysis and results.

*Documentation quality*: Complete

### `calculate_physicochemical_properties`
**Summary**: Calculate key physicochemical properties of a drug candidate molecule.

**Parameters**:
- `smiles_string` (str): The molecular structure in SMILES format

**Returns**: str
    A research log summarizing the calculated physicochemical properties and
    indicating where the detailed results are saved

*Documentation quality*: Complete

### `analyze_xenograft_tumor_growth_inhibition`
**Summary**: Analyze tumor growth inhibition in xenograft models across different treatment groups.

**Parameters**:
- `data_path` (str): Path to CSV or TSV file containing tumor volume measurements. The file should have columns for time, volume, treatment group, and subject ID
- `time_column` (str): Name of the column containing time points (e.g., 'Day', 'Time')
- `volume_column` (str): Name of the column containing tumor volume measurements
- `group_column` (str): Name of the column containing treatment group labels
- `subject_column` (str): Name of the column containing subject/mouse identifiers
- `output_dir` (str, optional): Directory to save output files (default: "./results")

**Returns**: str
    Research log summarizing the analysis steps, findings, and generated file paths

*Documentation quality*: Complete

### `analyze_western_blot`
**Summary**: Performs densitometric analysis of Western blot images to quantify relative protein expression.

**Parameters**:
- `blot_image_path` (str): Path to the Western blot image file
- `target_bands` (list of dict): List of dictionaries containing information about target protein bands Each dict should have 'name', 'roi' (region of interest as [x, y, width, height])
- `loading_control_band` (dict): Dictionary with 'name' and 'roi' for the loading control protein (e.g., β-actin, GAPDH)
- `antibody_info` (dict): Dictionary containing information about antibodies used Should have 'primary' and 'secondary' keys with antibody details
- `output_dir` (str, optional): Directory to save output files, defaults to './results'

**Returns**: str
    Research log summarizing the Western blot analysis process and results

*Documentation quality*: Complete

### `query_drug_interactions`
**Summary**: Query drug-drug interactions from DDInter database.

**Parameters**:
- `drug_names` (list of str): List of drug names to query for interactions
- `interaction_types` (list of str, optional): Filter by interaction types (e.g., ['synergistic', 'antagonistic'])
- `severity_levels` (list of str, optional): Filter by severity levels (e.g., ['Major', 'Moderate', 'Minor'])
- `data_lake_path` (str, optional): Path to data lake directory containing DDInter data

**Returns**: str
    Research log with detailed interaction analysis

*Documentation quality*: Complete

### `check_drug_combination_safety`
**Summary**: Analyze safety of a drug combination for potential interactions.

**Parameters**:
- `drug_list` (list of str): List of drugs to analyze for combination safety
- `include_mechanisms` (bool, default True): Include interaction mechanism descriptions
- `include_management` (bool, default True): Include management recommendations
- `data_lake_path` (str, optional): Path to data lake directory containing DDInter data

**Returns**: str
    Research log with safety analysis and recommendations

*Documentation quality*: Complete

### `analyze_interaction_mechanisms`
**Summary**: Analyze interaction mechanisms between two specific drugs.

**Parameters**:
- `drug_pair` (tuple of str): Pair of drug names to analyze (drug1, drug2)
- `detailed_analysis` (bool, default True): Include detailed mechanistic information
- `data_lake_path` (str, optional): Path to data lake directory containing DDInter data

**Returns**: str
    Research log with mechanism analysis

*Documentation quality*: Complete

### `find_alternative_drugs_ddinter`
**Summary**: Find alternative drugs that don't interact with contraindicated drugs.

**Parameters**:
- `target_drug` (str): Drug to find alternatives for
- `contraindicated_drugs` (list of str): List of drugs to avoid interactions with
- `therapeutic_class` (str, optional): Limit search to specific therapeutic class
- `data_lake_path` (str, optional): Path to data lake directory containing DDInter data

**Returns**: str
    Research log with alternative drug recommendations

*Documentation quality*: Complete

### `query_adverse_events`
**Summary**: Query adverse events with robust error handling and validation.

**Parameters**:
- `self`
- `drug_name` (str)
- `limit` (int)

*Documentation quality*: Complete

### `query_drug_labels`
**Summary**: Query FDA drug label information.

**Parameters**:
- `self`
- `drug_name` (str)
- `sections` (list[str] | None)

*Documentation quality*: Complete

### `query_drug_recalls`
**Summary**: Query FDA drug recall and enforcement information.

**Parameters**:
- `self`
- `drug_name` (str)
- `classification` (list[str] | None)

*Documentation quality*: Complete

### `query_fda_adverse_events`
**Summary**: Query FDA adverse event reports for specific drugs.

**Parameters**:
- `drug_name` (str)
- `date_range` (tuple[str, str] | None)
- `severity_filter` (list[str] | None)
- `outcome_filter` (list[str] | None)
- `limit` (int)

**Returns**: Formatted string with adverse event analysis

*Documentation quality*: Complete

### `get_fda_drug_label_info`
**Summary**: Retrieve FDA drug label information.

**Parameters**:
- `drug_name` (str)
- `sections` (list[str] | None)

**Returns**: Formatted string with drug label information

*Documentation quality*: Complete

### `check_fda_drug_recalls`
**Summary**: Check for FDA drug recalls and enforcement actions.

**Parameters**:
- `drug_name` (str)
- `classification` (list[str] | None)
- `date_range` (tuple[str, str] | None)

**Returns**: Formatted string with recall information

*Documentation quality*: Complete

### `analyze_fda_safety_signals`
**Summary**: Analyze safety signals across multiple drugs.

**Parameters**:
- `drug_list` (list[str])
- `comparison_period` (tuple[str, str] | None)
- `signal_threshold` (float)

**Returns**: Formatted string with safety signal analysis

*Documentation quality*: Complete

## Physiology (14 functions)

### `reconstruct_3d_face_from_mri`
**Summary**: Generate a 3D model of facial anatomy from MRI scans of the head and neck.

**Parameters**:
- `mri_file_path` (str): Path to the MRI scan file (NIfTI format: .nii or .nii.gz)
- `output_dir` (str): Directory where output files will be saved
- `subject_id` (str): Identifier for the subject, used in output filenames
- `threshold_value` (int): Threshold value for initial segmentation of facial tissues

**Returns**: str
    Research log detailing the reconstruction process and output file locations

*Documentation quality*: Complete

### `analyze_abr_waveform_p1_metrics`
**Summary**: Extracts P1 amplitude and latency from Auditory Brainstem Response (ABR) waveform data.

**Parameters**:
- `time_ms` (array-like): Time points of the ABR recording in milliseconds
- `amplitude_uv` (array-like): Amplitude values of the ABR recording in microvolts

**Returns**: str
    Research log summarizing the analysis steps and results, including P1 amplitude and latency

*Documentation quality*: Complete

### `analyze_ciliary_beat_frequency`
**Summary**: Analyze ciliary beat frequency from high-speed video microscopy data using FFT analysis.

**Parameters**:
- `video_path` (str): Path to the high-speed video microscopy file of ciliary beating
- `roi_count` (int, optional): Number of regions of interest to analyze (default: 5)
- `min_freq` (float, optional): Minimum frequency to consider in Hz (default: 0)
- `max_freq` (float, optional): Maximum frequency to consider in Hz (default: 30)
- `output_dir` (str, optional): Directory to save output files (default: current directory)

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `analyze_protein_colocalization`
**Summary**: Analyze colocalization between two fluorescently labeled proteins in microscopy images.

**Parameters**:
- `channel1_path` (str): Path to the first channel image file (fluorescent protein 1)
- `channel2_path` (str): Path to the second channel image file (fluorescent protein 2)
- `output_dir` (str): Directory to save output files (default: "./output")
- `threshold_method` (str): Method for thresholding images ('otsu', 'li', or 'yen') (default: "otsu")

**Returns**: str
    Research log summarizing the colocalization analysis results and saved files

*Documentation quality*: Complete

### `perform_cosinor_analysis`
**Summary**: Performs cosinor analysis on physiological time series data to characterize circadian rhythms.

**Parameters**:
- `time_data` (array-like): Time points of the measurements in hours
- `physiological_data` (array-like): Physiological measurements corresponding to each time point
- `period` (float, default=24.0): Period of the rhythm in hours, default is 24 hours for circadian rhythms

**Returns**: str
    A research log summarizing the cosinor analysis process and results

*Documentation quality*: Complete

### `cosinor_model`
**Summary**: Cosine function with baseline (mesor), amplitude, and phase shift.

**Parameters**:
- `t`
- `mesor`
- `amplitude`
- `acrophase`

*Documentation quality*: Complete

### `calculate_brain_adc_map`
**Summary**: Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.

**Parameters**:
- `dwi_file_path` (str): Path to the 4D NIfTI file containing diffusion-weighted MRI data, where the 4th dimension corresponds to different b-values.
- `b_values` (list or numpy.ndarray): List of b-values corresponding to each volume in the 4D DWI data.
- `output_path` (str, optional): Path where the output ADC map will be saved (default: "adc_map.nii.gz").
- `mask_file_path` (str, optional): Path to a binary mask file to limit ADC calculation to brain regions (default: None).

**Returns**: str
    Research log summarizing the ADC mapping process and results.

*Documentation quality*: Complete

### `mono_exp_model`

**Parameters**:
- `b`
- `S0`
- `ADC`

*Documentation quality*: Missing

### `analyze_endolysosomal_calcium_dynamics`
**Summary**: Analyze calcium dynamics in endo-lysosomal compartments using ELGA/ELGA1 probe data.

**Parameters**:
- `time_points` (numpy.ndarray or list): Time points of the measurements in seconds
- `luminescence_values` (numpy.ndarray or list): Luminescence intensity values from ELGA/ELGA1 probes corresponding to Ca2+ levels
- `treatment_time` (float, optional): Time point (in seconds) when treatment/stimulus was applied
- `cell_type` (str, optional): Type of cells used in the experiment
- `treatment_name` (str, optional): Name of the treatment or stimulus applied
- `output_file` (str, optional): Name of the file to save detailed analysis results

**Returns**: str
    A research log summarizing the calcium dynamics analysis and key findings

*Documentation quality*: Complete

### `analyze_fatty_acid_composition_by_gc`
**Summary**: Analyzes fatty acid composition in tissue samples using gas chromatography data.

**Parameters**:
- `gc_data_file` (str): Path to the CSV file containing gas chromatography data with columns 'retention_time' and 'peak_area'.
- `tissue_type` (str): Type of tissue sample (e.g., liver, kidney, heart, muscle, adipose).
- `sample_id` (str): Identifier for the sample being analyzed.
- `output_directory` (str, optional): Directory where result files will be saved (default: "./results").

**Returns**: str
    Research log summarizing the analysis steps and results.

*Documentation quality*: Complete

### `analyze_hemodynamic_data`
**Summary**: Analyzes raw blood pressure data to calculate key hemodynamic parameters.

**Parameters**:
- `pressure_data` (numpy.ndarray): Raw blood pressure measurements in mmHg
- `sampling_rate` (float): Data acquisition rate in Hz (samples per second)
- `output_file` (str, optional): Filename to save the calculated parameters, default is "hemodynamic_results.csv"

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `simulate_thyroid_hormone_pharmacokinetics`
**Summary**: Simulates the transport and binding of thyroid hormones across different tissue compartments

**Parameters**:
- `parameters` (dict): Dictionary containing model parameters: - transport_rates : dict of rate constants for hormone transport between compartments - binding_constants : dict of association/dissociation constants for hormone-protein binding - metabolism_rates : dict of rate constants for hormone metabolism in different tissues - volumes : dict of compartment volumes
- `initial_conditions` (dict): Dictionary of initial concentrations for all molecular species in each compartment
- `time_span` (tuple, optional): Start and end time for simulation in hours (default: (0, 24))
- `time_points` (int, optional): Number of time points to output (default: 100)

**Returns**: str
    Research log summarizing the simulation and results

*Documentation quality*: Complete

### `pk_ode_system`

**Parameters**:
- `t`
- `y`

*Documentation quality*: Missing

### `quantify_amyloid_beta_plaques`

**Parameters**:
- `image_path`
- `output_dir`
- `threshold_method`
- `min_plaque_size`
- `manual_threshold`

*Documentation quality*: Missing

## Protocols (2 functions)

### `search_protocols`
**Summary**: Search protocols.io for relevant protocols based on a natural language query.

**Parameters**:
- `query` (str)

**Returns**: Dictionary containing:
        - protocols: List of protocol dictionaries with title, description, url, etc.
        - pagination: Pagination information
        - total_results: Total number of matching protocols
        - status_code: API status code (0 = success)

*Documentation quality*: Complete

### `get_protocol_details`
**Summary**: Get detailed information about a specific protocol by ID.

**Parameters**:
- `protocol_id` (int)
- `timeout` (int)

**Returns**: Dictionary containing detailed protocol information

*Documentation quality*: Complete

## Synthetic_Biology (11 functions)

### `engineer_bacterial_genome_for_therapeutic_delivery`
**Summary**: Engineer a bacterial genome by integrating therapeutic genetic parts for therapeutic delivery.

**Parameters**:
- `bacterial_genome_file` (str): Path to the file containing the bacterial genome sequence in FASTA format
- `genetic_parts` (dict): Dictionary containing genetic parts to be integrated:: { 'promoters': list of dict with 'name', 'sequence', and 'position', 'genes': list of dict with 'name', 'sequence', and 'position', 'terminators': list of dict with 'name', 'sequence', and 'position', 'cargo': dict with 'name' and 'sequence' of the therapeutic cargo }

**Returns**: str
    Research log summarizing the engineering process, including the filename of the
    engineered genome and plasmid map

*Documentation quality*: Complete

### `analyze_bacterial_growth_rate`
**Summary**: Analyze bacterial growth data and extract growth parameters from OD600 measurements.

**Parameters**:
- `time_points` (list or numpy.ndarray): Time points at which OD600 measurements were taken (in hours)
- `od_measurements` (list or numpy.ndarray): Optical density (OD600) measurements corresponding to each time point
- `strain_name` (str, optional): Name of the bacterial strain being analyzed, default is "Unknown strain"
- `output_dir` (str, optional): Directory where to save the output files, default is current directory

**Returns**: str
    A research log summarizing the analysis steps, fitted parameters, and results

*Documentation quality*: Complete

### `gompertz_model`
**Summary**: Gompertz growth model.

**Parameters**:
- `t` (time points)
- `lag` (lag time (hours)
- `mu_max` (maximum growth rate (per hour)
- `A` (carrying capacity (maximum OD)

*Documentation quality*: Complete

### `analyze_barcode_sequencing_data`
**Summary**: Analyze sequencing data to extract, quantify and determine lineage relationships of barcodes.

**Parameters**:
- `input_file` (str): Path to the input sequencing file in FASTQ or FASTA format
- `barcode_pattern` (str, optional): Regular expression pattern to identify barcodes. If None, will use flanking sequences
- `flanking_seq_5prime` (str, optional): 5' flanking sequence of the barcode region
- `flanking_seq_3prime` (str, optional): 3' flanking sequence of the barcode region
- `min_count` (int, default=5): Minimum count threshold for considering a barcode
- `output_dir` (str, default="./results"): Directory to save output files

**Returns**: str
    Research log summarizing the analysis steps and results

*Documentation quality*: Complete

### `hamming_distance`

**Parameters**:
- `s1`
- `s2`

*Documentation quality*: Missing

### `analyze_bifurcation_diagram`
**Summary**: Performs bifurcation analysis on a dynamical system and generates a bifurcation diagram.

**Parameters**:
- `time_series_data` (numpy.ndarray): A 2D array where each row represents a time series for a specific parameter value. Shape should be (n_parameter_values, n_time_points).
- `parameter_values` (numpy.ndarray): 1D array of parameter values corresponding to each time series. Shape should be (n_parameter_values,).
- `system_name` (str, optional): Name of the dynamical system being analyzed, used for plot titles.
- `output_dir` (str, optional): Directory to save the output files.

**Returns**: str
    Research log summarizing the bifurcation analysis process and results.

*Documentation quality*: Complete

### `create_biochemical_network_sbml_model`
**Summary**: Generate a mathematical model of a biochemical network in SBML format.

**Parameters**:
- `reaction_network` (list of dict): List of dictionaries, each representing a reaction with keys: - 'id': Reaction identifier - 'name': Reaction name - 'reactants': Dict of reactant species IDs and their stoichiometry - 'products': Dict of product species IDs and their stoichiometry - 'reversible': Boolean indicating if reaction is reversible
- `kinetic_parameters` (dict): Dictionary mapping reaction IDs to their kinetic law parameters. Each entry should contain: - 'law_type': Type of kinetic law (e.g., 'mass_action', 'michaelis_menten') - 'parameters': Dict of parameter names and values
- `output_file` (str, optional): File path to save the SBML model (default: "biochemical_model.xml")

**Returns**: str
    Research log summarizing the model creation process

*Documentation quality*: Complete

### `optimize_codons_for_heterologous_expression`
**Summary**: Analyzes and optimizes a DNA/RNA sequence for improved expression in a heterologous host organism.

**Parameters**:
- `target_sequence` (str): The DNA or RNA sequence of the target gene to be optimized. Should contain complete codons (length divisible by 3).
- `host_codon_usage` (dict): Dictionary mapping codons to their usage frequency in the host organism. Format: {'AUG': 0.8, 'GCC': 0.6, ...} or {'ATG': 0.8, 'GCC': 0.6, ...}

**Returns**: str
    A research log summarizing the optimization process and results.

*Documentation quality*: Complete

### `simulate_gene_circuit_with_growth_feedback`
**Summary**: Simulate gene regulatory circuit dynamics with growth feedback.

**Parameters**:
- `circuit_topology` (numpy.ndarray): Adjacency matrix representing the gene circuit topology. Positive values indicate activation, negative values indicate repression. Shape should be (n_genes, n_genes) where n_genes is the number of genes in the circuit.
- `kinetic_params` (dict): Dictionary containing kinetic parameters: - 'basal_rates': list of basal expression rates for each gene - 'degradation_rates': list of degradation rates for each gene - 'hill_coefficients': list of Hill coefficients for regulatory interactions - 'threshold_constants': list of threshold constants for regulatory interactions
- `growth_params` (dict): Dictionary containing growth-related parameters: - 'max_growth_rate': maximum cell growth rate - 'growth_inhibition': how gene expression affects growth - 'gene_growth_weights': weights for how each gene affects growth
- `simulation_time` (float, optional): Total simulation time (default: 100)
- `time_points` (int, optional): Number of time points to sample (default: 1000)

**Returns**: str
    Research log summarizing the simulation and results with file names of saved data

*Documentation quality*: Complete

### `gene_circuit_odes`

**Parameters**:
- `t`
- `state`

*Documentation quality*: Missing

### `identify_fas_functional_domains`
**Summary**: Identifies functional domains within a Fatty Acid Synthase (FAS) sequence and predicts their roles.

**Parameters**:
- `sequence` (str): The nucleotide or protein sequence of a FAS gene
- `sequence_type` (str): Type of sequence provided - "protein" or "nucleotide" (default: "protein")
- `output_file` (str): Name of the output file to save the detailed domain report (default: "fas_domains_report.txt")

**Returns**: str
    A research log summarizing the steps taken and results of the domain analysis

*Documentation quality*: Complete

## Systems_Biology (13 functions)

### `query_chatnt`
**Summary**: Call ChatNT to answer a question about a DNA sequence.

**Parameters**:
- `question` (str): Question to ask about the DNA sequence
- `sequence` (str): DNA sequence to analyze
- `device` (int, optional): Device to use for the ChatNT model. Default is -1 (CPU).

**Returns**: str
    Answer to the question

*Documentation quality*: Complete

### `perform_flux_balance_analysis`
**Summary**: Perform Flux Balance Analysis (FBA) on a genome-scale metabolic network model.

**Parameters**:
- `model_file` (str): Path to the metabolic model file (SBML or JSON format)
- `constraints` (dict, optional): Dictionary of reaction constraints where keys are reaction IDs and values are tuples of (lower_bound, upper_bound)
- `objective_reaction` (str, optional): Reaction ID to use as the objective function (e.g., biomass reaction) If None, uses the model's default objective
- `output_file` (str, optional): File name to save the flux distribution results

**Returns**: str
    Research log summarizing the FBA process and results

*Documentation quality*: Complete

### `model_protein_dimerization_network`
**Summary**: Model protein dimerization networks to find equilibrium concentrations of dimers.

**Parameters**:
- `monomer_concentrations` (dict): Dictionary mapping monomer names to their initial concentrations (in arbitrary units)
- `dimerization_affinities` (dict): Dictionary mapping dimer names (as 'A-B' strings) to their association constants (Ka)
- `network_topology` (list of tuples): List of (monomer1, monomer2) pairs that can form dimers

**Returns**: str
    Research log summarizing the modeling process and results

*Documentation quality*: Complete

### `dimerization_odes`

**Parameters**:
- `t`
- `y`

*Documentation quality*: Missing

### `simulate_metabolic_network_perturbation`
**Summary**: Construct and simulate kinetic models of metabolic networks and analyze their responses to perturbations.

**Parameters**:
- `model_file` (str): Path to the COBRA model file (SBML format)
- `initial_concentrations` (dict): Dictionary mapping metabolite IDs to their initial concentrations
- `perturbation_params` (dict): Dictionary with the following keys: - 'time': float, time at which perturbation is applied - 'metabolite': str, ID of the metabolite to perturb - 'factor': float, multiplication factor for the metabolite concentration
- `simulation_time` (float, optional): Total simulation time (default: 100)
- `time_points` (int, optional): Number of time points to simulate (default: 1000)

**Returns**: str
    Research log summarizing the steps taken and results obtained

*Documentation quality*: Complete

### `mass_action_kinetics`

**Parameters**:
- `reaction`
- `concentrations`
- `metabolite_ids`

*Documentation quality*: Missing

### `ode_system`

**Parameters**:
- `t`
- `concentrations`
- `metabolite_ids`
- `reactions`
- `perturbation`

*Documentation quality*: Missing

### `simulate_protein_signaling_network`
**Summary**: Simulate protein signaling network dynamics using ODE-based logic modeling with normalized Hill functions.

**Parameters**:
- `network_structure` (dict): Dictionary defining the network topology. Each key is a target protein and its value is a list of tuples (regulator, regulation_type) where regulation_type is 1 for activation and -1 for inhibition.
- `reaction_params` (dict): Dictionary of reaction parameters. Keys are tuples (regulator, target) and values are dictionaries with keys 'W' (weight), 'n' (Hill coefficient), and 'EC50' (half-maximal effective concentration).
- `species_params` (dict): Dictionary of species parameters. Keys are protein names and values are dictionaries with keys 'tau' (time constant), 'y0' (initial concentration), and 'ymax' (maximum concentration).
- `simulation_time` (float, optional): Total simulation time in arbitrary time units. Default is 100.
- `time_points` (int, optional): Number of time points for the simulation. Default is 1000.

**Returns**: str
    Research log summarizing the simulation process and results.

*Documentation quality*: Complete

### `hill_function`

**Parameters**:
- `x`
- `n`
- `ec50`

*Documentation quality*: Missing

### `ode_system`

**Parameters**:
- `t`
- `y`

*Documentation quality*: Missing

### `compare_protein_structures`
**Summary**: Compares two protein structures to identify structural differences and conformational changes.

**Parameters**:
- `pdb_file1` (str): Path to the first PDB file
- `pdb_file2` (str): Path to the second PDB file
- `chain_id1` (str, optional): Chain ID to analyze in the first structure (default: 'A')
- `chain_id2` (str, optional): Chain ID to analyze in the second structure (default: 'A')
- `output_prefix` (str, optional): Prefix for output files (default: "protein_comparison")

**Returns**: str
    A research log summarizing the structural comparison analysis

*Documentation quality*: Complete

### `simulate_renin_angiotensin_system_dynamics`
**Summary**: Simulate the time-dependent concentrations of renin-angiotensin system (RAS) components.

**Parameters**:
- `initial_concentrations`
- `rate_constants`
- `feedback_params`
- `simulation_time` (float, optional): Total simulation time in hours (default: 48)
- `time_points` (int, optional): Number of time points to evaluate (default: 100)

**Returns**: str
    Research log summarizing the simulation steps and results

*Documentation quality*: Complete

### `ras_ode_system`

**Parameters**:
- `t`
- `y`

*Documentation quality*: Missing
