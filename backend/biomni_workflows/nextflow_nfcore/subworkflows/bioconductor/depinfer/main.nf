#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DepInfeR — protein_dependency_inference
// Infer sample-specific protein dependencies from drug-protein affinity and drug response matrices using regularized multivariate linear regression.
// Input: targetsGDSC, drug_response_GDSC
// Container: quay.io/biocontainers/bioconductor-depinfer:1.14.0--r45hdfd78af_0
// R packages: BiocParallel, DepInfeR, dplyr, ggbeeswarm, ggplot2, ggrepel, missForest, pheatmap, RColorBrewer, tibble, tidyr
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, DepInfeR, RColorBrewer, dplyr, ggbeeswarm, ggplot2, ggrepel, missForest, pheatmap, tibble, tidyr
// Visualizations: heatmap, dot plot, box plot
// QC: low-count filtering, missing-value handling
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Preprocess the drug-protein affinity matrix using processTarget to transform values and filter correlated targets. 2. Handle missi

nextflow.enable.dsl = 2

process BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-proteomics:3.20"

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
    .bm_deps <- c("BiocParallel", "DepInfeR", "dplyr", "ggbeeswarm", "ggplot2", "ggrepel", "missForest", "pheatmap", "RColorBrewer", "tibble", "tidyr")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      .rv <- getRversion()
      .biocv <- if (.rv >= "4.5") "3.21" else if (.rv >= "4.4") "3.20" else if (.rv >= "4.3") "3.18" else "3.16"
      .repos <- c(sprintf("https://bioconductor.org/packages/%s/bioc", .biocv), sprintf("https://bioconductor.org/packages/%s/data/annotation", .biocv), sprintf("https://bioconductor.org/packages/%s/data/experiment", .biocv), "https://cloud.r-project.org")
      suppressWarnings(try(install.packages(.bm_miss, repos=.repos, quiet=TRUE), silent=TRUE))
    }
    
    # Load required libraries
    library(DepInfeR)
    library(tibble)
    library(tidyr)
    library(ggplot2)
    library(BiocParallel)
    library(dplyr)
    library(missForest)
    library(RColorBrewer)
    library(pheatmap)
    library(ggrepel)
    library(ggbeeswarm)
    
    # Set seed for reproducibility
    set.seed(123)
    
    # Helper function to read input files from the working directory
    read_input_file <- function(base_name) {
      if (file.exists(paste0(base_name, ".rds"))) {
        return(readRDS(paste0(base_name, ".rds")))
      } else if (file.exists(paste0(base_name, ".csv"))) {
        return(read.csv(paste0(base_name, ".csv"), check.names = FALSE, stringsAsFactors = FALSE))
      } else if (file.exists(paste0(base_name, ".tsv"))) {
        return(read.delim(paste0(base_name, ".tsv"), check.names = FALSE, stringsAsFactors = FALSE))
      } else {
        stop(paste("Required input file not found in working directory:", base_name))
      }
    }
    
    # 1. Read declared user inputs
        # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
        for (.bm_d in list.files(".", full.names = TRUE)) {
          if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
            for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
              if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
            }
          }
        }
    targetsGDSC <- read_input_file("targetsGDSC")
    drug_response_GDSC <- read_input_file("drug_response_GDSC")
    
    # Rename BCR to BCR/ABL to avoid confusion with B-cell receptor (BCR)
    targetsGDSC <- mutate(targetsGDSC,
      targetName = ifelse(targetName %in% "BCR", "BCR/ABL", targetName)
    )
    
    # Turn target table into drug-protein affinity matrix
    targetMatrix <- filter(
      targetsGDSC,
      targetClassification == "High confidence"
    ) %>%
      select(drugID, targetName, Kd) %>%
      pivot_wider(names_from = "targetName", values_from = "Kd") %>%
      remove_rownames() %>%
      column_to_rownames("drugID") %>%
      as.matrix()
    
    # Preprocess the drug-protein affinity matrix
    ProcessTargetResults <- processTarget(targetMatrix,
      KdAsInput = TRUE,
      removeCorrelated = TRUE
    )
    
    # Prepare drug response matrix
    responseMatrix <- filter(drug_response_GDSC, `Drug Id` %in% targetsGDSC\$drugID) %>%
      select(`Drug Id`, `Cell line name`, AUC) %>%
      pivot_wider(names_from = `Cell line name`, values_from = AUC) %>%
      remove_rownames() %>%
      column_to_rownames("Drug Id") %>%
      as.matrix()
    
    # Subset for cell lines with less than or equal to 24 missing values
    responseMatrix <- responseMatrix[, colSums(is.na(responseMatrix)) <= 24]
    
    # Impute missing values using missForest
    impRes <- missForest(t(responseMatrix))
    imp_missforest <- impRes\$ximp
    responseMatrix_imputed <- t(imp_missforest)
    
    # Calculate column-wise z-score
    responseMatrix_scaled <- t(scale(t(responseMatrix_imputed)))
    
    # Combine the feature and response matrix for the regression model
    targetInput <- ProcessTargetResults\$targetMatrix
    
    overlappedDrugs <- intersect(
      rownames(responseMatrix_scaled),
      rownames(targetInput)
    )
    
    targetInput <- targetInput[overlappedDrugs, ]
    responseInput <- responseMatrix_scaled[overlappedDrugs, ]
    
    # Set up BiocParallel back-end and run multi-target LASSO regression
    param <- MulticoreParam(workers = 2, RNGseed = 333)
    
    result <- runLASSORegression(
      TargetMatrix = targetInput,
      ResponseMatrix = responseInput, repeats = 3,
      BPPARAM = param
    )
    
    # Remove targets that were never selected
    useTar <- rowSums(result\$coefMat != 0) > 0
    result\$coefMat <- result\$coefMat[useTar, ]
    
    # Save primary regression outputs
    write.csv(result\$coefMat, "protein_dependence_matrix.csv", row.names = TRUE)
    saveRDS(result, "regression_results.rds")
    
    # 2. Downstream Analysis and Visualization
    # Try to read mutation_GDSC from working directory if available, otherwise construct from drug_response_GDSC
    mutation_GDSC <- NULL
    if (file.exists("mutation_GDSC.rds") || file.exists("mutation_GDSC.csv") || file.exists("mutation_GDSC.tsv")) {
      mutation_GDSC <- read_input_file("mutation_GDSC")
    } else {
      if ("Cell line name" %in% colnames(drug_response_GDSC) && "TCGA classification" %in% colnames(drug_response_GDSC)) {
        mutation_GDSC <- drug_response_GDSC %>%
          select(`Cell line name`, `TCGA classification`) %>%
          distinct() %>%
          rename(TCGA.classification = `TCGA classification`) %>%
          mutate(TCGA.classification = gsub("-", ".", TCGA.classification)) %>%
          remove_rownames() %>%
          column_to_rownames("Cell line name")
        mutation_GDSC\$missing_value_perc <- 0
      }
    }
    
    if (!is.null(mutation_GDSC)) {
      importanceTab <- result\$coefMat
      colnames(importanceTab) <- gsub("-", ".", colnames(importanceTab))
      
      # Align mutation annotation with the results
      rownames(mutation_GDSC) <- gsub("-", ".", rownames(mutation_GDSC))
      mutation_GDSC_filtered <- mutation_GDSC[intersect(rownames(mutation_GDSC), colnames(importanceTab)), , drop = FALSE]
      importanceTab <- importanceTab[, rownames(mutation_GDSC_filtered), drop = FALSE]
      
      if ("TCGA.classification" %in% colnames(mutation_GDSC_filtered)) {
        mutation_GDSC_filtered\$TCGA.classification[mutation_GDSC_filtered\$TCGA.classification == "BRCA"] <- "BRCAHer-"
        all_levels <- c("ALL", "AML", "DLBC", "BRCAHer-", "BRCAHer+")
        existing_levels <- intersect(all_levels, unique(mutation_GDSC_filtered\$TCGA.classification))
        mutation_GDSC_filtered\$TCGA.classification <- factor(mutation_GDSC_filtered\$TCGA.classification, levels = existing_levels)
      }
      
      # Heatmap of protein dependence coefficients
      annoColor_full <- list(
        H2O2 = c(`-1` = "red", `0` = "black", `1` = "green"),
        IL.1 = c(`-1` = "red", `0` = "black", `1` = "green"),
        JAK.STAT = c(`-1` = "red", `0` = "black", `1` = "green"),
        MAPK.only = c(`-1` = "red", `0` = "black", `1` = "green"),
        MAPK.PI3K = c(`-1` = "red", `0` = "black"),
        TLR = c(`-1` = "red", `0` = "black", `1` = "green"),
        Wnt = c(`-1` = "red", `0` = "black", `1` = "green"),
        VEGF = c(`-1` = "red", `0` = "black", `1` = "green"),
        PI3K.only = c(`-1` = "red", `0` = "black", `1` = "green"),
        TCGA.classification = c(
          ALL = "#BC3C29FF", AML = "#E18727FF",
          DLBC = "#20854EFF", "BRCAHer-" = "#0072B5FF",
          "BRCAHer+" = "#7876B1FF"
        ),
        ARID1A_mut = c(`1` = "black", `0` = "grey80"),
        EP300_mut = c(`1` = "black", `0` = "grey80"),
        PTEN_mut = c(`1` = "black", `0` = "grey80"),
        TP53_mut = c(`1` = "black", `0` = "grey80"),
        PIK3CA_mut = c(`1` = "black", `0` = "grey80"),
        BRCA2_mut = c(`1` = "black", `0` = "grey80"),
        BRCA1_mut = c(`1` = "black", `0` = "grey80"),
        CDH1_mut = c(`1` = "black", `0` = "grey80"),
        FBXW7_mut = c(`1` = "black", `0` = "grey80"),
        NRAS_mut = c(`1` = "black", `0` = "grey80"),
        ASXL1_mut = c(`1` = "black", `0` = "grey80"),
        MLL2_mut = c(`1` = "black", `0` = "grey80"),
        ABL1_trans = c(`1` = "black", `0` = "grey80"),
        missing_value_perc = c(`0` = "white", `25` = "red")
      )
      annoColor <- annoColor_full[intersect(names(annoColor_full), colnames(mutation_GDSC_filtered))]
      
      plotTab <- importanceTab
      plotTab_scaled <- scale(t(plotTab), center = FALSE, scale = TRUE)
      
      pdf("heatmap_protein_dependence.pdf", width = 10, height = 12)
      pheatmap(plotTab_scaled,
        color = colorRampPalette(rev(brewer.pal(n = 7, name = "RdBu")), bias = 1.8)(100),
        annotation_row = mutation_GDSC_filtered,
        annotation_colors = annoColor,
        clustering_method = "ward.D2", scale = "none",
        main = "Protein Dependence Coefficients", fontsize = 9,
        fontsize_row = 7, fontsize_col = 10
      )
      dev.off()
      
      # Prepare genomic background table
      cell_anno_final <- mutation_GDSC_filtered
      if ("missing_value_perc" %in% colnames(cell_anno_final)) {
        cell_anno_final <- cell_anno_final %>% select(-missing_value_perc)
      }
      if ("TCGA.classification" %in% colnames(cell_anno_final)) {
        cell_anno_final <- cell_anno_final %>% rename(cancer_type = TCGA.classification)
      }
      colnames(cell_anno_final) <- gsub("_mut", "", colnames(cell_anno_final))
      colnames(cell_anno_final) <- gsub("_trans", "_translocation", colnames(cell_anno_final))
      
      # Association test function
      diffImportance <- function(coefMat, Annotation) {
        geneBack <- Annotation
        geneBack <- geneBack[colnames(coefMat), , drop = FALSE]
        keepCols <- apply(geneBack, 2, function(x) {
          length(unique(na.omit(x))) >= 2 & all(table(x) > 6)
        })
        if (!any(keepCols)) return(NULL)
        geneBack <- geneBack[, keepCols, drop = FALSE]
        
        pTab <- lapply(rownames(coefMat), function(targetName) {
          lapply(colnames(geneBack), function(mutName) {
            impVec <- coefMat[targetName, ]
            genoVec <- geneBack[, mutName]
            resTab <- data.frame(
              targetName = targetName, mutName = mutName,
              stringsAsFactors = FALSE
            )
            if (length(unique(na.omit(genoVec))) == 2) {
              res <- t.test(impVec ~ genoVec, var.equal = TRUE, na.action = na.omit)
              resTab\$p <- res\$p.value
              resTab\$FC <- (res\$estimate[[2]] - res\$estimate[[1]]) / abs(res\$estimate[[1]])
            } else if (length(unique(na.omit(genoVec))) >= 3) {
              res <- anova(lm(impVec ~ genoVec, na.action = na.omit))
              diffTab <- data.frame(val = impVec, gr = genoVec) %>%
                filter(!is.na(gr)) %>%
                group_by(gr) %>%
                summarise(meanVal = mean(val), .groups = 'drop')
              resTab\$p <- res\$`Pr(>F)`[1]
              resTab\$FC <- max(diffTab\$meanVal) - min(diffTab\$meanVal)
            } else {
              resTab\$p <- NA
              resTab\$FC <- NA
            }
            resTab
          }) %>% bind_rows()
        }) %>%
          bind_rows() %>%
          filter(!is.na(p)) %>%
          arrange(p) %>%
          mutate(p.adj = p.adjust(p, method = "BH"))
        pTab
      }
      
      testRes <- diffImportance(importanceTab, cell_anno_final)
      
      if (!is.null(testRes) && nrow(testRes) > 0) {
        write.csv(testRes, "target_importance_associations.csv", row.names = FALSE)
        
        # Visualize protein associations with cancer type
        CancerType <- testRes %>%
          filter(mutName == "cancer_type") %>%
          filter(p.adj < 0.05, FC > 0.1)
        
        if (nrow(CancerType) > 0) {
          plotTab_cancer <- t(scale(t(importanceTab))) %>%
            data.frame() %>%
            rownames_to_column("target") %>%
            gather(key = "CellLine", value = "coef", -target) %>%
            mutate(Cancer_Type = mutation_GDSC_filtered[CellLine, ]\$TCGA.classification) %>%
            group_by(target, Cancer_Type) %>%
            mutate(meanCoef = mean(coef)) %>%
            arrange(meanCoef) %>%
            ungroup() %>%
            mutate(target = factor(target, levels = unique(target)))
          
          plotTab_cancer <- plotTab_cancer %>% filter(target %in% CancerType\$targetName)
          plotTab_cancer\$Cancer_Type <- factor(plotTab_cancer\$Cancer_Type,
            levels = intersect(c("ALL", "AML", "DLBC", "BRCAHer-", "BRCAHer+"), unique(plotTab_cancer\$Cancer_Type))
          )
          
          p_cancer <- ggplot(plotTab_cancer, aes(x = target, y = coef, group = Cancer_Type)) +
            geom_jitter(aes(color = Cancer_Type),
              position = position_jitterdodge(jitter.width = 0.2, dodge.width = 0.8),
              size = 1.2
            ) +
            stat_summary(
              fun = mean, fun.min = mean, fun.max = mean, colour = "grey25",
              geom = "crossbar", size = 0.8,
              position = position_dodge(0.8)
            ) +
            scale_color_manual(
              values = c(
                ALL = "#BC3C29FF", AML = "#E18727FF",
                DLBC = "#20854EFF", `BRCAHer-` = "#0072B5FF", `BRCAHer+` = "#7876B1FF"
              ),
              guide = guide_legend(override.aes = list(size = 3))
            ) +
            ggtitle("Protein dependence associated with cancer type") +
            ylab("Protein dependence coefficient") +
            xlab("Protein") +
            theme_bw() +
            geom_vline(xintercept = seq(from = 1.5, to = length(unique(plotTab_cancer\$target)) - 0.5, by = 1), color = "darkgrey") +
            labs(color = "Cancer Type")
          
          ggsave("beeswarm_protein_dependence_cancer_type.pdf", plot = p_cancer, width = 10, height = 5)
        }
        
        # Visualize mutational background associations
        plotTab_mut <- testRes %>% filter(mutName != "cancer_type")
        if (nrow(plotTab_mut) > 0) {
          colList2 <- c(`not significant` = "grey80", mutated = "#BC3C29FF", unmutated = "#0072B5FF")
          pos <- position_jitter(width = 0.15, seed = 10)
          plotTab_mut <- plotTab_mut %>%
            mutate(type = ifelse(p.adj > 0.1, "not significant", ifelse(FC > 0, "mutated", "unmutated"))) %>%
            mutate(varName = ifelse(type == "not significant", "", targetName)) %>%
            mutate(p.adj = ifelse(p.adj < 1e-5, 1e-5, p.adj))
          
          plotMut <- unique(filter(testRes, p.adj <= 0.1 & mutName != "cancer_type")\$mutName)
          if (length(plotMut) > 0) {
            plotTab_mut <- plotTab_mut %>% filter(mutName %in% plotMut)
            plotTab_mut\$type <- factor(plotTab_mut\$type, levels = intersect(c("mutated", "unmutated", "not significant"), unique(plotTab_mut\$type)))
            
            p_mut <- ggplot(data = plotTab_mut, aes(x = mutName, y = -log10(p.adj), col = type, label = varName)) +
              geom_text_repel(position = pos, color = "black", size = 6, force = 3) +
              geom_hline(yintercept = -log10(0.1), linetype = "dotted", color = "grey20") +
              geom_point(size = 3, position = pos) +
              ylab(expression(-log[10] * "(" * adjusted ~ italic("P") ~ value * ")")) +
              xlab("Mutation") +
              scale_color_manual(values = colList2) +
              scale_y_continuous(trans = "exp", limits = c(0, 2.5), breaks = c(0, 1, 1.5, 2)) +
              coord_flip() +
              labs(col = "Higher dependence in") +
              theme_bw() +
              theme(
                legend.position = "bottom",
                legend.text = element_text(size = 12),
                legend.title = element_text(size = 14),
                axis.title = element_text(size = 14),
                axis.text = element_text(size = 14)
              )
            ggsave("dotplot_mutation_associations.pdf", plot = p_mut, width = 10, height = 6)
          }
        }
        
        # Boxplot visualization for significant associations
        formatNum <- function(i, limit = 0.01, digits = 1, format = "e") {
          sapply(i, function(n) {
            if (n < limit) {
              formatC(n, digits = digits, format = format)
            } else {
              format(n, digits = digits)
            }
          })
        }
        
        plotDiffBox <- function(pTab, coefMat, cellAnno, fdrCut = 0.05) {
          pTab.sig <- filter(pTab, p.adj <= fdrCut)
          if (nrow(pTab.sig) == 0) return(list())
          geneBack <- cellAnno
          geneBack <- geneBack[colnames(coefMat), , drop = FALSE]
          pList <- lapply(seq(nrow(pTab.sig)), function(i) {
            geno <- pTab.sig[i, ]\$mutName
            target <- pTab.sig[i, ]\$targetName
            pval <- pTab.sig[i, ]\$p
            plotTab <- tibble(
              id = colnames(coefMat),
              mut = geneBack[, geno], val = coefMat[target, ]
            ) %>% filter(!is.na(mut))
            
            plotTab <- mutate(plotTab, mut = ifelse(mut %in% c("M", "1", 1), "Mutated", "Unmutated")) %>%
              mutate(mut = factor(mut, levels = c("Unmutated", "Mutated")))
            
            numTab <- group_by(plotTab, mut) %>% summarise(n = length(id), .groups = 'drop')
            plotTab <- left_join(plotTab, numTab, by = "mut") %>%
              mutate(mutNum = sprintf("%s\n(n=%s)", mut, n)) %>%
              arrange(mut) %>%
              mutate(mutNum = factor(mutNum, levels = unique(mutNum)))
            
            titleText <- sprintf("%s ~ %s %s", target, geno, "mutations")
            pval <- formatNum(pval, digits = 1, format = "e")
            titleText <- bquote(atop(.(titleText), "(" ~ italic("P") ~ "=" ~ .(pval) ~ ")"))
            
            ggplot(plotTab, aes(x = mutNum, y = val)) +
              stat_boxplot(geom = "errorbar", width = 0.3) +
              geom_boxplot(outlier.shape = NA, col = "black", width = 0.4) +
              geom_beeswarm(cex = 2, size = 2, aes(col = mutNum)) +
              theme_classic() +
              xlab("") +
              ylab("Protein dependence") +
              ggtitle(titleText) +
              scale_color_manual(values = c("#0072B5FF", "#BC3C29FF")) +
              theme(
                axis.line.x = element_blank(), axis.ticks.x = element_blank(),
                axis.title = element_text(size = 14), axis.text = element_text(size = 14),
                plot.title = element_text(size = 16, face = "bold", hjust = 0.5),
                legend.position = "none"
              )
          })
          names(pList) <- paste0(pTab.sig\$targetName, "_", pTab.sig\$mutName)
          return(pList)
        }
        
        sig_associations <- filter(testRes, p.adj <= 0.05)
        if (nrow(sig_associations) > 0) {
          pList <- tryCatch({
            plotDiffBox(testRes, importanceTab, cell_anno_final, 0.05)
          }, error = function(e) {
            NULL
          })
          if (!is.null(pList) && length(pList) > 0) {
            pdf("boxplot_significant_association.pdf", width = 6, height = 6)
            print(pList[[1]])
            dev.off()
          }
        }
      }
    }

    writeLines(c(
        '"BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE":',
        paste0('    DepInfeR: ', as.character(packageVersion('DepInfeR')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_protein_dependency_inference.csv versions.yml
    """
}

workflow BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ targetsGDSC, drug_response_GDSC ] ]

    main:
    BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE(ch_input)

    emit:
    tables   = BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE.out.tables
    plots    = BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE.out.plots
    objects  = BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE.out.objects
    versions = BIOC_DEPINFER_PROTEIN_DEPENDENCY_INFERENCE.out.versions
}
