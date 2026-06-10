#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mCSEA — dmr_identification_and_visualization
// Rank CpG probes, identify differentially methylated regions (DMRs) using GSEA, and visualize the genomic context and enrichment curves of top candidates.
// Input: beta_values.matrix, phenotype_data.csv
// Container: quay.io/biocontainers/bioconductor-mcsea:1.30.1--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: mCSEA
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Rank CpG probes using rankProbes()
//  * 2. [Core Analysis] Run GSEA-based DMR detection using mCSEATest()
//  * 3. [Visualization & Output] Plot the genomic context of a specific DMR using mCSEAPlot()
//  * 4. [Visualization & Output] Plot the GSEA enrichment score curve for a specific DMR using mCSEAPlotGSEA()

nextflow.enable.dsl = 2

process BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION {
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
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
            
            # Load required libraries
            library(mCSEA)
            
            # -----------------------------------------------------------------------------
            # Stage 0: Read User Input Files
            # -----------------------------------------------------------------------------
            
            # Read the beta-values or M-values matrix
            # Expects CpG probes as rows and samples as columns
            betaTest <- as.matrix(read.table("beta_values.matrix", header = TRUE, row.names = 1, check.names = FALSE))
            
            # Read the phenotype data
            # Expects sample phenotypes containing explanatory variables and covariates
            phenoTest <- read.csv("phenotype_data.csv", row.names = 1, check.names = FALSE)
            
            # Align samples between beta matrix and phenotype data
            common_samples <- intersect(colnames(betaTest), rownames(phenoTest))
            if (length(common_samples) == 0) {
              stop("Error: No matching sample names found between beta_values.matrix and phenotype_data.csv")
            }
            betaTest <- betaTest[, common_samples, drop = FALSE]
            phenoTest <- phenoTest[common_samples, , drop = FALSE]
            
            # -----------------------------------------------------------------------------
            # Stage 1: Rank CpG probes using rankProbes()
            # -----------------------------------------------------------------------------
            ref_group <- as.character(unique(phenoTest[, 1])[1])
            myRank <- rankProbes(betaTest, phenoTest, refGroup = ref_group)
            
            # Save ranked probes
            saveRDS(myRank, "ranked_probes.rds")
            write.csv(as.data.frame(myRank), "ranked_probes.csv", row.names = TRUE)
            
            # -----------------------------------------------------------------------------
            # Stage 2: Run GSEA-based DMR detection using mCSEATest()
            # -----------------------------------------------------------------------------
            platform_type <- ifelse(nrow(betaTest) > 490000, "EPIC", "450k")
            myResults <- mCSEATest(myRank, betaTest, phenoTest, 
                                    regionsTypes = "promoters", platform = platform_type)
            
            # Save full results object
            saveRDS(myResults, "mCSEA_results.rds")
            
            # Save promoters data frame
            if ("promoters" %in% names(myResults)) {
              write.csv(myResults[["promoters"]], "promoters_results.csv", row.names = TRUE)
            }
            
            # -----------------------------------------------------------------------------
            # Stage 3: Plot the genomic context of a specific DMR using mCSEAPlot()
            # -----------------------------------------------------------------------------
            top_dmr <- rownames(myResults[["promoters"]])[1]
            
            if (!is.na(top_dmr)) {
              tryCatch({
                pdf(paste0("mCSEAPlot_", top_dmr, ".pdf"), width = 10, height = 8)
                mCSEAPlot(myResults, regionType = "promoters", 
                           dmrName = top_dmr,
                           transcriptAnnotation = "symbol", makePDF = FALSE)
                dev.off()
              }, error = function(e) {
                message("Could not generate mCSEAPlot for ", top_dmr, ": ", e\$message)
                if (dev.cur() > 1) dev.off()
              })
            } else {
              message("No significant DMRs found, skipping mCSEAPlot.")
            }
            
            # -----------------------------------------------------------------------------
            # Stage 4: Plot the GSEA enrichment score curve using mCSEAPlotGSEA()
            # -----------------------------------------------------------------------------
            if (!is.na(top_dmr)) {
              tryCatch({
                pdf(paste0("mCSEAPlotGSEA_", top_dmr, ".pdf"), width = 7, height = 5)
                print(mCSEAPlotGSEA(myRank, myResults, regionType = "promoters", dmrName = top_dmr))
                dev.off()
              }, error = function(e) {
                message("Could not generate mCSEAPlotGSEA for ", top_dmr, ": ", e\$message)
                if (dev.cur() > 1) dev.off()
              })
            } else {
              message("No significant DMRs found, skipping mCSEAPlotGSEA.")
            }

    writeLines(c(
        '"BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION":',
        paste0('    mCSEA: ', as.character(packageVersion('mCSEA')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_dmr_identification_and_visualization.csv versions.yml
    """
}

workflow BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ beta_values.matrix, phenotype_data.csv ] ]

    main:
    BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION(ch_input)

    emit:
    tables   = BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION.out.tables
    plots    = BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION.out.plots
    objects  = BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION.out.objects
    versions = BIOC_MCSEA_DMR_IDENTIFICATION_AND_VISUALIZATION.out.versions
}
