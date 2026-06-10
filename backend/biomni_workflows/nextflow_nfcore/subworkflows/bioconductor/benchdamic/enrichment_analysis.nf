#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: benchdamic — enrichment_analysis
// Validate DA methods by checking if their significant findings are enriched for taxa known a priori to be differentially abundant.
// Input: ps_plaque_16S, microbial_metabolism
// Container: quay.io/biocontainers/bioconductor-benchdamic:1.6.0--r43hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: benchdamic, ggplot2, phyloseq
// Visualizations: enrichment plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Integrate prior knowledge with the dataset's taxonomy
//  * 2. [Core Analysis] Run normalizations and filter rare taxa
//  * 3. [Core Analysis] Compute zero-inflated negative binomial weights
//  * 4. [Input & Preparation] Set up and run DA methods on the full dataset
//  * 5. [Core Analysis] Perform enrichment analysis using prior knowledge
//  * 6. [Visualization & Output] Plot contingency tables, enrichment barplots, mutual findings, and true/false positive differences

nextflow.enable.dsl = 2

process BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS {
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
        library(benchdamic)
        library(phyloseq)
        library(ggplot2)
        
        # -----------------------------------------------------------------------------
        # 1. Read User Input Files
        # -----------------------------------------------------------------------------
        
        # Read ps_plaque_16S (phyloseq object)
        if (file.exists("ps_plaque_16S.rds")) {
          ps_plaque_16S <- readRDS("ps_plaque_16S.rds")
        } else if (file.exists("ps_plaque_16S.RData")) {
          load("ps_plaque_16S.RData")
        } else if (file.exists("ps_plaque_16S")) {
          ps_plaque_16S <- readRDS("ps_plaque_16S")
        } else {
          stop("Required input file 'ps_plaque_16S' not found in the working directory.")
        }
        
        # Read microbial_metabolism (data frame)
        if (file.exists("microbial_metabolism.rds")) {
          microbial_metabolism <- readRDS("microbial_metabolism.rds")
        } else if (file.exists("microbial_metabolism.csv")) {
          microbial_metabolism <- read.csv("microbial_metabolism.csv", header = TRUE, stringsAsFactors = FALSE)
        } else if (file.exists("microbial_metabolism.RData")) {
          load("microbial_metabolism.RData")
        } else if (file.exists("microbial_metabolism")) {
          microbial_metabolism <- readRDS("microbial_metabolism")
        } else {
          stop("Required input file 'microbial_metabolism' not found in the working directory.")
        }
        
        # Ensure HMP_BODY_SUBSITE and RSID are factors as required by the workflow
        sample_data(ps_plaque_16S)\$HMP_BODY_SUBSITE <- factor(sample_data(ps_plaque_16S)\$HMP_BODY_SUBSITE)
        sample_data(ps_plaque_16S)\$RSID <- factor(sample_data(ps_plaque_16S)\$RSID)
        
        # -----------------------------------------------------------------------------
        # 2. Integrate Prior Knowledge with Dataset's Taxonomy
        # -----------------------------------------------------------------------------
        
        genera <- tax_table(ps_plaque_16S)[, "GENUS"]
        rownames(microbial_metabolism) <- microbial_metabolism\$Genus
        priorInfo <- data.frame(genera, "Type" =  microbial_metabolism[genera, "Type"])
        unknown_metabolism <- is.na(priorInfo\$Type)
        priorInfo[unknown_metabolism, "Type"] <- "Unknown"
        priorInfo\$Type <- factor(priorInfo\$Type, 
            levels = c("Aerobic","Anaerobic","F Anaerobic","Unknown"), 
            labels = c("Aerobic","Anaerobic","F_Anaerobic","Unknown"))
        priorInfo[, "newNames"] <- paste0(rownames(priorInfo), "|", priorInfo[, "GENUS"])
        
        # -----------------------------------------------------------------------------
        # 3. Run Normalizations and Filter Rare Taxa
        # -----------------------------------------------------------------------------
        
        # Define normalization list required by runNormalizations
        my_normalizations <- setNormalizations(fun = "norm_edgeR", method = "TMM")
        
        ps_plaque_16S <- runNormalizations(my_normalizations, object = ps_plaque_16S)
        ps_plaque_16S <- phyloseq::filter_taxa(physeq = ps_plaque_16S, 
            flist = function(x) sum(x > 0) >= 3, prune = TRUE)
        
        # -----------------------------------------------------------------------------
        # 4. Compute Zero-Inflated Negative Binomial Weights
        # -----------------------------------------------------------------------------
        
        plaque_weights <- weights_ZINB(object = ps_plaque_16S, design = ~ 1,
            zeroinflation = TRUE)
        
        # -----------------------------------------------------------------------------
        # 5. Set Up and Run DA Methods on the Full Dataset
        # -----------------------------------------------------------------------------
        
        my_edgeR <- set_edgeR(
            group_name = "HMP_BODY_SUBSITE", 
            design = ~ 1 + RSID + HMP_BODY_SUBSITE, 
            coef = "HMP_BODY_SUBSITESupragingival Plaque", 
            norm = "TMM", 
            weights_logical = c(TRUE, FALSE),
            expand = TRUE)
        my_methods <- c(my_edgeR)
        
        Plaque_16S_DA <- runDA(method_list = my_methods, 
            object = ps_plaque_16S, weights = plaque_weights, verbose = FALSE)
        
        # -----------------------------------------------------------------------------
        # 6. Perform Enrichment Analysis Using Prior Knowledge
        # -----------------------------------------------------------------------------
        
        enrichment <- createEnrichment(
            object = Plaque_16S_DA, 
            priorKnowledge = priorInfo, 
            enrichmentCol = "Type",
            namesCol = "newNames", 
            slot = "pValMat", 
            colName = "adjP", 
            type = "pvalue",
            direction = c("logFC"),
            threshold_pvalue = c(0.1),
            threshold_logfc = 0,
            top = NULL,
            alternative = "greater",
            verbose = TRUE
        )
        
        # Save enrichment object
        saveRDS(enrichment, "enrichment_results.rds")
        
        # -----------------------------------------------------------------------------
        # 7. Plot Contingency, Enrichment, Mutual Findings, and Positives
        # -----------------------------------------------------------------------------
        
        # Plot Contingency Table
        pdf("contingency_plot.pdf", width = 7, height = 6)
        plotContingency(enrichment = enrichment, 
            levels_to_plot = c("Aerobic", "Anaerobic"), 
            method = "edgeR.TMM.weighted")
        dev.off()
        
        # Plot Enrichment Barplot
        pdf("enrichment_plot.pdf", width = 7, height = 6)
        plotEnrichment(enrichment = enrichment, enrichmentCol = "Type", 
            levels_to_plot = c("Aerobic", "Anaerobic"))
        dev.off()
        
        # Plot Mutual Findings
        pdf("mutual_findings_plot.pdf", width = 7, height = 6)
        plotMutualFindings(enrichment, enrichmentCol = "Type", 
            levels_to_plot = c("Aerobic", "Anaerobic"), n_methods = 2)
        dev.off()
        
        # Create Positives
        positives <- createPositives(
            object = Plaque_16S_DA, 
            priorKnowledge = priorInfo, 
            enrichmentCol = "Type",
            namesCol = "newNames", 
            slot = "pValMat", 
            colName = "rawP", 
            type = "pvalue",
            direction = c("logFC"),
            threshold_pvalue = c(0.1), 
            threshold_logfc = 0,
            top = seq.int(from = 0, to = 30, by = 3),
            alternative = "greater",
            verbose = FALSE,
            TP = list(c("DOWN Abundant", "Anaerobic"), c("UP Abundant", "Aerobic")),
            FP = list(c("DOWN Abundant", "Aerobic"), c("UP Abundant", "Anaerobic"))
        )
        
        # Save positives object
        saveRDS(positives, "positives_results.rds")
        
        # Plot Positives
        pdf("positives_plot.pdf", width = 8, height = 6)
        plotPositives(positives)
        dev.off()

    writeLines(c(
        '"BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS":',
        paste0('    benchdamic: ', as.character(packageVersion('benchdamic')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_enrichment_analysis.csv versions.yml
    """
}

workflow BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ ps_plaque_16S, microbial_metabolism ] ]

    main:
    BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS.out.tables
    plots    = BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS.out.plots
    objects  = BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS.out.objects
    versions = BIOC_BENCHDAMIC_ENRICHMENT_ANALYSIS.out.versions
}
