#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: FRASER — aberrant_splicing_from_counts
// Detect rare aberrant splicing events starting from precalculated junction and splice site count matrices.
// Input: sampleTable_countTable.tsv, raw_junction_counts.tsv.gz, raw_site_counts.tsv.gz
// Container: quay.io/biocontainers/bioconductor-fraser:2.6.0--r45ha27e39d_0
// R packages: BiocParallel, FRASER, TxDb.Hsapiens.UCSC.hg19.knownGene, data.table, org.Hs.eg.db
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, FRASER, TxDb.Hsapiens.UCSC.hg19.knownGene, data.table, org.Hs.eg.db
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load sample annotation and count matrices from the
//  * 2. [Input & Preparation] Create a FraserDataSet object directly from the count
//  * 3. [Input & Preparation] Calculate PSI and Jaccard values
//  * 4. [Input & Preparation] Filter junctions
//  * 5. [Input & Preparation] Optimize the latent space dimension q
//  * 6. [Input & Preparation] Fit the splicing model
//  * 7. [Input & Preparation] Calculate p-values and adjusted p-values
//  * 8. [Input & Preparation] Annotate ranges and extract results

nextflow.enable.dsl = 2

process BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS {
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
    .bm_deps <- c("BiocParallel", "FRASER", "TxDb.Hsapiens.UCSC.hg19.knownGene", "data.table", "org.Hs.eg.db")
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
                library(FRASER)
                library(data.table)
                library(BiocParallel)
                library(TxDb.Hsapiens.UCSC.hg19.knownGene)
                library(org.Hs.eg.db)
                
                # Set parallel backend to serial for reproducibility and stability
                register(SerialParam())
                
                # --- Load sample annotation and count matrices from the ---
                sampleTable <- fread("sampleTable_countTable.tsv")
                head(sampleTable)
                
                junctionCts <- fread("raw_junction_counts.tsv.gz")
                head(junctionCts)
                
                spliceSiteCts <- fread("raw_site_counts.tsv.gz")
                head(spliceSiteCts)
                
                # --- Create a FraserDataSet object directly from the count ---
                fds <- FraserDataSet(colData=sampleTable, junctions=junctionCts,
                        spliceSites=spliceSiteCts, workingDir="FRASER_output")
                fds
                
                # --- Calculate PSI and Jaccard values ---
                fds <- calculatePSIValues(fds)
                
                # --- Filter junctions ---
                fds <- filterExpressionAndVariability(fds, minDeltaPsi=0, filter=TRUE)
                
                # Set up PDF to capture diagnostic plots
                pdf("FRASER_diagnostic_plots.pdf", width=7, height=7)
                
                set.seed(42)
                # --- Optimize the latent space dimension q ---
                # Optimal Hard Thresholding (default method)
                fds <- estimateBestQ(fds, type="jaccard", plot=FALSE)
                print(plotEncDimSearch(fds, type="jaccard", plotType="sv"))
                
                # Retrieve the estimated optimal dimension of the latent space
                optimal_q <- bestQ(fds, type="jaccard")
                message("Estimated optimal Q: ", optimal_q)
                
                # --- Fit the splicing model ---
                # Using an alternative way to correct splicing ratios
                # the default is 15 iterations
                fds <- fit(fds, q=optimal_q, type="jaccard", implementation="PCA-BB-Decoder", 
                            iterations=15)
                
                # --- Calculate p-values and adjusted p-values ---
                fds <- calculatePvalues(fds, type="jaccard")
                head(pVals(fds, type="jaccard"))
                
                fds <- calculatePadjValues(fds, type="jaccard", method="BY")
                head(padjVals(fds,type="jaccard"))
                
                # --- Annotate ranges and extract results ---
                txdb <- TxDb.Hsapiens.UCSC.hg19.knownGene
                orgDb <- org.Hs.eg.db
                fds <- annotateRangesWithTxDb(fds, txdb=txdb, orgDb=orgDb)
                
                res <- results(fds, all=TRUE)
                res
                
                # Close the PDF device
                dev.off()
                
                # Save meaningful outputs to the working directory
                write.csv(as.data.frame(res), "fraser_results.csv", row.names=FALSE)
                saveRDS(fds, "fds_object.rds")
                
                message("FRASER pipeline completed successfully. Outputs saved to 'fraser_results.csv', 'fds_object.rds', and 'FRASER_diagnostic_plots.pdf'.")

    writeLines(c(
        '"BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS":',
        paste0('    FRASER: ', as.character(packageVersion('FRASER')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_aberrant_splicing_from_counts.csv versions.yml
    """
}

workflow BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ sampleTable_countTable.tsv, raw_junction_counts.tsv.gz, raw_site_counts.tsv.gz ] ]

    main:
    BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS(ch_input)

    emit:
    tables   = BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS.out.tables
    plots    = BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS.out.plots
    objects  = BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS.out.objects
    versions = BIOC_FRASER_ABERRANT_SPLICING_FROM_COUNTS.out.versions
}
