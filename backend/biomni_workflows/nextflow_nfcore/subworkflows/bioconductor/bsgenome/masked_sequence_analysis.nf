#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: BSgenome — masked_sequence_analysis
// Analyze chromosome sequences while ignoring assembly gaps, repeat regions, or ambiguities using built-in masks.
// Input: BSgenome.Hsapiens.UCSC.hg38.masked
// Container: quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0
// R packages: BSgenome, BSgenome.Hsapiens.UCSC.hg38.masked, Biostrings
// Bioconductor: 3.20 | R: 4.4
// Requires: BSgenome, BSgenome.Hsapiens.UCSC.hg38.masked, Biostrings
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the masked genome package and extract a chromosome
//  * 2. [Core Analysis] Inspect and activate/deactivate specific masks (e.g., "AGAPS", "AMB", "RM", "TRF") using active()
//  * 3. [Core Analysis] Compute masked-aware statistics like alphabetFrequency()
//  * 4. [Core Analysis] Coerce the masked sequence to XStringViews to extract non-masked regions or use gaps() to extract masked regions
//  * 5. [Core Analysis] Perform pattern matching (e.g., countPattern) on the masked sequence to avoid false matches in assembly gaps or repeat regions

nextflow.enable.dsl = 2

process BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20-slim"

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
    .bm_deps <- c("BSgenome", "BSgenome.Hsapiens.UCSC.hg38.masked", "Biostrings")
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
    library(BSgenome)
    library(BSgenome.Hsapiens.UCSC.hg38.masked)
    library(Biostrings)
    
    # 1. Load the masked genome package and extract chromosome Y
    genome <- BSgenome.Hsapiens.UCSC.hg38.masked
    chrY <- genome\$chrY
    print(chrY)
    
    # 2. Inspect and activate/deactivate specific masks
    active(masks(chrY))["RM"] <- TRUE
    print(chrY)
    
    active(masks(chrY)) <- FALSE
    active(masks(chrY))["AGAPS"] <- TRUE
    
    # 3. Compute masked-aware statistics
    af_unmasked_direct <- alphabetFrequency(unmasked(chrY))
    af_masked_direct <- alphabetFrequency(chrY)
    
    # 4. Coerce the masked sequence to XStringViews and extract gaps
    views_chrY <- as(chrY, "XStringViews")
    gaps_views <- gaps(as(chrY, "XStringViews"))
    gaps_widths <- width(gaps(as(chrY, "XStringViews")))
    
    gaps_chrY_obj <- gaps(chrY)
    af_gaps_chrY <- alphabetFrequency(gaps(chrY))
    
    # Verify that unmasked = masked + gaps
    af0 <- alphabetFrequency(unmasked(chrY))
    af1 <- alphabetFrequency(chrY)
    af2 <- alphabetFrequency(gaps(chrY))
    check_sum <- all(af0 == af1 + af2)
    
    # 5. Perform pattern matching on the masked sequence
    Ebox <- "CANNTG"
    active(masks(chrY)) <- FALSE
    count1 <- countPattern(Ebox, chrY, fixed=FALSE)
    count2 <- countPattern(Ebox, chrY, fixed=c(pattern=FALSE,subject=TRUE))
    
    active(masks(chrY))[c("AGAPS", "AMB")] <- TRUE
    af_base_only <- alphabetFrequency(chrY, baseOnly=TRUE)
    count3 <- countPattern(Ebox, chrY, fixed=FALSE)
    
    # --- Save Outputs ---
    
    # Save alphabet frequencies comparison
    af_df <- data.frame(
      Base = names(af0),
      Unmasked = as.vector(af0),
      Masked_AGAPS = as.vector(af1),
      Gaps = as.vector(af2),
      stringsAsFactors = FALSE
    )
    write.csv(af_df, "alphabet_frequencies.csv", row.names = FALSE)
    
    # Save gaps analysis
    gaps_df <- data.frame(
      Start = start(gaps_views),
      End = end(gaps_views),
      Width = gaps_widths
    )
    write.csv(gaps_df, "gaps_analysis.csv", row.names = FALSE)
    
    # Save pattern matching counts
    counts_df <- data.frame(
      Analysis_Setting = c(
        "fixed=FALSE (all masks inactive)",
        "fixed=c(pattern=FALSE, subject=TRUE) (all masks inactive)",
        "fixed=FALSE (AGAPS and AMB active)"
      ),
      Match_Count = c(count1, count2, count3),
      stringsAsFactors = FALSE
    )
    write.csv(counts_df, "pattern_counts.csv", row.names = FALSE)
    
    # Save binary summary object
    summary_data <- list(
      chromosome = "chrY",
      assembly = metadata(genome)\$genome,
      unmasked_equals_masked_plus_gaps = check_sum,
      base_only_frequency_with_active_masks = af_base_only
    )
    saveRDS(summary_data, "masked_sequence_analysis_summary.rds")

    writeLines(c(
        '"BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS":',
        paste0('    BSgenome: ', as.character(packageVersion('BSgenome')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_masked_sequence_analysis.csv versions.yml
    """
}

workflow BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSgenome.Hsapiens.UCSC.hg38.masked ] ]

    main:
    BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS.out.tables
    plots    = BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS.out.plots
    objects  = BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS.out.objects
    versions = BIOC_BSGENOME_MASKED_SEQUENCE_ANALYSIS.out.versions
}
