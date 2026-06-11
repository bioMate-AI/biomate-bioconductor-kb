#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqCAT — cosmic_profile_comparison
// Compare HTS sample variants against the COSMIC database to validate cell line identity.
// Input: sample.vcf.gz, CosmicCLP_MutantExport.tsv.gz
// Container: quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0
// R packages: VariantAnnotation, seqCAT
// Bioconductor: 3.20 | R: 4.4
// Requires: VariantAnnotation, seqCAT
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create SNV profile from VCF
//  * 2. [Input & Preparation] List and read the COSMIC profile for the target cell line
//  * 3. [Core Analysis] Compare the HTS profile to the COSMIC profile

nextflow.enable.dsl = 2

process BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("VariantAnnotation", "seqCAT")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    
    # Load required libraries
    library("seqCAT")
    library("VariantAnnotation")
    
    # Define input file paths (must exist in the working directory)
    vcf_file <- "sample.vcf.gz"
    cosmic_file <- "CosmicCLP_MutantExport.tsv.gz"
    
    # Verify input files exist
    if (!file.exists(vcf_file)) {
      stop(paste("Required input file missing:", vcf_file))
    }
    if (!file.exists(cosmic_file)) {
      stop(paste("Required input file missing:", cosmic_file))
    }
    
    # Dynamically extract sample names from the user's VCF file
    vcf_samples <- VariantAnnotation::samples(VariantAnnotation::scanVcfHeader(vcf_file))
    if (length(vcf_samples) == 0) {
      stop("No samples found in the provided VCF file.")
    }
    
    # 1. Create SNV profiles from VCF dynamically for available samples
    profiles <- list()
    for (s in vcf_samples) {
      message("Creating SNV profile for: ", s)
      profiles[[s]] <- create_profile(vcf_file, s)
    }
    
    # 2. List and read the COSMIC profile for the target cell line
    message("Listing cell lines in COSMIC export...")
    cell_lines <- list_cosmic(cosmic_file)
    
    # Check if the target cell line exists in the COSMIC file
    target_sample <- vcf_samples[1]
    has_target <- any(grepl(target_sample, cell_lines, ignore.case = TRUE))
    message("Is ", target_sample, " present in COSMIC file? ", has_target)
    
    # Determine which COSMIC profile to read
    cosmic_target <- if (has_target) target_sample else cell_lines[1]
    message("Reading COSMIC profile for: ", cosmic_target)
    cosmic <- read_cosmic(cosmic_file, cosmic_target)
    
    # 3. Compare the HTS profile to the COSMIC profile
    message("Comparing HTS profile to COSMIC profile...")
    target_profile <- profiles[[target_sample]]
    target_cosmic <- compare_profiles(target_profile, cosmic)
    
    # 4. Perform many-to-one comparisons against the COSMIC baseline
    message("Performing many-to-one comparisons against COSMIC...")
    many_cosmic <- compare_many(profiles, one = cosmic)
    
    # --- Save Outputs ---
    message("Writing output files...")
    
    # Save individual profiles
    for (s in vcf_samples) {
      write_profile(profiles[[s]], paste0(s, "_profile.txt"))
      saveRDS(profiles[[s]], paste0(s, "_profile.rds"))
    }
    
    # Save binary comparison results
    write.csv(target_cosmic, paste0(target_sample, "_cosmic_comparison.csv"), row.names = FALSE)
    saveRDS(target_cosmic, paste0(target_sample, "_cosmic_comparison.rds"))
    
    # Save many-to-one comparison results
    saveRDS(many_cosmic, "many_cosmic_comparison.rds")
    if (length(many_cosmic) >= 1) {
      write.csv(many_cosmic[[1]], "many_cosmic_similarities.csv", row.names = FALSE)
    }
    
    message("Pipeline completed successfully.")

    writeLines(c(
        '"BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON":',
        paste0('    seqCAT: ', as.character(packageVersion('seqCAT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosmic_profile_comparison.csv versions.yml
    """
}

workflow BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sample.vcf.gz, CosmicCLP_MutantExport.tsv.gz ] ]

    main:
    BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON.out.tables
    plots    = BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON.out.plots
    objects  = BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON.out.objects
    versions = BIOC_SEQCAT_COSMIC_PROFILE_COMPARISON.out.versions
}
