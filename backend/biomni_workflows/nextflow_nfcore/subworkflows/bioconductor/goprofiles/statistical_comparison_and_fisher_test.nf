#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: goProfiles — statistical_comparison_and_fisher_test
// Perform statistical tests to determine if two gene lists are functionally different globally and identify which specific GO categories drive the difference.
// Input: list1, list2
// Container: quay.io/biocontainers/bioconductor-goprofiles:1.72.0--r45hdfd78af_0
// R packages: goProfiles, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: goProfiles, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compute global difference between gene lists using `compareGeneLists`
//  * 2. [Visualization & Output] Summarize the comparison using `compSummary`
//  * 3. [Core Analysis] Compute the basic profile of the intersection of the gene lists using `basicProfile`
//  * 4. [Core Analysis] Perform category-by-category Fisher's exact tests using `fisherGOProfiles`

nextflow.enable.dsl = 2

process BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST {
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
    library(goProfiles)
    library(org.Hs.eg.db)
    
    # Helper function to read gene lists from the working directory
    read_gene_list <- function(filename) {
      if (file.exists(filename)) {
        genes <- scan(filename, what = character(), quiet = TRUE)
        return(genes)
      } else if (file.exists(paste0(filename, ".txt"))) {
        genes <- scan(paste0(filename, ".txt"), what = character(), quiet = TRUE)
        return(genes)
      } else {
        stop(paste("Input file", filename, "not found in the working directory."))
      }
    }
    
    # Read user input files
    list1 <- read_gene_list("list1")
    list2 <- read_gene_list("list2")
    
    # Step 1: Compute global difference between gene lists using compareGeneLists
    compared.welsh.singh.01.MF <- compareGeneLists(list1, list2, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    
    # Step 2: Summarize the comparison using compSummary
    comp_sum <- compSummary(compared.welsh.singh.01.MF)
    print(comp_sum)
    
    # Save comparison summary to CSV and RDS
    write.csv(as.data.frame(comp_sum), "comparison_summary.csv", row.names = TRUE)
    saveRDS(compared.welsh.singh.01.MF, "compared_welsh_singh_01_MF.rds")
    
    # Step 3: Compute basic profiles for list1, list2, and their intersection
    welsh.MF <- basicProfile(list1, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    singh.MF <- basicProfile(list2, onto="MF", level=2, orgPackage="org.Hs.eg.db")
    commProf <- basicProfile(intersect(list1, list2), onto="MF", level=2, orgPackage="org.Hs.eg.db")\$MF
    
    # Step 4: Perform category-by-category Fisher's exact tests using fisherGOProfiles
    fisher_results <- fisherGOProfiles(welsh.MF\$MF, singh.MF\$MF, commProf, method="holm")
    print(fisher_results)
    
    # Save Fisher's test results to CSV and RDS
    fisher_df <- data.frame(
      GOID = names(fisher_results),
      Adjusted_pValue = as.vector(fisher_results),
      Unadjusted_pValue = attr(fisher_results, "unadjusted")
    )
    write.csv(fisher_df, "fisher_go_profiles_results.csv", row.names = FALSE)
    saveRDS(fisher_results, "fisher_results.rds")
    
    # Generate and save comparison plots
    tryCatch({
      pdf("profiles_comparison_plot.pdf", width = 10, height = 8)
      merged_prof <- mergeProfilesLists(welsh.MF, singh.MF, profNames = c("List1", "List2"))
      plotProfiles(merged_prof, percentage = TRUE, aTitle = "List1 vs List2 Comparison", legend = TRUE)
      dev.off()
    }, error = function(e) {
      warning("Could not generate comparison plot: ", e\$message)
    })

    writeLines(c(
        '"BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST":',
        paste0('    goProfiles: ', as.character(packageVersion('goProfiles')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_statistical_comparison_and_fisher_test.csv versions.yml
    """
}

workflow BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1, list2 ] ]

    main:
    BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST(ch_input)

    emit:
    tables   = BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST.out.tables
    plots    = BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST.out.plots
    objects  = BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST.out.objects
    versions = BIOC_GOPROFILES_STATISTICAL_COMPARISON_AND_FISHER_TEST.out.versions
}
