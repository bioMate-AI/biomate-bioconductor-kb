# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-26

### Added

- `LESSONS_LEARNED.md` - Comprehensive documentation of patterns, best practices, and common pitfalls
- `test_data/create_mock_nifti.py` - Script for generating mock NIfTI test files
- Mock NIfTI test data files for bioimaging workflows

### Fixed

#### Bioimaging Workflows (10 modules)
- `bioimaging/batch_register_images` - Fixed parameter mapping for `moving_images_dir`
- `bioimaging/calculate_similarity_metrics` - Added full ImageRegistrationTool implementation
- `bioimaging/create_segmentation_visualization` - Added full SegmentationTool implementation
- `bioimaging/prepare_input_for_nnunet` - Added full SegmentationTool implementation
- `bioimaging/preprocess_image` - Added full ImageRegistrationTool implementation
- `bioimaging/quick_affine_registration` - Added full ImageRegistrationTool implementation
- `bioimaging/quick_deformable_registration` - Added full ImageRegistrationTool implementation
- `bioimaging/quick_rigid_registration` - Added full ImageRegistrationTool implementation
- `bioimaging/segment_with_nn_unet` - Added full SegmentationTool implementation
- `bioimaging/split_modalities` - Added full SegmentationTool implementation

#### Python 3.10+ Compatibility (4 modules)
- `cell_biology/analyze_flow_cytometry_immunophenotyping` - Added collections.abc compatibility shim
- `cancer_biology/analyze_cell_senescence_and_apoptosis` - Added collections.abc compatibility shim
- `immunology/analyze_cfse_cell_proliferation` - Added collections.abc compatibility shim
- `immunology/analyze_cytokine_production_in_cd4_tcells` - Added collections.abc compatibility shim

#### Parameter Validation (5 modules)
- `biochemistry/michaelis_menten` - Added None handling with sensible defaults
- `database/get_hpo_names` - Implemented parse_hpo_obo function
- `microbiology/simulate_microbial_population_dynamics` - Added parameter type validation
- `physiology/cosinor_model` - Added None handling with sensible defaults
- `synthetic_biology/optimize_codons_for_heterologous_expression` - Added default E. coli codon usage table

### Changed

- `nextflow.config` - Added Docker volume mounts for `/tmp` and `test_data` directories
- All bioimaging modules now use single-quoted Python docstrings (`'''`) to avoid Nextflow script block conflicts

### Technical Notes

- **Nextflow/Python Docstring Conflict**: Triple-quoted Python docstrings (`"""`) inside Nextflow script blocks cause premature script termination. Solution: Use single-quoted docstrings (`'''`).
- **Python 3.10+ Collections**: Libraries using `collections.MutableMapping` fail on Python 3.10+. Solution: Add compatibility shim before imports.
- **None Parameter Handling**: Functions must validate and provide defaults for all numeric parameters.

## [1.0.0] - 2026-01-25

### Added

- Initial release of 237 Nextflow nf-core style modules
- Support for 19 bioinformatics domains
- Docker container support via `biomate/biomni-tools:latest`
- Self-contained Python implementations (no external biomni dependency)
