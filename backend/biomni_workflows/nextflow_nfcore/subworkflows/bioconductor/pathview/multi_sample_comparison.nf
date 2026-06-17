#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: pathview — multi_sample_comparison
// Compare multiple samples or experimental states side-by-side on a single pathway graph by slicing nodes.
// Input: multi_sample_gene_expression.tsv, multi_sample_metabolite_abundance.tsv
// Container: quay.io/biocontainers/bioconductor-pathview:1.50.0--r45hdfd78af_0
// R packages: pathview
// Bioconductor: 3.20 | R: 4.4
// Requires: pathview
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load package and multi-sample data
//  * 2. [Visualization & Output] Render native KEGG view without sample matching
//  * 3. [Visualization & Output] Render native KEGG view with sample matching
//  * 4. [Visualization & Output] Render Graphviz view with multi-sample data

nextflow.enable.dsl = 2

process BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON {
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
    .bm_deps <- c("pathview")
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
        
        # 1. Load package and multi-sample data
        library(pathview)
        
        # Read user-provided multi-sample gene expression data
        # Expected format: TSV with Entrez gene IDs as row names and at least 3 sample columns
        gse16873.d <- as.matrix(read.delim(
          "multi_sample_gene_expression.tsv", 
          row.names = 1, 
          sep = "\t", 
          check.names = FALSE
        ))
        
        # Read user-provided multi-sample metabolite abundance data
        # Expected format: TSV with KEGG compound IDs as row names and at least 2 sample columns
        sim.cpd.data2 <- as.matrix(read.delim(
          "multi_sample_metabolite_abundance.tsv", 
          row.names = 1, 
          sep = "\t", 
          check.names = FALSE
        ))
        
        # 2. Render native KEGG view without sample matching
        pv.out <- pathview(gene.data = gse16873.d, 
            cpd.data = sim.cpd.data2, pathway.id = "00640", 
            species = "hsa", out.suffix = "gse16873.cpd.3-2s", keys.align = "y", 
            kegg.native = T, match.data = F, multi.state = T, same.layer = T)
        
        # Save intermediate results
        saveRDS(pv.out, "pv_out_native_no_match.rds")
        if (!is.null(pv.out\$plot.data.gene)) {
          write.csv(pv.out\$plot.data.gene, "mapped_genes_native_no_match.csv", row.names = FALSE)
        }
        if (!is.null(pv.out\$plot.data.cpd)) {
          write.csv(pv.out\$plot.data.cpd, "mapped_compounds_native_no_match.csv", row.names = FALSE)
        }
        
        # 3. Render native KEGG view with sample matching
        pv.out <- pathview(gene.data = gse16873.d, 
            cpd.data = sim.cpd.data2, pathway.id = "00640", 
            species = "hsa", out.suffix = "gse16873.cpd.3-2s.match", 
            keys.align = "y", kegg.native = T, match.data = T, multi.state = T, 
            same.layer = T)
        
        # Save intermediate results
        saveRDS(pv.out, "pv_out_native_match.rds")
        if (!is.null(pv.out\$plot.data.gene)) {
          write.csv(pv.out\$plot.data.gene, "mapped_genes_native_match.csv", row.names = FALSE)
        }
        if (!is.null(pv.out\$plot.data.cpd)) {
          write.csv(pv.out\$plot.data.cpd, "mapped_compounds_native_match.csv", row.names = FALSE)
        }
        
        # 4. Render Graphviz view with multi-sample data
        pv.out <- pathview(gene.data = gse16873.d, 
            cpd.data = sim.cpd.data2, pathway.id = "00640", 
            species = "hsa", out.suffix = "gse16873.cpd.3-2s", keys.align = "y", 
            kegg.native = F, match.data = F, multi.state = T, same.layer = T,
            key.pos = "topleft", sign.pos = "bottomright")
        
        # Save final results
        saveRDS(pv.out, "pv_out_graphviz.rds")
        if (!is.null(pv.out\$plot.data.gene)) {
          write.csv(pv.out\$plot.data.gene, "mapped_genes_graphviz.csv", row.names = FALSE)
        }
        if (!is.null(pv.out\$plot.data.cpd)) {
          write.csv(pv.out\$plot.data.cpd, "mapped_compounds_graphviz.csv", row.names = FALSE)
        }

    writeLines(c(
        '"BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON":',
        paste0('    pathview: ', as.character(packageVersion('pathview')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multi_sample_comparison.csv versions.yml
    """
}

workflow BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ multi_sample_gene_expression.tsv, multi_sample_metabolite_abundance.tsv ] ]

    main:
    BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON.out.tables
    plots    = BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON.out.plots
    objects  = BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON.out.objects
    versions = BIOC_PATHVIEW_MULTI_SAMPLE_COMPARISON.out.versions
}
