#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqcat — snv_profile_comparison_and_similarity_analysis
// Create SNV profiles from VCF files, compare them to evaluate genetic similarity, and visualize the results.
// Input: example.vcf.gz
// Container: quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0
// R packages: ggplot2, seqCAT
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("ggplot2", "seqCAT")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
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
    library("ggplot2")
    
    # Define the input file from the working directory
    vcf <- "example.vcf.gz"
    
    # Verify input file existence
    if (!file.exists(vcf)) {
      stop(paste("Error: Required input file '", vcf, "' not found in the working directory.", sep = ""))
    }
    
    # --- Create individual SNV profiles ---
    message("Creating SNV profiles...")
    hct116 <- create_profile(vcf, "HCT116")
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    
    # --- Filter variants by depth or duplicates ---
    message("Filtering variants...")
    rko_filtered <- filter_variants(rko, min_depth = 20)
    rko_deduplicated <- filter_duplicates(rko, filter_pd = TRUE)
    
    # --- Compare profiles ---
    message("Comparing profiles...")
    hct116_rko <- compare_profiles(hct116, rko)
    hct116_rko_union <- compare_profiles(hct116, rko, mode = "union")
    
    # --- Calculate similarity statistics ---
    message("Calculating similarity statistics...")
    similarity <- calculate_similarity(hct116_rko)
    
    hke3 <- create_profile(vcf, "HKE3")
    hct116_hke3 <- compare_profiles(hct116, hke3)
    similarities <- calculate_similarity(hct116_hke3, similarity, b = 10)
    
    # --- Plot variant impact distributions ---
    message("Plotting variant impacts...")
    impacts <- plot_impacts(hct116_rko)
    
    # --- Perform many-to-many comparisons ---
    message("Performing many-to-many comparisons...")
    profiles <- list(hct116, hke3, rko)
    many <- compare_many(profiles)
    
    # --- Visualize multiple comparisons ---
    message("Plotting heatmap...")
    heatmap <- plot_heatmap(many[[1]])
    
    # Save outputs to the working directory
    message("Saving results to disk...")
    
    # Save profiles and comparisons as CSV tables
    write.csv(as.data.frame(hct116), "hct116_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(rko), "rko_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(rko_filtered), "rko_filtered_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(rko_deduplicated), "rko_deduplicated_profile.csv", row.names = FALSE)
    write.csv(as.data.frame(hct116_rko), "hct116_rko_comparison.csv", row.names = FALSE)
    write.csv(as.data.frame(hct116_rko_union), "hct116_rko_union_comparison.csv", row.names = FALSE)
    write.csv(as.data.frame(similarity), "similarity_hct116_rko.csv", row.names = FALSE)
    write.csv(as.data.frame(similarities), "similarities_all.csv", row.names = FALSE)
    
    # Save the full many-to-many comparison list object
    saveRDS(many, "many_comparisons.rds")
    
    # Save plots as PDFs
    ggplot2::ggsave("impacts_distribution.pdf", plot = impacts, width = 7, height = 5)
    ggplot2::ggsave("similarity_heatmap.pdf", plot = heatmap, width = 6, height = 5)
    
    message("Pipeline completed successfully!")

    writeLines(c(
        '"BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS":',
        paste0('        seqcat: ', as.character(packageVersion("seqcat")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snv_profile_comparison_and_similarity_analysis.csv versions.yml
    """
}

workflow BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ example.vcf.gz ] ]

    main:
    BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS.out.tables
    plots    = BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS.out.plots
    objects  = BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS.out.objects
    versions = BIOC_SEQCAT_SNV_PROFILE_COMPARISON_AND_SIMILARITY_ANALYSIS.out.versions
}
