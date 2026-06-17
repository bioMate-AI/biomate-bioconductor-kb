#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goProfiles — equivalence_testing
// Test if two gene lists are functionally equivalent (statistically similar) rather than different.
// Input: list1, list2
// Container: quay.io/biocontainers/bioconductor-goprofiles:1.72.0--r45hdfd78af_0
// R packages: goProfiles, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: goProfiles, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute expanded profiles for both gene lists using `expandedProfile`
//  * 2. [Core Analysis] Compute the expanded profile for the intersection of both gene lists using `expandedProfile`
//  * 3. [Core Analysis] Perform equivalence testing using `equivalentGOProfiles`
//  * 4. [Visualization & Output] Summarize the equivalence test results using `equivSummary`

nextflow.enable.dsl = 2

process BIOC_GOPROFILES_EQUIVALENCE_TESTING {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

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
    .bm_deps <- c("goProfiles", "org.Hs.eg.db")
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
    library(goProfiles)
    library(org.Hs.eg.db)
    
    # Define input file paths
    file1 <- "list1"
    file2 <- "list2"
    
    # Fallback to .txt extension if files without extension are not found
    if (!file.exists(file1) && file.exists("list1.txt")) {
      file1 <- "list1.txt"
    }
    if (!file.exists(file2) && file.exists("list2.txt")) {
      file2 <- "list2.txt"
    }
    
    # Verify input files exist
    if (!file.exists(file1)) {
      stop(paste("Error: Input file for list1 not found at:", file1))
    }
    if (!file.exists(file2)) {
      stop(paste("Error: Input file for list2 not found at:", file2))
    }
    
    # Read Entrez gene IDs from the files
    genes1 <- unique(as.character(scan(file1, what = character(), quiet = TRUE)))
    genes2 <- unique(as.character(scan(file2, what = character(), quiet = TRUE)))
    
    # Stage 1: Compute expanded profiles for both gene lists using expandedProfile
    expandedWelsh <- expandedProfile(genes1, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    expandedSingh <- expandedProfile(genes2, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    
    # Stage 2: Compute the expanded profile for the intersection of both gene lists using expandedProfile
    commonGenes <- intersect(genes1, genes2)
    if (length(commonGenes) == 0) {
      stop("Error: The intersection of the two gene lists is empty. Equivalence testing requires a non-empty intersection.")
    }
    commonExpanded <- expandedProfile(commonGenes, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    
    # Stage 3: Perform equivalence testing using equivalentGOProfiles
    equivMF <- equivalentGOProfiles(expandedWelsh[['MF']], qm = expandedSingh[['MF']], pqn0 = commonExpanded[['MF']])
    
    # Stage 4: Summarize the equivalence test results using equivSummary
    summary_results <- equivSummary(equivMF, decs=5)
    print(summary_results)
    
    # Write meaningful output files
    saveRDS(equivMF, file = "equivalence_results.rds")
    write.csv(as.data.frame(summary_results), file = "equivalence_summary.csv", row.names = TRUE)

    writeLines(c(
        '"BIOC_GOPROFILES_EQUIVALENCE_TESTING":',
        paste0('    goProfiles: ', as.character(packageVersion('goProfiles')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_equivalence_testing.csv versions.yml
    """
}

workflow BIOC_GOPROFILES_EQUIVALENCE_TESTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1, list2 ] ]

    main:
    BIOC_GOPROFILES_EQUIVALENCE_TESTING(ch_input)

    emit:
    tables   = BIOC_GOPROFILES_EQUIVALENCE_TESTING.out.tables
    plots    = BIOC_GOPROFILES_EQUIVALENCE_TESTING.out.plots
    objects  = BIOC_GOPROFILES_EQUIVALENCE_TESTING.out.objects
    versions = BIOC_GOPROFILES_EQUIVALENCE_TESTING.out.versions
}
