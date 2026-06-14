#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathview — gene_data_visualization
// Visualize a single sample of gene expression data on a signaling pathway using both native KEGG and Graphviz layouts.
// Input: gene_expression.tsv
// Container: quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
// R packages: gage, pathview
// Bioconductor: 3.20 | R: 4.4
// Requires: pathview
// Visualizations: pathway diagram
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and data
//  * 2. [Visualization & Output] Render native KEGG view with default settings
//  * 3. [Visualization & Output] Render native KEGG view with two layers (same.layer = FALSE)
//  * 4. [Visualization & Output] Render Graphviz view with default settings
//  * 5. [Visualization & Output] Render Graphviz view with two layers
//  * 6. [Visualization & Output] Render Graphviz view with split node groups
//  * 7. [Visualization & Output] Render Graphviz view with expanded multiple-gene nodes

nextflow.enable.dsl = 2

process BIOC_PATHVIEW_GENE_DATA_VISUALIZATION {
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
    .bm_deps <- c("gage", "pathview")
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
    
    library(pathview)
    
    # 1. Load package and data
    gene_df <- read.delim("gene_expression.tsv", row.names = 1, check.names = FALSE)
    gse16873.d <- as.matrix(gene_df)
    
    demo.paths <- list(
      sel.paths = c("04110"),
      spos = c("bottomleft")
    )
    i <- 1
    
    # 2. Render native KEGG view with default settings
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873", kegg.native = T)
    saveRDS(pv.out, "pv_out_native_default.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_native_default.csv", row.names = FALSE)
    }
    
    # 3. Render native KEGG view with two layers (same.layer = FALSE)
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873.2layer", kegg.native = T,
                       same.layer = F)
    saveRDS(pv.out, "pv_out_native_2layer.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_native_2layer.csv", row.names = FALSE)
    }
    
    # 4. Render Graphviz view with default settings
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i],
                       species = "hsa", out.suffix = "gse16873", kegg.native = F,
                       sign.pos = demo.paths\$spos[i])
    saveRDS(pv.out, "pv_out_graphviz_default.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_graphviz_default.csv", row.names = FALSE)
    }
    
    # 5. Render Graphviz view with two layers
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i], 
        species = "hsa", out.suffix = "gse16873.2layer", kegg.native = F, 
        sign.pos = demo.paths\$spos[i], same.layer = F)
    saveRDS(pv.out, "pv_out_graphviz_2layer.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_graphviz_2layer.csv", row.names = FALSE)
    }
    
    # 6. Render Graphviz view with split node groups
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i], 
        species = "hsa", out.suffix = "gse16873.split", kegg.native = F, 
        sign.pos = demo.paths\$spos[i], split.group = T)
    saveRDS(pv.out, "pv_out_graphviz_split.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_graphviz_split.csv", row.names = FALSE)
    }
    
    # 7. Render Graphviz view with expanded multiple-gene nodes
    pv.out <- pathview(gene.data = gse16873.d[, 1], pathway.id = demo.paths\$sel.paths[i], 
        species = "hsa", out.suffix = "gse16873.split.expanded", kegg.native = F,
        sign.pos = demo.paths\$spos[i], split.group = T, expand.node = T)
    saveRDS(pv.out, "pv_out_graphviz_expanded.rds")
    if (!is.null(pv.out\$plot.data.gene)) {
      write.csv(pv.out\$plot.data.gene, "plot_data_gene_graphviz_expanded.csv", row.names = FALSE)
    }

    writeLines(c(
        '"BIOC_PATHVIEW_GENE_DATA_VISUALIZATION":',
        paste0('    pathview: ', as.character(packageVersion('pathview')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gene_data_visualization.csv versions.yml
    """
}

workflow BIOC_PATHVIEW_GENE_DATA_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ gene_expression.tsv ] ]

    main:
    BIOC_PATHVIEW_GENE_DATA_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PATHVIEW_GENE_DATA_VISUALIZATION.out.tables
    plots    = BIOC_PATHVIEW_GENE_DATA_VISUALIZATION.out.plots
    objects  = BIOC_PATHVIEW_GENE_DATA_VISUALIZATION.out.objects
    versions = BIOC_PATHVIEW_GENE_DATA_VISUALIZATION.out.versions
}
