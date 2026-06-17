#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bsgenome — masked_genome_analysis
// Count pattern occurrences in a masked genome while ignoring assembly gaps, ambiguities, or repeat regions.
// Input: BSgenome.Hsapiens.UCSC.hg38.masked
// Container: quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0
// R packages: BSgenome.Hsapiens.UCSC.hg38.masked
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_BSGENOME_MASKED_GENOME_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-bsgenome:1.78.0--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38.masked")
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
    
    # --- Load the masked genome package (handling local user input ---
    pkg_path <- "BSgenome.Hsapiens.UCSC.hg38.masked"
    if (dir.exists(pkg_path)) {
      install.packages(pkg_path, repos = NULL, type = "source")
    } else if (file.exists(pkg_path)) {
      install.packages(pkg_path, repos = NULL, type = "source")
    }
    
    library(BSgenome.Hsapiens.UCSC.hg38.masked)
    
    # --- Access a specific chromosome (returns a MaskedDNAString) ---
    genome <- BSgenome.Hsapiens.UCSC.hg38.masked
    chrY <- genome\$chrY
    
    # --- Activate or deactivate specific built-in masks ---
    active(masks(chrY))["RM"] <- TRUE
    active(masks(chrY)) <- FALSE
    active(masks(chrY))["AGAPS"] <- TRUE
    
    Ebox <- "CANNTG"
    
    active(masks(chrY))[c("AGAPS", "AMB")] <- TRUE
    
    # --- Count pattern occurrences using countPattern with mask ---
    final_count <- countPattern(Ebox, chrY, fixed=FALSE)
    
    # Write the meaningful results to output files
    results <- data.frame(
      Pattern = Ebox,
      Chromosome = "chrY",
      Count = final_count,
      AGAPS_Mask_Active = active(masks(chrY))["AGAPS"],
      AMB_Mask_Active = active(masks(chrY))["AMB"],
      RM_Mask_Active = active(masks(chrY))["RM"],
      TRF_Mask_Active = active(masks(chrY))["TRF"]
    )
    
    write.csv(results, "masked_genome_analysis_results.csv", row.names = FALSE)
    
    # Save the masked chromosome object as an RDS file
    saveRDS(chrY, "masked_chrY.rds")
    
    message("Analysis complete. Results written to 'masked_genome_analysis_results.csv' and 'masked_chrY.rds'.")

    writeLines(c(
        '"BIOC_BSGENOME_MASKED_GENOME_ANALYSIS":',
        paste0('        bsgenome: ', as.character(packageVersion("bsgenome")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_masked_genome_analysis.csv versions.yml
    """
}

workflow BIOC_BSGENOME_MASKED_GENOME_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ BSgenome.Hsapiens.UCSC.hg38.masked ] ]

    main:
    BIOC_BSGENOME_MASKED_GENOME_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BSGENOME_MASKED_GENOME_ANALYSIS.out.tables
    plots    = BIOC_BSGENOME_MASKED_GENOME_ANALYSIS.out.plots
    objects  = BIOC_BSGENOME_MASKED_GENOME_ANALYSIS.out.objects
    versions = BIOC_BSGENOME_MASKED_GENOME_ANALYSIS.out.versions
}
