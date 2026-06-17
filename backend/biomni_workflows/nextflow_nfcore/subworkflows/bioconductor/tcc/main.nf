#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: TCC — two_group_replicates
// Perform robust differential expression analysis on two-group RNA-seq count data with biological replicates using iterative iDEGES/edgeR normalization.
// Input: hypoData, group
// Container: quay.io/biocontainers/bioconductor-tcc:1.50.0--r45hdfd78af_0
// R packages: roc, TCC
// Bioconductor: 3.20 | R: 4.4
// Requires: TCC
// Visualizations: plot (ggplot/base)
// QC: TMM normalization, low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Visualization & Output] Read User Input Files
//  * 2. [Visualization & Output] Execute TCC Workflow
//  * 3. [Visualization & Output] Write Output Files

nextflow.enable.dsl = 2

process BIOC_TCC_TWO_GROUP_REPLICATES {
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
    .bm_deps <- c("roc", "TCC")
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
    library(TCC)
    
    # ---------------------------------------------------------
    # --- Read User Input Files ---
    # ---------------------------------------------------------
    # Locate and read the raw count matrix (hypoData)
    hypoData_file <- NULL
    for (f in c("hypoData", "hypoData.csv", "hypoData.tsv", "hypoData.txt", "hypoData.rds")) {
      if (file.exists(f)) {
        hypoData_file <- f
        break
      }
    }
    if (is.null(hypoData_file)) {
      stop("Error: hypoData file not found in the working directory.")
    }
    
    if (grepl("\\\\.rds\$", hypoData_file, ignore.case = TRUE)) {
      hypoData <- readRDS(hypoData_file)
    } else if (grepl("\\\\.csv\$", hypoData_file, ignore.case = TRUE)) {
      hypoData <- as.matrix(read.csv(hypoData_file, row.names = 1, check.names = FALSE))
    } else {
      hypoData <- as.matrix(read.table(hypoData_file, header = TRUE, row.names = 1, check.names = FALSE))
    }
    
    # Locate and read the group membership vector (group)
    group_file <- NULL
    for (f in c("group", "group.csv", "group.tsv", "group.txt", "group.rds")) {
      if (file.exists(f)) {
        group_file <- f
        break
      }
    }
    if (is.null(group_file)) {
      stop("Error: group file not found in the working directory.")
    }
    
    if (grepl("\\\\.rds\$", group_file, ignore.case = TRUE)) {
      group <- readRDS(group_file)
    } else {
      lines <- readLines(group_file)
      lines <- lines[lines != ""]
      if (length(lines) == 1 && grepl(",", lines)) {
        group <- as.numeric(strsplit(lines, ",")[[1]])
      } else {
        group <- as.numeric(lines)
      }
    }
    
    # ---------------------------------------------------------
    # --- Execute TCC Workflow ---
    # ---------------------------------------------------------
    # Construct TCC class object
    tcc <- new("TCC", hypoData, group)
    
    # Filter out low-count genes
    tcc <- filterLowCountGenes(tcc)
    
    # Calculate robust normalization factors using iterative iDEGES/edgeR
    tcc <- calcNormFactors(tcc, norm.method = "tmm", test.method = "edger", 
                           iteration = 3, FDR = 0.1, floorPDEG = 0.05)
    
    # Perform differential expression analysis using edgeR
    tcc <- estimateDE(tcc, test.method = "edger", FDR = 0.1)
    
    # Retrieve results table
    result <- getResult(tcc, sort = TRUE)
    head(result)
    
    # Print DEG summary to console
    print(table(tcc\$estimatedDEG))
    
    # Retrieve normalized count data
    normalized.count <- getNormalizedData(tcc)
    
    # ---------------------------------------------------------
    # --- Write Output Files ---
    # ---------------------------------------------------------
    # Save DE results table
    write.csv(result, "tcc_de_results.csv", row.names = FALSE)
    
    # Save DEG summary table
    deg_summary <- table(tcc\$estimatedDEG)
    write.table(deg_summary, "tcc_deg_summary.txt", col.names = FALSE, quote = FALSE)
    
    # Save M-A plot as PDF
    pdf("tcc_ma_plot.pdf")
    plot(tcc)
    dev.off()
    
    # Save normalized count data
    write.csv(normalized.count, "tcc_normalized_counts.csv")
    
    # Save the complete TCC object
    saveRDS(tcc, "tcc_object.rds")

    writeLines(c(
        '"BIOC_TCC_TWO_GROUP_REPLICATES":',
        paste0('    TCC: ', as.character(packageVersion('TCC')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_two_group_replicates.csv versions.yml
    """
}

workflow BIOC_TCC_TWO_GROUP_REPLICATES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ hypoData, group ] ]

    main:
    BIOC_TCC_TWO_GROUP_REPLICATES(ch_input)

    emit:
    tables   = BIOC_TCC_TWO_GROUP_REPLICATES.out.tables
    plots    = BIOC_TCC_TWO_GROUP_REPLICATES.out.plots
    objects  = BIOC_TCC_TWO_GROUP_REPLICATES.out.objects
    versions = BIOC_TCC_TWO_GROUP_REPLICATES.out.versions
}
