#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylGSA — custom_annotation_analysis
// Perform gene set analysis using a user-supplied CpG-to-gene mapping and custom gene sets.
// Input: cpg.pval, CpG2Gene, GS.list
// Container: quay.io/biocontainers/bioconductor-methylgsa:1.16.0--r42hdfd78af_0
// R packages: methylGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: methylGSA
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the custom CpG-to-gene mapping using prepareAnnot
//  * 2. [Core Analysis] Run gene set testing using methylRRA with the custom annotation and custom gene sets

nextflow.enable.dsl = 2

process BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-epigenomics:3.20-slim"

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
    .bm_deps <- c("methylGSA")
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
                library(methylGSA)
                
                # Helper function to read files robustly from the working directory
                read_input = function(filename) {
                  if (!file.exists(filename)) {
                    stop(paste("Required input file missing:", filename))
                  }
                  
                  # Try reading as RDS
                  res = tryCatch(readRDS(filename), error = function(e) NULL)
                  if (!is.null(res)) return(res)
                  
                  # Try reading as CSV
                  res = tryCatch(read.csv(filename, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
                  if (!is.null(res)) return(res)
                  
                  # Try reading as TSV/table
                  res = tryCatch(read.table(filename, header = TRUE, stringsAsFactors = FALSE), error = function(e) NULL)
                  if (!is.null(res)) return(res)
                  
                  stop(paste("Could not parse input file:", filename))
                }
                
                # 1. Load user-supplied input files
                cpg.pval_raw = read_input("cpg.pval")
                if (is.numeric(cpg.pval_raw) && !is.null(names(cpg.pval_raw))) {
                  cpg.pval = cpg.pval_raw
                } else if (is.data.frame(cpg.pval_raw)) {
                  cpg.pval = as.numeric(cpg.pval_raw[[2]])
                  names(cpg.pval) = as.character(cpg.pval_raw[[1]])
                } else {
                  stop("cpg.pval must be a named numeric vector or a 2-column data frame/matrix.")
                }
                
                CpG2Gene = read_input("CpG2Gene")
                if (!is.data.frame(CpG2Gene) && !is.matrix(CpG2Gene)) {
                  stop("CpG2Gene must be a data frame or matrix.")
                }
                
                GS.list = read_input("GS.list")
                if (!is.list(GS.list)) {
                  stop("GS.list must be a list of gene sets.")
                }
                
                # 2. Preprocess the custom CpG-to-gene mapping using prepareAnnot
                FullAnnot = prepareAnnot(CpG2Gene) 
                
                # 3. Run gene set testing using methylRRA with the custom annotation and custom gene sets
                res5 = methylRRA(cpg.pval = cpg.pval, FullAnnot = FullAnnot, method = "ORA", 
                                    GS.list = GS.list, GS.idtype = "SYMBOL", 
                                    minsize = 100, maxsize = 300)
                
                # 4. Write outputs
                write.csv(res5, "methylRRA_results.csv", row.names = FALSE)
                saveRDS(res5, "methylRRA_results.rds")
                
                # Optional visualization
                tryCatch({
                  pdf("methylRRA_barplot.pdf")
                  # Explicitly call methylGSA::barplot to avoid masking by graphics::barplot
                  # and explicitly print() the resulting ggplot2 object to the PDF device
                  print(methylGSA::barplot(res5, num = 10, colorby = "pvalue"))
                }, error = function(e) {
                  message("Visualization skipped or failed: ", e\$message)
                }, finally = {
                  # Ensure the PDF device is closed even if plotting fails
                  if (names(dev.cur()) != "null device") {
                    dev.off()
                  }
                })

    writeLines(c(
        '"BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS":',
        paste0('    methylGSA: ', as.character(packageVersion('methylGSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_custom_annotation_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpg.pval, CpG2Gene, GS.list ] ]

    main:
    BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS.out.tables
    plots    = BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS.out.plots
    objects  = BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS.out.objects
    versions = BIOC_METHYLGSA_CUSTOM_ANNOTATION_ANALYSIS.out.versions
}
