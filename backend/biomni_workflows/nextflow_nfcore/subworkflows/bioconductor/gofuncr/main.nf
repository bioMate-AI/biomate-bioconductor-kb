#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: GOfuncR — hypergeometric_test
// Test for gene set enrichment using the hypergeometric test with options for custom background, gene length correction, or genomic regions.
// Input: candidate_genes.tsv, genomic_regions.tsv
// Container: quay.io/biocontainers/bioconductor-gofuncr:1.30.0--r45ha27e39d_0
// R packages: GOfuncR
// Bioconductor: 3.20 | R: 4.4
// Requires: GOfuncR
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Define candidate (and optionally background) genes or genomic regions
//  * 2. [Core Analysis] Run enrichment analysis using go_enrich with test='hyper'
//  * 3. [Visualization & Output] Extract results and plot distribution of gene-associated variables using plot_anno_scores

nextflow.enable.dsl = 2

process BIOC_GOFUNCR_HYPERGEOMETRIC_TEST {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-genomics:3.20"

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
    .bm_deps <- c("GOfuncR")
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
        
        # Load GOfuncR package
        library(GOfuncR)
        
        # 1. Read user input files from the working directory
        # candidate_genes.tsv: columns gene_ids, is_candidate
        cand_df = read.delim("candidate_genes.tsv", stringsAsFactors=FALSE, header=TRUE)
        
        # genomic_regions.tsv: columns regions, is_candidate
        regions_df = read.delim("genomic_regions.tsv", stringsAsFactors=FALSE, header=TRUE)
        
        # 2. Prepare input dataframes
        # For default background, we only use candidate genes (is_candidate = 1)
        input_hyper = cand_df[cand_df[, 2] == 1, , drop=FALSE]
        colnames(input_hyper) = c("gene_ids", "is_candidate")
        
        # For defined background, we use both candidate and background genes
        input_hyper_bg = cand_df
        colnames(input_hyper_bg) = c("gene_ids", "is_candidate")
        
        # For genomic regions
        input_regions = regions_df
        colnames(input_regions) = c("regions", "is_candidate")
        
        # 3. Run enrichment analyses
        # Hypergeometric test using default background
        res_hyper = go_enrich(input_hyper, n_randset=100)
        stats = res_hyper[[1]]
        head(stats)
        by(stats, stats\$ontology, head, n=3)
        head(res_hyper[[2]])
        res_hyper[[3]]
        head(res_hyper[[4]])
        
        # Hypergeometric test using defined background
        res_hyper_bg = go_enrich(input_hyper_bg, n_randsets=100)
        head(res_hyper_bg[[1]])
        
        # Hypergeometric test with correction for gene length
        res_hyper_len = go_enrich(input_hyper, gene_len=TRUE)
        
        # Hypergeometric test with genomic regions as input
        res_region = go_enrich(input_regions, n_randsets=100, regions=TRUE)
        stats_region = res_region[[1]]
        head(stats_region)
        input_genes = res_region[[2]]
        candidate_genes = input_genes[input_genes[,2]==1, 1]
        candidate_genes
        
        # 4. Plotting and saving results
        # Plot distribution of gene-associated variables
        tryCatch({
            pdf("hyper_plots.pdf", width=10, height=7)
            top_gos_hyper = head(res_hyper[[1]]\$node_id, 5)
            if (length(top_gos_hyper) > 0) {
                plot_anno_scores(res_hyper, top_gos_hyper)
            }
            dev.off()
        }, error = function(e) {
            warning("Could not generate hyper_plots.pdf: ", e\$message)
            if (dev.cur() > 1) dev.off()
        })
        
        tryCatch({
            pdf("hyper_bg_plots.pdf", width=10, height=7)
            top_gos_hyper_bg = head(res_hyper_bg[[1]]\$node_id, 5)
            if (length(top_gos_hyper_bg) > 0) {
                plot_stats = plot_anno_scores(res_hyper_bg, top_gos_hyper_bg)
                write.csv(plot_stats, "plot_stats.csv", row.names=FALSE)
            }
            dev.off()
        }, error = function(e) {
            warning("Could not generate hyper_bg_plots.pdf: ", e\$message)
            if (dev.cur() > 1) dev.off()
        })
        
        # Write output tables
        write.csv(stats, "stats_hyper.csv", row.names=FALSE)
        write.csv(res_hyper_bg[[1]], "stats_hyper_bg.csv", row.names=FALSE)
        write.csv(stats_region, "stats_region.csv", row.names=FALSE)
        
        # Save RDS objects
        saveRDS(res_hyper, "res_hyper.rds")
        saveRDS(res_hyper_bg, "res_hyper_bg.rds")
        saveRDS(res_hyper_len, "res_hyper_len.rds")
        saveRDS(res_region, "res_region.rds")

    writeLines(c(
        '"BIOC_GOFUNCR_HYPERGEOMETRIC_TEST":',
        paste0('    GOfuncR: ', as.character(packageVersion('GOfuncR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hypergeometric_test.csv versions.yml
    """
}

workflow BIOC_GOFUNCR_HYPERGEOMETRIC_TEST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ candidate_genes.tsv, genomic_regions.tsv ] ]

    main:
    BIOC_GOFUNCR_HYPERGEOMETRIC_TEST(ch_input)

    emit:
    tables   = BIOC_GOFUNCR_HYPERGEOMETRIC_TEST.out.tables
    plots    = BIOC_GOFUNCR_HYPERGEOMETRIC_TEST.out.plots
    objects  = BIOC_GOFUNCR_HYPERGEOMETRIC_TEST.out.objects
    versions = BIOC_GOFUNCR_HYPERGEOMETRIC_TEST.out.versions
}
