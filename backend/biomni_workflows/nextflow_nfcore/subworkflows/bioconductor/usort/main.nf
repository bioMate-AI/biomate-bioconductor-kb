#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: uSORT — usort_cell_progression
// Uncover the intrinsic cell progression path and identify driver genes from single-cell RNA-seq expression data.
// Input: exprs_file.txt, signature_genes.txt, celltype.txt
// Container: quay.io/biocontainers/bioconductor-usort:1.36.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: gplots, uSORT
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load the package and locate the input expression file
//  * 2. [Core Analysis] Run the main uSORT function to perform pre-processing, preliminary gene selection, preliminary cell ordering, refined gene selecti
//  * 3. [Core Analysis] Extract and inspect the resulting list containing raw expression, trimmed log2 expression, preliminary/refined sorting genes, and 
//  * 4. [Visualization & Output] (Optional) Validate and visualize the preliminary and refined cell orderings using known signature genes and cell type annotations

nextflow.enable.dsl = 2

process BIOC_USORT_USORT_CELL_PROGRESSION {
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
    .bm_deps <- c("uSORT", "gplots")
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
        library(uSORT)
        library(gplots)
        
        # Define input file paths (exactly as specified by the user)
        exprs_file <- "exprs_file.txt"
        sig_genes_file <- "signature_genes.txt"
        celltype_file <- "celltype.txt"
        
        # Validate mandatory input file existence
        if (!file.exists(exprs_file)) {
          stop(paste("Error: Mandatory input file", exprs_file, "does not exist in the working directory."))
        }
        
        # Define project parameters
        project_name <- "uSORT_example"
        
        # Run the main uSORT workflow
        uSORT_results <- uSORT(exprs_file = exprs_file, 
                               log_transform = TRUE,
                               remove_outliers = TRUE,
                               project_name = project_name,
                               preliminary_sorting_method = "autoSPIN", 
                               refine_sorting_method = "sWanderlust",
                               result_directory = getwd(),
                               save_results = TRUE,
                               reproduce_seed = 1234)
        
        # Save the complete results object
        saveRDS(uSORT_results, file = paste0(project_name, "_results.rds"))
        
        # Save sorting orders and genes to CSV files
        write.csv(data.frame(CellID = uSORT_results\$preliminary_sorting_order), 
                  file = paste0(project_name, "_preliminary_sorting_order.csv"), 
                  row.names = FALSE)
        
        write.csv(data.frame(CellID = uSORT_results\$refined_sorting_order), 
                  file = paste0(project_name, "_refined_sorting_order.csv"), 
                  row.names = FALSE)
        
        write.csv(data.frame(Gene = uSORT_results\$refined_sorting_genes), 
                  file = paste0(project_name, "_refined_sorting_genes.csv"), 
                  row.names = FALSE)
        
        # Optional validation and visualization using signature genes and cell type annotations
        if (file.exists(sig_genes_file) && file.exists(celltype_file)) {
          
          # Read validation files
          sig_genes <- read.table(sig_genes_file)
          sig_genes <- as.character(sig_genes[,1])
          spl_annotat <- read.table(celltype_file, header=TRUE)
          
          # Dynamically detect column names (assuming 1st is Cell ID, 2nd is Cell Type)
          id_col <- colnames(spl_annotat)[1]
          group_col <- colnames(spl_annotat)[2]
          
          # Dynamically determine cell types and colors
          celltype <- unique(as.character(spl_annotat[[group_col]]))
          celltype <- celltype[!is.na(celltype)]
          celltype_color <- rainbow(length(celltype))
          
          # ---------------------------------------------------------------------------
          # Preliminary ordering heatmap with signature genes
          # ---------------------------------------------------------------------------
          pre_log2ex <- uSORT_results\$trimmed_log2exp[rev(uSORT_results\$preliminary_sorting_order), ]
          m <- spl_annotat[match(rownames(pre_log2ex), spl_annotat[[id_col]]), ]
          
          cell_color <- celltype_color[match(m[[group_col]], celltype)]
          cell_color[is.na(cell_color)] <- "grey" # Prevent heatmap.2 crash for unannotated cells
          
          sigGenes_log2ex <- t(pre_log2ex[ ,colnames(pre_log2ex) %in% sig_genes])
          fileNm <- paste0(project_name, '_signatureGenes_profiles_preliminary.pdf')
          
          pdf(fileNm, width = 10, height = 10)
          heatmap.2(as.matrix(sigGenes_log2ex),
                    dendrogram='row',
                    trace='none',
                    col = bluered,
                    Rowv=T,Colv=F,
                    scale = 'row',
                    cexRow=1.8,
                    ColSideColors=cell_color,
                    margins = c(8, 8))
          
          legend("topright",
                 legend=celltype,
                 col=celltype_color,
                 text.col=celltype_color,
                 pch=20,
                 horiz=T,
                 bty= "n",
                 inset=c(0,-0.01),
                 pt.cex=1.5)
          dev.off()
          
          # ---------------------------------------------------------------------------
          # Refined ordering heatmap with signature genes
          # ---------------------------------------------------------------------------
          ref_log2ex <- uSORT_results\$trimmed_log2exp[uSORT_results\$refined_sorting_order, ]
          m <- spl_annotat[match(rownames(ref_log2ex), spl_annotat[[id_col]]), ]
          
          cell_color <- celltype_color[match(m[[group_col]], celltype)]
          cell_color[is.na(cell_color)] <- "grey" # Prevent heatmap.2 crash for unannotated cells
          
          sigGenes_log2ex <- t(ref_log2ex[ ,colnames(ref_log2ex) %in% sig_genes])
          fileNm <- paste0(project_name, '_signatureGenes_profiles_refine.pdf')
          
          pdf(fileNm, width = 10, height = 10)
          heatmap.2(as.matrix(sigGenes_log2ex),
                    dendrogram='row',
                    trace='none',
                    col = bluered,
                    Rowv=T,Colv=F,
                    scale = 'row',
                    cexRow=1.8,
                    ColSideColors=cell_color,
                    margins = c(8, 8))
          
          legend("topright",
                 legend=celltype,
                 col=celltype_color,
                 text.col=celltype_color,
                 pch=20,
                 horiz=T,
                 bty= "n",
                 inset=c(0,-0.01),
                 pt.cex=1.5)
          dev.off()
          
        } else {
          message("Optional validation files (signature_genes.txt and/or celltype.txt) not found. Skipping validation heatmaps.")
        }

    writeLines(c(
        '"BIOC_USORT_USORT_CELL_PROGRESSION":',
        paste0('    uSORT: ', as.character(packageVersion('uSORT')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_usort_cell_progression.csv versions.yml
    """
}

workflow BIOC_USORT_USORT_CELL_PROGRESSION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ exprs_file.txt, signature_genes.txt, celltype.txt ] ]

    main:
    BIOC_USORT_USORT_CELL_PROGRESSION(ch_input)

    emit:
    tables   = BIOC_USORT_USORT_CELL_PROGRESSION.out.tables
    plots    = BIOC_USORT_USORT_CELL_PROGRESSION.out.plots
    objects  = BIOC_USORT_USORT_CELL_PROGRESSION.out.objects
    versions = BIOC_USORT_USORT_CELL_PROGRESSION.out.versions
}
