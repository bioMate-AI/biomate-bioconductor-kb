#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: OrderedList — compare_ordered_lists
// Compare two pre-ordered gene lists directly without underlying expression data.
// Input: list1, list2
// Container: quay.io/biocontainers/bioconductor-orderedlist:1.82.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: OrderedList
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Compare the two ordered lists using compareLists
//  * 2. [Core Analysis] Extract the overlapping genes at a specific rank/percentage using getOverlap
//  * 3. [Visualization & Output] Plot the overlap and score distributions using plot

nextflow.enable.dsl = 2

process BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20"

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
    .bm_deps <- c("OrderedList")
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
    
    # Load required library
    library(OrderedList)
    
    # Locate and read the user input files
    file1 <- "list1"
    if (!file.exists(file1)) {
      file1 <- "list1.txt"
    }
    if (!file.exists(file1)) {
      stop("Error: Input file 'list1' or 'list1.txt' not found in the working directory.")
    }
    
    file2 <- "list2"
    if (!file.exists(file2)) {
      file2 <- "list2.txt"
    }
    if (!file.exists(file2)) {
      stop("Error: Input file 'list2' or 'list2.txt' not found in the working directory.")
    }
    
    # Read ordered gene identifiers as character vectors
    list1 <- as.character(readLines(file1))
    list2 <- as.character(readLines(file2))
    
    # Stage 1: Compare the two ordered lists
    y <- compareLists(list1,list2)
    print(y)
    
    # Stage 2: Extract the overlapping genes
    z <- getOverlap(y)
    print(z)
    print(z\$intersect[1:min(5, length(z\$intersect))])
    
    # Save results to files
    saveRDS(y, file = "compare_lists_result.rds")
    saveRDS(z, file = "overlap_result.rds")
    
    # Export the intersecting genes to a CSV file
    write.csv(data.frame(GeneID = z\$intersect), file = "intersecting_genes.csv", row.names = FALSE)
    
    # Stage 3: Plot the overlap and score distributions
    pdf("overlap_plot.pdf", width = 6, height = 5)
    plot(z)
    dev.off()
    
    pdf("scores_plot.pdf", width = 6, height = 5)
    plot(z,"scores")
    dev.off()

    writeLines(c(
        '"BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS":',
        paste0('    OrderedList: ', as.character(packageVersion('OrderedList')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_compare_ordered_lists.csv versions.yml
    """
}

workflow BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ list1, list2 ] ]

    main:
    BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS(ch_input)

    emit:
    tables   = BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS.out.tables
    plots    = BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS.out.plots
    objects  = BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS.out.objects
    versions = BIOC_ORDEREDLIST_COMPARE_ORDERED_LISTS.out.versions
}
