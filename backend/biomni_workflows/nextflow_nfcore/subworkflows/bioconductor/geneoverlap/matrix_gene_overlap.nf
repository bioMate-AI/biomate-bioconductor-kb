#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GeneOverlap — matrix_gene_overlap
// Compare multiple gene lists from two different gene sets in a pairwise matrix fashion, visualize the results as a heatmap, and extract specific comparison matri
// Input: set1.rds, set2.rds, background_size
// Container: quay.io/biocontainers/bioconductor-geneoverlap:1.46.0--r45hdfd78af_0
// Requires: GeneOverlap
// Visualizations: heatmap
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Create a GeneOverlapMatrix object using newGOM
//  * 2. [Visualization & Output] Visualize the pairwise overlaps using drawHeatmap
//  * 3. [Core Analysis] Extract matrices of p-values or odds ratios using getMatrix
//  * 4. [Core Analysis] Retrieve overlapping gene lists for all comparisons using getNestedList
//  * 5. [Core Analysis] Access individual pairwise GeneOverlap objects using matrix-like indexing

nextflow.enable.dsl = 2

process BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-general:3.20"

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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
        
        # Load library
        library(GeneOverlap)
        
        # Read inputs
        hESC.ChIPSeq.list <- readRDS("set1.rds")
        hESC.RNASeq.list <- readRDS("set2.rds")
        
        # Read background size
        if (file.exists("background_size")) {
          gs.RNASeq <- tryCatch({
            readRDS("background_size")
          }, error = function(e) {
            as.integer(readLines("background_size", warn=FALSE)[1])
          })
        } else if (file.exists("background_size.rds")) {
          gs.RNASeq <- readRDS("background_size.rds")
        } else {
          stop("background_size file not found!")
        }
        
        # Ensure names match the documented code's indexing requirements
        if (is.null(names(hESC.ChIPSeq.list)) || length(names(hESC.ChIPSeq.list)) == 0) {
          names(hESC.ChIPSeq.list) <- paste0("Set1_List", seq_along(hESC.ChIPSeq.list))
        }
        
        if (is.null(names(hESC.RNASeq.list)) || length(names(hESC.RNASeq.list)) == 0) {
          names(hESC.RNASeq.list) <- paste0("Set2_List", seq_along(hESC.RNASeq.list))
        }
        
        # 1. Create a GeneOverlapMatrix object using newGOM
        gom.obj <- newGOM(hESC.ChIPSeq.list, hESC.RNASeq.list, 
                          gs.RNASeq)
        
        # 2. Visualize the pairwise overlaps using drawHeatmap
        pdf("heatmap.pdf", width = 8, height = 8)
        drawHeatmap(gom.obj)
        dev.off()
        
        # 3. Extract matrices of p-values or odds ratios using getMatrix
        pval_matrix <- getMatrix(gom.obj, name="pval")
        write.csv(pval_matrix, "pval_matrix.csv", row.names = TRUE)
        
        odds_matrix <- getMatrix(gom.obj, "odds.ratio")
        write.csv(odds_matrix, "odds_ratio_matrix.csv", row.names = TRUE)
        
        # 4. Retrieve overlapping gene lists for all comparisons using getNestedList
        inter.nl <- getNestedList(gom.obj, name="intersection")
        saveRDS(inter.nl, "intersections.rds")
        
        # 5. Access individual pairwise GeneOverlap objects using matrix-like indexing
        go.k4.high <- gom.obj[1, 1]
        saveRDS(go.k4.high, "go_k4_high.rds")
        
        # Run the exact documented indexing line
        indexed_obj <- gom.obj[names(hESC.ChIPSeq.list)[1], names(hESC.RNASeq.list)[1]]
        print(indexed_obj)

    writeLines(c(
        '"BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP":',
        paste0('    GeneOverlap: ', as.character(packageVersion('GeneOverlap')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_matrix_gene_overlap.csv versions.yml
    """
}

workflow BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ set1.rds, set2.rds, background_size ] ]

    main:
    BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP(ch_input)

    emit:
    tables   = BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP.out.tables
    plots    = BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP.out.plots
    objects  = BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP.out.objects
    versions = BIOC_GENEOVERLAP_MATRIX_GENE_OVERLAP.out.versions
}
