#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: Cepo — standard_differential_stability
// Run differential stability analysis on normalized scRNA-seq data to identify cell identity genes, with optional filtering, p-value calculation, and visualizatio
// Input: cellbench
// Container: quay.io/biocontainers/bioconductor-cepo:1.16.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Cepo, SingleCellExperiment, UpSetR
// Visualizations: plot (ggplot/base)
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
