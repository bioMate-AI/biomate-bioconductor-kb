#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathview — discrete_data_visualization
// Visualize discrete lists of significant genes and compounds on a pathway graph.
// Input: significant_genes.txt, significant_compounds.txt
// Container: quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
// Requires: org.Hs.eg.db, pathview
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and identify significant genes/compounds
//  * 2. [Visualization & Output] Render native KEGG view with discrete color mapping for both genes and compounds
//  * 3. [Visualization & Output] Render native KEGG view with discrete mapping for genes and continuous mapping for compounds

nextflow.enable.dsl = 2

process BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION {
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
        for (.bm_f in list.files(".", recursive = TRUE, full.names = TRUE)) {
          .bm_bn <- basename(.bm_f)
          if (!file.exists(.bm_bn)) try(file.copy(.bm_f, .bm_bn), silent = TRUE)
        }
    
    # 1. Load package and identify significant genes/compounds
    library(pathview)
    require(org.Hs.eg.db)
    
    # Read user input files from the working directory
    if (!file.exists("significant_genes.txt")) {
      stop("Error: significant_genes.txt not found in the working directory.")
    }
    if (!file.exists("significant_compounds.txt")) {
      stop("Error: significant_compounds.txt not found in the working directory.")
    }
    
    sel.genes <- readLines("significant_genes.txt")
    sel.genes <- trimws(sel.genes)
    sel.genes <- sel.genes[sel.genes != ""]
    
    sel.cpds <- readLines("significant_compounds.txt")
    sel.cpds <- trimws(sel.cpds)
    sel.cpds <- sel.cpds[sel.cpds != ""]
    
    # Create a continuous representation of the compounds for the second visualization
    # (assigning a constant value of 1.0 to represent presence/significance)
    cpd.data.continuous <- rep(1.0, length(sel.cpds))
    names(cpd.data.continuous) <- sel.cpds
    
    # Define pathway ID and key position (replacing demo.paths)
    pathway_id <- "00640"
    key_pos <- "topright"
    
    # 2. Render native KEGG view with discrete color mapping for both genes and compounds
    pv.out1 <- pathview(gene.data = sel.genes, cpd.data = sel.cpds, 
        pathway.id = pathway_id, species = "hsa", out.suffix = "sel.genes.sel.cpd", 
        keys.align = "y", kegg.native = T, key.pos = key_pos, 
        limit = list(gene = 5, cpd = 2), bins = list(gene = 5, cpd = 2), 
        na.col = "gray", discrete = list(gene = T, cpd = T))
    
    # 3. Render native KEGG view with discrete mapping for genes and continuous mapping for compounds
    pv.out2 <- pathview(gene.data = sel.genes, cpd.data = cpd.data.continuous, 
        pathway.id = pathway_id, species = "hsa", out.suffix = "sel.genes.cpd",
        keys.align = "y", kegg.native = T, key.pos = key_pos, 
        limit = list(gene = 5, cpd = 1), bins = list(gene = 5, cpd = 10), 
        na.col = "gray", discrete = list(gene = T, cpd = F))
    
    # Save outputs to disk
    if (!is.null(pv.out1\$plot.data.gene)) {
      write.csv(pv.out1\$plot.data.gene, "pv_out1_gene_data.csv", row.names = FALSE)
    }
    if (!is.null(pv.out1\$plot.data.cpd)) {
      write.csv(pv.out1\$plot.data.cpd, "pv_out1_cpd_data.csv", row.names = FALSE)
    }
    saveRDS(pv.out1, "pv_out1.rds")
    
    if (!is.null(pv.out2\$plot.data.gene)) {
      write.csv(pv.out2\$plot.data.gene, "pv_out2_gene_data.csv", row.names = FALSE)
    }
    if (!is.null(pv.out2\$plot.data.cpd)) {
      write.csv(pv.out2\$plot.data.cpd, "pv_out2_cpd_data.csv", row.names = FALSE)
    }
    saveRDS(pv.out2, "pv_out2.rds")

    writeLines(c(
        '"BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION":',
        paste0('    pathview: ', as.character(packageVersion('pathview')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_discrete_data_visualization.csv versions.yml
    """
}

workflow BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ significant_genes.txt, significant_compounds.txt ] ]

    main:
    BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION.out.tables
    plots    = BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION.out.plots
    objects  = BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION.out.objects
    versions = BIOC_PATHVIEW_DISCRETE_DATA_VISUALIZATION.out.versions
}
