#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methylGSA — methylrra_analysis
// Perform gene set analysis using Robust Rank Aggregation (RRA) to adjust for multiple CpG p-values per gene, followed by either ORA or GSEA.
// Input: cpg.pval
// Container: quay.io/biocontainers/bioconductor-methylgsa:1.16.0--r42hdfd78af_0
// R packages: IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Bioconductor: 3.20 | R: 4.4
// Requires: IlluminaHumanMethylation450kanno.ilmn12.hg19, methylGSA
// Visualizations: bar plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and array annotation
//  * 2. [Core Analysis] Run RRA with Over-Representation Analysis (ORA)
//  * 3. [Core Analysis] Run RRA with Gene Set Enrichment Analysis (GSEA)

nextflow.enable.dsl = 2

process BIOC_METHYLGSA_METHYLRRA_ANALYSIS {
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
    .bm_deps <- c("IlluminaHumanMethylation450kanno.ilmn12.hg19", "methylGSA")
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
        
        # 1. Load the package and array annotation
        library(methylGSA)
        library(IlluminaHumanMethylation450kanno.ilmn12.hg19)
        
        # Read user input 'cpg.pval' from the working directory
        if (file.exists("cpg.pval")) {
          cpg.pval <- tryCatch({
            readRDS("cpg.pval")
          }, error = function(e) {
            # Fallback to reading as a table if it is not an RDS file
            tab <- read.table("cpg.pval", header = TRUE, stringsAsFactors = FALSE)
            if (ncol(tab) >= 2) {
              vec <- as.numeric(tab[, 2])
              names(vec) <- as.character(tab[, 1])
              vec
            } else {
              vec <- as.numeric(tab[, 1])
              names(vec) <- rownames(tab)
              vec
            }
          })
        } else {
          stop("Required input file 'cpg.pval' not found in the working directory.")
        }
        
        # Ensure cpg.pval is a valid named numeric vector
        if (!is.numeric(cpg.pval) || is.null(names(cpg.pval))) {
          stop("Input 'cpg.pval' must be a named numeric vector of CpG p-values.")
        }
        
        # 2. Run RRA with Over-Representation Analysis (ORA)
        res2 = methylRRA(cpg.pval = cpg.pval, method = "ORA")
        
        # Save ORA results
        write.csv(res2, file = "methylRRA_ORA_results.csv", row.names = FALSE)
        saveRDS(res2, file = "methylRRA_ORA_results.rds")
        
        # 3. Run RRA with Gene Set Enrichment Analysis (GSEA)
        res3 = methylRRA(cpg.pval = cpg.pval, method = "GSEA")
        
        # Save GSEA results
        write.csv(res3, file = "methylRRA_GSEA_results.csv", row.names = FALSE)
        saveRDS(res3, file = "methylRRA_GSEA_results.rds")
        
        # 4. Visualization
        pdf("methylRRA_results_plots.pdf", width = 8, height = 6)
        
        # Plot ORA results if available
        tryCatch({
          if (!is.null(res2) && nrow(res2) > 0) {
            print(barplot(res2, num = 8, colorby = "pvalue", title = "methylRRA ORA Results"))
          }
        }, error = function(e) {
          message("Could not generate ORA barplot: ", e\$message)
        })
        
        # Plot GSEA results if available
        tryCatch({
          if (!is.null(res3) && nrow(res3) > 0) {
            print(barplot(res3, num = 8, colorby = "pvalue", title = "methylRRA GSEA Results"))
          }
        }, error = function(e) {
          message("Could not generate GSEA barplot: ", e\$message)
        })
        
        dev.off()

    writeLines(c(
        '"BIOC_METHYLGSA_METHYLRRA_ANALYSIS":',
        paste0('    methylGSA: ', as.character(packageVersion('methylGSA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_methylrra_analysis.csv versions.yml
    """
}

workflow BIOC_METHYLGSA_METHYLRRA_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cpg.pval ] ]

    main:
    BIOC_METHYLGSA_METHYLRRA_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHYLGSA_METHYLRRA_ANALYSIS.out.tables
    plots    = BIOC_METHYLGSA_METHYLRRA_ANALYSIS.out.plots
    objects  = BIOC_METHYLGSA_METHYLRRA_ANALYSIS.out.objects
    versions = BIOC_METHYLGSA_METHYLRRA_ANALYSIS.out.versions
}
