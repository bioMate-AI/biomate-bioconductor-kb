#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: SpliceWiz — coverage_visualization
// Generate normalized group-averaged or individual coverage plots for specific splicing events.
// Input: se, res_edgeR
// Container: quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0
// R packages: SpliceWiz
// Bioconductor: 3.20 | R: 4.4
// Requires: SpliceWiz
// Visualizations: coverage plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Retrieve coverage data for a gene using getCoverageData()
//  * 2. [Visualization & Output] Get normalized event-specific plot object using getPlotObject()
//  * 3. [Visualization & Output] Plot coverage using plotView()

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION {
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
    .bm_deps <- c("SpliceWiz")
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
            library(SpliceWiz)
            
            # -----------------------------------------------------------------------------
            # 1. READ USER INPUTS
            # -----------------------------------------------------------------------------
            # The pipeline expects 'se.rds' (NxtSE object) and 'res_edgeR.rds' (differential expression results)
            # to be present in the working directory.
            
            se_path <- "se.rds"
            res_path <- "res_edgeR.rds"
            
            if (!file.exists(se_path)) {
                stop(paste("Required input file missing:", se_path))
            }
            if (!file.exists(res_path)) {
                stop(paste("Required input file missing:", res_path))
            }
            
            se <- readRDS(se_path)
            res_edgeR <- readRDS(res_path)
            
            # -----------------------------------------------------------------------------
            # 2. ROBUST ADAPTATION FOR USER DATA
            # -----------------------------------------------------------------------------
            # Filter res_edgeR first to find the top event
            res_edgeR.filtered <- res_edgeR[!is.na(res_edgeR\$FDR) & res_edgeR\$FDR < 0.05 ,]
            if (nrow(res_edgeR.filtered) == 0) {
                # Fallback if no events pass the threshold: use the top event sorted by FDR
                res_edgeR.filtered <- res_edgeR[order(res_edgeR\$FDR), , drop = FALSE]
            }
            
            # Dynamically extract the gene of the first event
            first_event <- res_edgeR.filtered\$EventName[1]
            target_gene <- strsplit(first_event, "/")[[1]][1]
            
            # -----------------------------------------------------------------------------
            # 3. EXACT DOCUMENTED CODE WORKFLOW
            # -----------------------------------------------------------------------------
            dataObj <- getCoverageData(se, Gene = target_gene, tracks = colnames(se))
            plotObj <- getPlotObject(dataObj, Event = first_event)
            
            # Open PDF device to save the coverage plot
            pdf("coverage_visualization.pdf", width = 12, height = 8)
            print(plotView(plotObj, centerByEvent = TRUE, trackList = as.list(seq_len(ncol(se))), plotJunctions = TRUE))
            dev.off()
            
            # -----------------------------------------------------------------------------
            # 4. WRITE MEANINGFUL OUTPUTS
            # -----------------------------------------------------------------------------
            # Save the filtered differential events to a CSV file
            write.csv(as.data.frame(res_edgeR.filtered), "filtered_differential_events.csv", row.names = FALSE)
            
            # Save the plot object for downstream interactive use
            saveRDS(plotObj, "coverage_plot_object.rds")

    writeLines(c(
        '"BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION":',
        paste0('    SpliceWiz: ', as.character(packageVersion('SpliceWiz')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_coverage_visualization.csv versions.yml
    """
}

workflow BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ se, res_edgeR ] ]

    main:
    BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION.out.tables
    plots    = BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION.out.plots
    objects  = BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION.out.objects
    versions = BIOC_SPLICEWIZ_COVERAGE_VISUALIZATION.out.versions
}
