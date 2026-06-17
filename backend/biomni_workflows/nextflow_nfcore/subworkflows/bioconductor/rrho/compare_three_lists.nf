#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RRHO — compare_three_lists
// Compare three ranked lists to test whether the difference between list 1 and list 3 is different from the difference between list 2 and list 3.
// Input: list1, list2, list3
// Container: quay.io/biocontainers/bioconductor-rrho:1.50.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RRHO, lattice
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Perform three-list comparison using RRHOComparison
//  * 2. [Visualization & Output] Visualize the standard RRHO map between list 1 and list 3 using lattice::levelplot
//  * 3. [Visualization & Output] Visualize the p-value of the difference using lattice::levelplot

nextflow.enable.dsl = 2

process BIOC_RRHO_COMPARE_THREE_LISTS {
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
    .bm_deps <- c("RRHO", "lattice")
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
    library(RRHO)
    library(lattice)
    
    # Helper function to read input files robustly
    read_input_list <- function(filename) {
      # Check for exact filename, then with common extensions
      possible_files <- c(
        filename,
        paste0(filename, ".csv"),
        paste0(filename, ".tsv"),
        paste0(filename, ".txt")
      )
      
      found_file <- NULL
      for (f in possible_files) {
        if (file.exists(f)) {
          found_file <- f
          break
        }
      }
      
      if (is.null(found_file)) {
        stop(paste("Error: Input file for", filename, "not found in the working directory."))
      }
      
      # Attempt to read the file
      df <- tryCatch({
        read.csv(found_file, header = TRUE, stringsAsFactors = FALSE)
      }, error = function(e) {
        read.table(found_file, header = TRUE, stringsAsFactors = FALSE)
      })
      
      # Ensure the data frame has at least two columns and rename them to match expectations
      if (ncol(df) < 2) {
        stop(paste("Error: File", found_file, "must have at least two columns (GeneIdentifier and RankingVal)."))
      }
      
      colnames(df)[1:2] <- c("GeneIdentifier", "RankingVal")
      return(df[, 1:2])
    }
    
    # 1. Read the declared USER INPUT files
    list1 <- read_input_list("list1")
    list2 <- read_input_list("list2")
    list3 <- read_input_list("list3")
    
    # Define output directory
    temp.dir <- "rrho_output"
    if (!dir.exists(temp.dir)) {
      dir.create(temp.dir, recursive = TRUE)
    }
    
    # 2. Perform three-list comparison using RRHOComparison
    # Keeping function call and argument names EXACTLY as documented
    rrho.comparison<- RRHOComparison(list1,list2,list3,
                    stepsize=10,
                    labels=c("list1",
                             "list2",
                             "list3"),
                    plots=FALSE,
                    outputdir=temp.dir);
    
    # 3. Visualize the standard RRHO map between list 1 and list 3 using lattice::levelplot
    pdf(file.path(temp.dir, "rrho_map_list1_list3.pdf"))
    print(lattice::levelplot(rrho.comparison\$hypermat1))
    dev.off()
    
    # 4. Visualize the p-value of the difference using lattice::levelplot
    pdf(file.path(temp.dir, "rrho_pdiff.pdf"))
    print(lattice::levelplot(rrho.comparison\$Pdiff))
    dev.off()
    
    # 5. Save meaningful results to output files
    saveRDS(rrho.comparison, file = file.path(temp.dir, "rrho_comparison.rds"))
    write.csv(as.data.frame(rrho.comparison\$hypermat1), file = file.path(temp.dir, "hypermat1.csv"), row.names = TRUE)
    write.csv(as.data.frame(rrho.comparison\$Pdiff), file = file.path(temp.dir, "Pdiff.csv"), row.names = TRUE)

    writeLines(c(
        '"BIOC_RRHO_COMPARE_THREE_LISTS":',
        paste0('    RRHO: ', as.character(packageVersion('RRHO')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_three_lists.csv versions.yml
    """
}

workflow BIOC_RRHO_COMPARE_THREE_LISTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1, list2, list3 ] ]

    main:
    BIOC_RRHO_COMPARE_THREE_LISTS(ch_input)

    emit:
    tables   = BIOC_RRHO_COMPARE_THREE_LISTS.out.tables
    plots    = BIOC_RRHO_COMPARE_THREE_LISTS.out.plots
    objects  = BIOC_RRHO_COMPARE_THREE_LISTS.out.objects
    versions = BIOC_RRHO_COMPARE_THREE_LISTS.out.versions
}
