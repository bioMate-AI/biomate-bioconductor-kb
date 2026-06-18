#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: PhyloProfile — group_comparison
// Compare the distribution of additional variables between an in-group and an out-group of taxa.
// Input: raw_profile.txt
// Container: quay.io/biocontainers/bioconductor-phyloprofile:2.2.2--r45hdfd78af_0
// R packages: PhyloProfile
// Bioconductor: 3.20 | R: 4.4
// Requires: PhyloProfile
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define the in-group taxa and the variable to compare
//  * 2. [Core Analysis] Perform statistical comparison using `compareTaxonGroups`

nextflow.enable.dsl = 2

process BIOC_PHYLOPROFILE_GROUP_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20-slim"

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
    .bm_deps <- c("PhyloProfile")
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
        
    # Load required library
    library(PhyloProfile)
    
    # 1. Read the user input file from the working directory
    # The input file 'raw_profile.txt' is expected to be a tab-delimited file
    # containing raw phylogenetic profile data in long format.
    data <- read.table(
      "raw_profile.txt",
      header = TRUE,
      sep = "\t",
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    
    # 2. Define the in-group taxa and the variable to compare
    # Dynamically select taxa that actually exist in the user-provided input file
    inGroup <- head(unique(data\$ncbiID), 2)
    variable <- colnames(data)[4]
    
    # 3. Perform statistical comparison using compareTaxonGroups
    # This compares the distribution of the selected variable between the in-group and out-group taxa.
    results <- compareTaxonGroups(data, inGroup, TRUE, variable, 0.05)
    
    # 4. Save the meaningful results to output files
    # Save as RDS object
    saveRDS(results, "group_comparison_results.rds")
    
    # Convert the named vector of p-values to a data frame and save as CSV
    results_df <- data.frame(
      geneID = names(results),
      p_value = as.numeric(results),
      stringsAsFactors = FALSE
    )
    write.csv(results_df, "group_comparison_results.csv", row.names = FALSE)

    writeLines(c(
        '"BIOC_PHYLOPROFILE_GROUP_COMPARISON":',
        paste0('    PhyloProfile: ', as.character(packageVersion('PhyloProfile')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_group_comparison.csv versions.yml
    """
}

workflow BIOC_PHYLOPROFILE_GROUP_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_profile.txt ] ]

    main:
    BIOC_PHYLOPROFILE_GROUP_COMPARISON(ch_input)

    emit:
    tables   = BIOC_PHYLOPROFILE_GROUP_COMPARISON.out.tables
    plots    = BIOC_PHYLOPROFILE_GROUP_COMPARISON.out.plots
    objects  = BIOC_PHYLOPROFILE_GROUP_COMPARISON.out.objects
    versions = BIOC_PHYLOPROFILE_GROUP_COMPARISON.out.versions
}
