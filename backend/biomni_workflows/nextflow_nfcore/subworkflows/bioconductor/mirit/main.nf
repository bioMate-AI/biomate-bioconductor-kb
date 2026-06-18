#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: MIRit — paired_integration_workflow
// Perform differential expression, functional enrichment, target retrieval, and correlation-based integration for paired miRNA and gene expression data.
// Input: geneCounts, mirnaCounts, meta
// Container: quay.io/biocontainers/r-base:4.3.1
// R packages: ggpubr, MIRit
// Bioconductor: 3.20 | R: 4.4
// Requires: MIRit, ggpubr
// Visualizations: volcano plot, correlation plot, MDS plot, bar plot, dot plot, enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load expression matrices and prepare metadata
//  * 2. [Input & Preparation] Create a MirnaExperiment object
//  * 3. [Visualization & Output] Visualize expression variability using MDS plots
//  * 4. [Core Analysis] Perform differential expression for genes and miRNAs
//  * 5. [Visualization & Output] Access and visualize differential expression results
//  * 6. [Core Analysis] Perform functional enrichment analysis (ORA and GSEA)
//  * 7. [Core Analysis] Retrieve predicted and validated miRNA targets
//  * 8. [Core Analysis] Perform correlation-based integration
//  * 9. [Visualization & Output] Extract and visualize integrated miRNA-target pairs

nextflow.enable.dsl = 2

process BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW {
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
    .bm_deps <- c("ggpubr", "MIRit")
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
        library(MIRit)
        library(ggpubr)
        
        # Helper function to read user input files robustly (supporting RDS, CSV, TSV, TXT)
        read_input <- function(base_name) {
          rds_path <- paste0(base_name, ".rds")
          csv_path <- paste0(base_name, ".csv")
          tsv_path <- paste0(base_name, ".tsv")
          txt_path <- paste0(base_name, ".txt")
        
          if (file.exists(rds_path)) {
            return(readRDS(rds_path))
          } else if (file.exists(csv_path)) {
            if (base_name == "meta") {
              return(read.csv(csv_path, check.names = FALSE))
            }
            return(as.matrix(read.csv(csv_path, row.names = 1, check.names = FALSE)))
          } else if (file.exists(tsv_path)) {
            if (base_name == "meta") {
              return(read.delim(tsv_path, check.names = FALSE))
            }
            return(as.matrix(read.delim(tsv_path, row.names = 1, check.names = FALSE)))
          } else if (file.exists(txt_path)) {
            if (base_name == "meta") {
              return(read.table(txt_path, header = TRUE, check.names = FALSE))
            }
            return(as.matrix(read.table(txt_path, header = TRUE, row.names = 1, check.names = FALSE)))
          } else {
            stop(paste("Required input file not found for:", base_name))
          }
        }
        
        # 1. Load expression matrices and prepare metadata
        geneCounts <- read_input("geneCounts")
        mirnaCounts <- read_input("mirnaCounts")
        meta <- read_input("meta")
        
        # Align metadata columns to match the documented code's expectations
        if ("condition" %in% colnames(meta) && !"disease" %in% colnames(meta)) {
          meta\$disease <- meta\$condition
        }
        
        # Dynamically determine the contrast from the actual condition levels
        unique_diseases <- unique(meta\$disease)
        if (length(unique_diseases) < 2) {
          stop("At least two conditions are required in the metadata.")
        }
        contrast_str <- paste0(unique_diseases[1], "-", unique_diseases[2])
        
        # Ensure patient column exists for the paired design formula (~ disease + patient)
        if (!"patient" %in% colnames(meta)) {
          n_samples <- nrow(meta)
          meta\$patient <- paste0("Sample_", rep(seq_len(n_samples / 2), length.out = n_samples))
        }
        
        # 2. Create a MirnaExperiment object
        experiment <- MirnaExperiment(mirnaExpr = mirnaCounts,
                                      geneExpr = geneCounts,
                                      samplesMetadata = meta,
                                      pairedSamples = TRUE)
        
        # 3. Visualize expression variability using MDS plots
        pdf("mds_plots.pdf", width = 10, height = 5)
        geneMDS <- plotDimensions(experiment,
                                  assay = "genes",
                                  condition = "disease",
                                  title = "MDS plot for genes")
        mirnaMDS <- plotDimensions(experiment,
                                   assay = "microRNA",
                                   condition = "disease",
                                   title = "MDS plot for miRNAs")
        print(ggpubr::ggarrange(geneMDS, mirnaMDS,
                          nrow = 1, labels = "AUTO", common.legend = TRUE))
        dev.off()
        
        # 4. Perform differential expression for genes and miRNAs
        model <- ~ disease + patient
        experiment <- performGeneDE(experiment,
                                    group = "disease",
                                    contrast = contrast_str,
                                    design = model,
                                    pCutoff = 0.01)
        experiment <- performMirnaDE(experiment,
                                     group = "disease",
                                     contrast = contrast_str,
                                     design = model,
                                     pCutoff = 0.01)
        
        # 5. Access and visualize differential expression results
        deGenes <- geneDE(experiment)
        deMirnas <- mirnaDE(experiment)
        
        write.csv(deGenes, "de_genes.csv", row.names = TRUE)
        write.csv(deMirnas, "de_mirnas.csv", row.names = TRUE)
        
        pdf("volcano_plots.pdf", width = 10, height = 5)
        geneVolcano <- plotVolcano(experiment,
                                   assay = "genes",
                                   title = "Gene differential expression")
        mirnaVolcano <- plotVolcano(experiment,
                                    assay = "microRNA",
                                    title = "miRNA differential expression")
        print(ggpubr::ggarrange(geneVolcano, mirnaVolcano,
                          nrow = 1, labels = "AUTO", common.legend = TRUE))
        dev.off()
        
        # Dynamically plot top differentially expressed genes instead of hardcoded features
        if (nrow(deGenes) > 0) {
          top_genes <- rownames(deGenes)[seq_len(min(4, nrow(deGenes)))]
          pdf("de_barplot.pdf", width = 8, height = 6)
          print(plotDE(experiment,
                 features = top_genes,
                 graph = "barplot", linear = FALSE))
          dev.off()
        }
        
        # 6. Perform functional enrichment analysis (ORA and GSEA)
        supportedOrganisms("Reactome")
        
        # Wrap enrichment in tryCatch to handle potential offline/API issues gracefully
        tryCatch({
          ora <- enrichGenes(experiment,
                             method = "ORA",
                             database = "GO",
                             organism = "Homo sapiens")
          
          pdf("ora_dotplot.pdf", width = 8, height = 6)
          print(enrichmentDotplot(ora\$downregulated, title = "Depleted functions"))
          dev.off()
        }, error = function(e) {
          message("ORA enrichment failed: ", e\$message)
        })
        
        tryCatch({
          set.seed(1234)
          gse <- enrichGenes(experiment,
                             method = "GSEA",
                             database = "KEGG",
                             organism = "Homo sapiens")
          
          gse_res <- enrichmentResults(gse)
          write.csv(gse_res, "gsea_results.csv", row.names = FALSE)
          
          # Dynamically plot the top enriched pathway instead of a hardcoded one
          if (nrow(gse_res) > 0) {
            top_pathway <- gse_res\$pathway[1]
            pdf("gsea_plot.pdf", width = 8, height = 6)
            print(gseaPlot(gse, top_pathway, rankingMetric = TRUE))
            dev.off()
          }
        }, error = function(e) {
          message("GSEA enrichment failed: ", e\$message)
        })
        
        # 7. Retrieve predicted and validated miRNA targets & 8. Perform correlation-based integration
        tryCatch({
          experiment <- getTargets(experiment)
          experiment <- mirnaIntegration(experiment, test = "correlation")
          partial <- mirnaIntegration(experiment, test = "correlation",
                                      partial = TRUE, pCutoff = 1)
          
          # 9. Extract and visualize integrated miRNA-target pairs
          integrationResults <- integration(experiment)
          write.csv(integrationResults, "integration_results.csv", row.names = FALSE)
          print(head(integrationResults))
          
          # Dynamically plot top correlated pairs instead of hardcoded features
          if (nrow(integrationResults) > 0) {
            pdf("correlation_plots.pdf", width = 10, height = 5)
            
            pair1_mirna <- integrationResults\$microRNA[1]
            pair1_gene <- integrationResults\$Target[1]
            cor1 <- plotCorrelation(experiment,
                                    mirna = pair1_mirna,
                                    gene = pair1_gene,
                                    condition = "disease")
            
            if (nrow(integrationResults) > 1) {
              pair2_mirna <- integrationResults\$microRNA[2]
              pair2_gene <- integrationResults\$Target[2]
              cor2 <- plotCorrelation(experiment,
                                      mirna = pair2_mirna,
                                      gene = pair2_gene,
                                      condition = "disease")
              print(ggpubr::ggarrange(cor1, cor2, nrow = 1,
                                labels = "AUTO", common.legend = TRUE))
            } else {
              print(cor1)
            }
            dev.off()
          }
        }, error = function(e) {
          message("Target retrieval or integration failed (possibly due to offline environment or API limits): ", e\$message)
        })
        
        # Save the final experiment object
        saveRDS(experiment, "mirna_experiment.rds")

    writeLines(c(
        '"BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW":',
        paste0('    MIRit: ', as.character(packageVersion('MIRit')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_paired_integration_workflow.csv versions.yml
    """
}

workflow BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ geneCounts, mirnaCounts, meta ] ]

    main:
    BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW(ch_input)

    emit:
    tables   = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.tables
    plots    = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.plots
    objects  = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.objects
    versions = BIOC_MIRIT_PAIRED_INTEGRATION_WORKFLOW.out.versions
}
