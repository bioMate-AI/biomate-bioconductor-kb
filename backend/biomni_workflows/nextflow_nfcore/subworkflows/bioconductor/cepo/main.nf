#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cepo — standard_differential_stability
// Run differential stability analysis on normalized scRNA-seq data to identify cell identity genes, with optional filtering, p-value calculation, and visualizatio
// Input: cellbench
// Container: quay.io/biocontainers/bioconductor-cepo:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Cepo, SingleCellExperiment, UpSetR
// Visualizations: density plot, UpSet plot
// QC: normalization diagnostic plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load data and extract logcounts matrix
//  * 2. [Core Analysis] Run Cepo with default parameters
//  * 3. [Core Analysis] Run Cepo with expression percentage filtering
//  * 4. [Core Analysis] Run Cepo with log fold-change filtering
//  * 5. [Core Analysis] Compute p-values using fast normal approximation or permutation bootstrap
//  * 6. [Core Analysis] Extract top marker genes
//  * 7. [Visualization & Output] Visualize results using UpSet plots and density plots

nextflow.enable.dsl = 2

process BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim"

    input:
    tuple val(meta), path(input_files, stageAs: '?/*')

    output:
    tuple val(meta), path("*.csv"), emit: tables, optional: true
    tuple val(meta), path("*.pdf"), emit: plots,  optional: true
    tuple val(meta), path("*.rds"), emit: objects, optional: true
    tuple val(meta), path("qc_metrics.json"), emit: qc_metrics
    path "versions.yml",            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    # [biomate-deps] resolve declared dependencies so the workflow runs in any environment
    .bm_deps <- c("Cepo", "UpSetR")
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
        library(Cepo)
        library(UpSetR)
        
        # 1. Load data and extract logcounts matrix
        # Reading the cellbench SingleCellExperiment object from the working directory
        if (file.exists("cellbench")) {
          cellbench <- readRDS("cellbench")
        } else if (file.exists("cellbench.rds")) {
          cellbench <- readRDS("cellbench.rds")
        } else {
          stop("Required input file 'cellbench' or 'cellbench.rds' not found in the working directory.")
        }
        
        # Remove duplicated genes
        cellbench = cellbench[!duplicated(rownames(cellbench)),]
        
        # 2. Run Cepo with default parameters
        ds_res = Cepo(exprsMat = logcounts(cellbench),
                      cellType = cellbench\$celltype)
        
        # Save default Cepo results
        saveRDS(ds_res, "ds_res.rds")
        
        # 3. Run Cepo with expression percentage filtering
        ds_res_zprop = Cepo::Cepo(exprsMat = logcounts(cellbench),
                                  cellTypes = cellbench\$celltype,
                                  exprsPct = 0.5)
        
        # Save zprop Cepo results
        saveRDS(ds_res_zprop, "ds_res_zprop.rds")
        
        # 4. Run Cepo with log fold-change filtering
        ds_res_logfc = Cepo(exprsMat = logcounts(cellbench),
                            cellTypes = cellbench\$celltype,
                            logfc = 1)
        
        # Save logfc Cepo results
        saveRDS(ds_res_logfc, "ds_res_logfc.rds")
        
        # 5. Compute p-values using fast normal approximation
        ds_res_pvalues = Cepo(exprsMat = logcounts(cellbench),
                              cellType = cellbench\$celltype, 
                              computePvalue = 200,
                              prefilter_pzero = 0.4)
        
        # Save fast p-value Cepo results
        saveRDS(ds_res_pvalues, "ds_res_pvalues_fast.rds")
        
        # Compute p-values using permutation bootstrap
        ds_res_pvalues = Cepo(exprsMat = logcounts(cellbench),
                              cellType = cellbench\$celltype, 
                              # we use a low value for demonstration purposes
                              computePvalue = 100,
                              computeFastPvalue = FALSE)
        
        # Save permutation p-value Cepo results
        saveRDS(ds_res_pvalues, "ds_res_pvalues_permutation.rds")
        
        # 6. Extract top marker genes
        res_name = topGenes(object = ds_res, n = 500)
        
        # Save top genes to a CSV file
        res_name_df <- as.data.frame(res_name)
        write.csv(res_name_df, "top_genes_cepo.csv", row.names = FALSE)
        
        # 7. Visualize results using UpSet plots and density plots
        pdf("cepo_visualizations.pdf", width = 10, height = 8)
        
        # UpSet plot of top genes
        print(upset(fromList(res_name), nsets = length(res_name)))
        
        # Density plot of top 2 genes from each cell type
        print(plotDensities(x = cellbench,
                      cepoOutput = ds_res,
                      nGenes = 2,
                      assay = "logcounts",
                      celltypeColumn = "celltype"))
        
        # Density plot of specific genes
        # Note: We wrap this in a tryCatch in case the input cellbench object 
        # does not contain these specific gene names.
        tryCatch({
          print(plotDensities(x = cellbench,
                        cepoOutput = ds_res,
                        genes = c("PLTP", "CPT1C", "MEG3", "SYCE1", "MICOS10P3", "HOXB7"),
                        assay = "logcounts",
                        celltypeColumn = "celltype"))
        }, error = function(e) {
          warning("Could not plot specific genes: ", e\$message)
        })
        
        dev.off()
    # ── BIOC_QC_HARNESS — Phase 3c multi-label adoption ───────────────────────
    # Per-label metric computation. Each block is defensive (tryCatch +
    # isTRUE patterns) so a failed metric never breaks the whole emit.
    .qc_metrics_path <- "qc_metrics.json"
    .gates_by_label <- list()

    # normalization diagnostic plot — file-exists check for any PDF emitted
    # with "norm" / "mean_sd" / "library" in the filename. Pairs with
    # bioc_count_normalization (numeric metric); this row is the visual gate.
    .ndp_pdfs <- list.files(".", pattern = "(?i)(norm|mean.?sd|library).*\\.pdf\$")
    .ndp_passes <- length(.ndp_pdfs) > 0
    .gates_by_label[["normalization diagnostic plot"]] <- list(
      gate_row = "bioc_normalization_diagnostic_plot",
      metric_name = "normalization_plot_exists",
      metric_value = if (.ndp_passes) 1 else 0,
      passes = .ndp_passes,
      status = if (.ndp_passes) paste0("computed (", length(.ndp_pdfs), " diagnostic PDF(s) emitted)")
               else "not_computed (no normalization diagnostic PDF found)"
    )

    .qc_payload <- list(
      success = TRUE,
      process = "BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY",
      domain  = "bioconductor",
      declared_qc_steps = c("normalization diagnostic plot"),
      gates_by_label = .gates_by_label,
      evidence_tier = "mixed (per bioconductor_qc.* rows in qc_evidence.yaml)",
      harness_version = "0.2.0-multi"
    )
    cat(jsonlite::toJSON(.qc_payload, auto_unbox = TRUE, pretty = TRUE, null = "null"),
        file = .qc_metrics_path)



    writeLines(c(
        '"BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY":',
        paste0('    Cepo: ', as.character(packageVersion('Cepo')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_differential_stability.csv versions.yml
    """
}

workflow BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ cellbench ] ]

    main:
    BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY(ch_input)

    emit:
    tables   = BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY.out.tables
    plots    = BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY.out.plots
    objects  = BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY.out.objects
    versions = BIOC_CEPO_STANDARD_DIFFERENTIAL_STABILITY.out.versions
}
