#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: mirTarRnaSeq — mirna_mrna_regression_cohorts
// Identify miRNA-mRNA target interactions in a cohort using various GLM regression models integrated with miRanda predictions.
// Input: EBV_mRNA.txt.gz, EBV_miRNA.txt.gz
// Container: quay.io/biocontainers/bioconductor-mirtarrnaseq:1.18.0--r45hdfd78af_0
// R packages: ggplot2, mirTarRnaSeq, reshape2
// Bioconductor: 3.20 | R: 4.4
// Requires: ggplot2, mirTarRnaSeq, reshape2
// Visualizations: density plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load mRNA and miRNA expression data
//  * 2. [Core Analysis] Retrieve species-specific miRanda target predictions using getInputSpecies
//  * 3. [Core Analysis] Filter mRNA data to keep only predicted targets using miRanComp
//  * 4. [Core Analysis] Combine mRNA and miRNA data for selected miRNAs using combiner and geneVari
//  * 5. [Core Analysis] Run univariate or multivariate GLM models using runModel or runModels with specified families (e.g., glm_gaussian(), glm_poisson()
//  * 6. [Core Analysis] Evaluate model performance using AIC values and select the best-fitting model
//  * 7. [Core Analysis] Run all-to-all combinations using runAllMirnaModels

nextflow.enable.dsl = 2

process BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS {
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
    .bm_deps <- c("ggplot2", "mirTarRnaSeq", "reshape2")
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
    library(mirTarRnaSeq)
    library(ggplot2)
    library(reshape2)
    
    # 1. Load mRNA and miRNA expression data from the working directory
    DiffExp <- read.table("EBV_mRNA.txt.gz", as.is = TRUE, header = TRUE, row.names = 1)
    miRNAExp <- read.table("EBV_miRNA.txt.gz", as.is = TRUE, header = TRUE, row.names = 1)
    
    # 2. Retrieve species-specific miRanda target predictions using getInputSpecies
    miRanda <- getInputSpecies("Epstein_Barr", threshold = 140)
    
    # 3. Filter mRNA data to keep only predicted targets using miRanComp
    DiffExpmRNASub <- miRanComp(DiffExp, miRanda)
    
    # 4. Combine mRNA and miRNA data for selected miRNAs using combiner and geneVari
    miRNA_select <- c("ebv-mir-BART9-5p")
    Combine <- combiner(DiffExp, miRNAExp, miRNA_select)
    geneVariant <- geneVari(Combine, miRNA_select)
    
    # 5. Run univariate GLM models using runModel or runModels with specified families
    # Run a single Poisson model
    j <- runModel(`LMP-1` ~ `ebv-mir-BART9-5p`,
                  Combine, model = glm_poisson(),
                  scale = 100)
    p_val_j <- modelTermPvalues(j)
    print(p_val_j)
    write.csv(as.data.frame(p_val_j), "LMP1_BART9_poisson_pvalue.csv")
    
    # Run Gaussian models
    blaGaus <- runModels(Combine,
                         geneVariant, miRNA_select,
                         family = glm_gaussian(),
                         scale = 100)
    
    pdf("gaussian_models_plots.pdf", width = 10, height = 7)
    par(oma = c(2, 2, 2, 2))
    par(mfrow = c(2, 3), mar = c(4, 3, 3, 2))
    plot(blaGaus[["all_models"]][["BHLF1"]])
    plot(modelData(blaGaus[["all_models"]][["BHLF1"]]))
    G <- do.call(rbind.data.frame, blaGaus[["AICvalues"]])
    names(G) <- c("AIC_G")
    plot(density(G\$AIC_G))
    dev.off()
    
    GM <- melt(G)
    
    # Run Poisson models
    blaPois <- runModels(Combine,
                         geneVariant, miRNA_select,
                         family = glm_poisson(),
                         scale = 100)
    
    pdf("poisson_models_plots.pdf", width = 10, height = 7)
    par(oma = c(2, 2, 2, 2))
    par(mfrow = c(2, 3), mar = c(4, 3, 3, 2))
    plot(blaPois[["all_models"]][["LMP-2A"]])
    plot(modelData(blaPois[["all_models"]][["LMP-2A"]]))
    P <- do.call(rbind.data.frame, blaPois[["AICvalues"]])
    names(P) <- c("AIC_Po")
    dev.off()
    
    PM <- melt(P)
    
    # Run Negative Binomial models
    blaNB <- runModels(Combine,
                       geneVariant, miRNA_select,
                       family = glm_nb(), scale = 100)
    
    pdf("nb_models_plots.pdf", width = 8, height = 6)
    par(mar = c(4, 3, 3, 2))
    plot(modelData(blaNB[["all_models"]][["BALF1"]]))
    dev.off()
    
    B <- do.call(rbind.data.frame, blaNB[["AICvalues"]])
    names(B) <- c("AIC_NB")
    BM <- melt(B)
    
    # Run Zero-Inflated Negative Binomial models
    blazeroinflNB <- runModels(Combine, geneVariant,
                                miRNA_select,
                                family = glm_zeroinfl(dist = "negbin"),
                                scale = 100)
    ZNB <- do.call(rbind.data.frame, blazeroinflNB[["AICvalues"]])
    names(ZNB) <- c("AIC_ZNB")
    
    pdf("zeroinfl_nb_density.pdf", width = 6, height = 5)
    par(mar = c(4, 3, 3, 2))
    plot(density(ZNB\$AIC_ZNB))
    dev.off()
    
    ZNBM <- melt(ZNB)
    
    # Run Zero-Inflated Poisson models
    blazeroinfl <- runModels(Combine, geneVariant,
                             miRNA_select,
                             family = glm_zeroinfl(),
                             scale = 100)
    Zp <- do.call(rbind.data.frame, blazeroinfl[["AICvalues"]])
    names(Zp) <- c("AIC_Zp")
    
    pdf("zeroinfl_poisson_density.pdf", width = 6, height = 5)
    par(mar = c(4, 3, 3, 2))
    plot(density(Zp\$AIC_Zp))
    dev.off()
    
    ZpM <- melt(Zp)
    
    # 6. Evaluate model performance using AIC values and select the best-fitting model
    bindM <- rbind(PM, BM, GM, ZpM, ZNBM)
    p2 <- ggplot(data = bindM, aes(x = value, group = variable,
                                   fill = variable)) +
      geom_density(adjust = 1.5, alpha = .3) +
      xlim(-400, 2000) +
      ggtitle("Plot of of AIC for ebv-mir-BART9-5p regressed all mRNAs ") +
      ylab("Density") + xlab("AIC Value")
    
    ggsave("combined_AIC_density_plot.pdf", plot = p2, width = 7, height = 5)
    
    # Run Multivariate Models
    miRNA_select <- c("ebv-mir-BART9-5p", "ebv-mir-BART6-3p")
    Combine <- combiner(DiffExp, miRNAExp, miRNA_select)
    geneVariant <- geneVari(Combine, miRNA_select)
    
    MultiModel <- runModels(Combine, geneVariant,
                            miRNA_select, family = glm_multi(),
                            mode = "multi", scale = 10)
    multi_model_names <- table(unlist(lapply(MultiModel\$all_models, modelModelName)))
    print(multi_model_names)
    write.csv(as.data.frame(multi_model_names), "multimodel_selected_names.csv")
    
    # Run Interaction Models
    InterModel <- runModels(Combine,
                            geneVariant, miRNA_select,
                            family = glm_multi(
                              models = list(glm_gaussian,
                              glm_poisson())), mode = "inter", scale = 10)
    inter_model_names <- table(unlist(lapply(InterModel\$all_models, modelModelName)))
    print(inter_model_names)
    write.csv(as.data.frame(inter_model_names), "intermodel_selected_names.csv")
    
    # 7. Run all-to-all combinations using runAllMirnaModels
    vMiRNA <- rownames(miRNAExp)
    All_miRNAs_run <- runAllMirnaModels(mirnas = vMiRNA[1:5],
                                      DiffExpmRNA = DiffExpmRNASub,
                                      DiffExpmiRNA = miRNAExp,
                                      miranda_data = miRanda, prob = 0.75,
                                      cutoff = 0.05, fdr_cutoff = 0.1, method = "fdr",
                                      family = glm_multi(), scale = 2, mode = "multi")
    
    hasgenes <- lapply(All_miRNAs_run, function(x) nrow(x\$SigFDRGenes)) > 0
    All_miRNAs_run <- All_miRNAs_run[hasgenes]
    
    # Print specific model summaries
    if (length(All_miRNAs_run) > 0) {
      print(table(unlist(lapply(All_miRNAs_run[[1]][["FDRModel"]][["all_models"]], modelModelName))))
    }
    
    target_name <- "ebv-mir-BART1-5p and ebv-mir-BART11-3p"
    if (target_name %in% names(All_miRNAs_run)) {
      print(table(unlist(lapply(All_miRNAs_run[[target_name]][["FDRModel"]][["all_models"]], modelModelName))))
    }
    
    # Save the all-miRNA run results
    saveRDS(All_miRNAs_run, "All_miRNAs_run.rds")
    
    # Optional SPONGE integration
    try({
      sponge_mir_input <- miranda_sponge_predict(miRNAExp, DiffExp, miRanda)
      one2many_output <- one2manySponge(miRNAExp, DiffExp, sponge_mir_input)
      saveRDS(one2many_output, "one2many_sponge_output.rds")
    })

    writeLines(c(
        '"BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS":',
        paste0('    mirTarRnaSeq: ', as.character(packageVersion('mirTarRnaSeq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_mirna_mrna_regression_cohorts.csv versions.yml
    """
}

workflow BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ EBV_mRNA.txt.gz, EBV_miRNA.txt.gz ] ]

    main:
    BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS(ch_input)

    emit:
    tables   = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.tables
    plots    = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.plots
    objects  = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.objects
    versions = BIOC_MIRTARRNASEQ_MIRNA_MRNA_REGRESSION_COHORTS.out.versions
}
