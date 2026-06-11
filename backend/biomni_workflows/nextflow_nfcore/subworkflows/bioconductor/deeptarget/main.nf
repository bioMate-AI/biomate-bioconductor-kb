#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DeepTarget — drug_target_prediction_and_characterization
// Predict and characterize primary and secondary drug targets by integrating drug response and CRISPR gene knockout screens across cancer cell lines.
// Input: secondary_prism.csv, avana_CRISPR.csv, mutations_mat.csv, expression_20Q4.csv, DrugMetadata.csv
// Container: quay.io/biocontainers/bioconductor-deeptarget:1.4.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: DeepTarget
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load and prepare drug response and CRISPR KO matrices
//  * 2. [Core Analysis] Compute correlation/similarity between drug treatment and gene knockout using computeCor
//  * 3. [Core Analysis] Predict similarity across known targeted genes and all genes using PredTarget and PredMaxSim
//  * 4. [Core Analysis] Compute mutant-specific and expression-specific interactions using DoInteractMutant and DoInteractExp
//  * 5. [Visualization & Output] Assess interactions and prepare the prediction output data frame
//  * 6. [Core Analysis] Identify secondary targets in cell lines with low primary target expression using computeCor on subsetted data
//  * 7. [Visualization & Output] Visualize primary targets using plotCor
//  * 8. [Visualization & Output] Predict and visualize mutant vs. wild-type target specificity using DMB
//  * 9. [Visualization & Output] Predict and visualize secondary targets using DTR and plotSim

nextflow.enable.dsl = 2

process BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION {
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
        library(DeepTarget)
        
        # 1. Load and prepare drug response and CRISPR KO matrices from user input files
        secondary_prism <- as.matrix(read.csv("secondary_prism.csv", row.names = 1, check.names = FALSE))
        avana_CRISPR <- as.matrix(read.csv("avana_CRISPR.csv", row.names = 1, check.names = FALSE))
        mutations_mat <- as.matrix(read.csv("mutations_mat.csv", row.names = 1, check.names = FALSE))
        expression_20Q4 <- as.matrix(read.csv("expression_20Q4.csv", row.names = 1, check.names = FALSE))
        DrugMetadata <- read.csv("DrugMetadata.csv", check.names = FALSE)
        
        # Construct the OntargetM list structure to match the package's expected format
        OntargetM <- list(
          secondary_prism = secondary_prism,
          avana_CRISPR = avana_CRISPR,
          mutations_mat = mutations_mat,
          expression_20Q4 = expression_20Q4,
          DrugMetadata = DrugMetadata
        )
        
        # Verify dimensions
        print("Dimensions of OntargetM components:")
        print(vapply(OntargetM, dim, FUN.VALUE = numeric(2)))
        
        # Obtain the broad ID for all available drugs in the metadata
        Broad.IDs <- OntargetM\$DrugMetadata\$broad_id_trimmed
        
        # Filter secondary prism and CRISPR KO matrices
        sec.prism.f <- OntargetM\$secondary_prism[which(row.names(OntargetM\$secondary_prism) %in% Broad.IDs), , drop = FALSE]
        KO.GES <- OntargetM\$avana_CRISPR
        
        # 2. Compute correlation/similarity between drug treatment and gene knockout using computeCor
        List.sim <- NULL
        for (i in 1:nrow(sec.prism.f)){
            DRS <- as.data.frame(sec.prism.f[i,])
            DRS <- t(DRS)
            row.names(DRS) <- row.names(sec.prism.f)[i]
            out <- computeCor(row.names(sec.prism.f)[i], DRS, KO.GES)
            List.sim[[length(List.sim) + 1]] <- out
        }
        names(List.sim) <- row.names(sec.prism.f)
        
        # Save List.sim to RDS
        saveRDS(List.sim, "List_sim.rds")
        
        # 3. Predict similarity across known targeted genes and all genes using PredTarget and PredMaxSim
        metadata <- OntargetM\$DrugMetadata
        DrugTarcomputeCor <- PredTarget(List.sim, metadata)
        DrugGeneMaxSim <- PredMaxSim(List.sim, metadata)
        
        # 4. Compute mutant-specific and expression-specific interactions using DoInteractMutant and DoInteractExp
        d.mt <- OntargetM\$mutations_mat
        d.expr <- OntargetM\$expression_20Q4
        out.MutantTarget <- NULL
        out.LowexpTarget <- NULL
        
        for (i in 1:nrow(sec.prism.f)){
            DRS <- as.data.frame(sec.prism.f[i,])
            DRS <- t(DRS)
            row.names(DRS) <- row.names(sec.prism.f)[i]
            
            # For mutant
            Out.M <- DoInteractMutant(DrugTarcomputeCor[i,], d.mt, DRS, KO.GES)
            TargetMutSpecificity <- data.frame(
                MaxTgt_Inter_Mut_strength = vapply(Out.M, function(x) x[1], numeric(1)), 
                MaxTgt_Inter_Mut_Pval = vapply(Out.M, function(x) x[2], numeric(1))
            )
            out.MutantTarget <- rbind(out.MutantTarget, TargetMutSpecificity)
            
            # For expression
            Out.Expr <- DoInteractExp(DrugTarcomputeCor[i,], d.expr, DRS, KO.GES, CutOff = 2)
            TargetExpSpecificity <- data.frame(
                MaxTgt_Inter_Exp_strength = vapply(Out.Expr, function(x) x[1], numeric(1)),
                MaxTgt_Inter_Exp_Pval = vapply(Out.Expr, function(x) x[2], numeric(1))
            )
            out.LowexpTarget <- rbind(out.LowexpTarget, TargetExpSpecificity)
        }
        
        # 5. Assess interactions and prepare the prediction output data frame
        Whether_interaction_Ex_based <- ifelse(
            out.LowexpTarget\$MaxTgt_Inter_Exp_strength < 0 & out.LowexpTarget\$MaxTgt_Inter_Exp_Pval < 0.2, 
            TRUE, 
            FALSE
        )
        predicted_resistance_mut <- ifelse(
            out.MutantTarget\$MaxTgt_Inter_Mut_Pval < 0.1, 
            TRUE, 
            FALSE
        )
        
        Pred.d <- NULL
        Pred.d <- cbind(DrugTarcomputeCor, DrugGeneMaxSim, out.MutantTarget, predicted_resistance_mut)
        
        mutant.C <- vapply(
            Pred.d[,3], 
            function(x) tryCatch(sum(d.mt[x,] == 1), error = function(e){NA}), 
            FUN.VALUE = length(Pred.d[,3])
        )
        Pred.d\$mutant.C <- mutant.C
        
        Low.Exp.C <- vapply(
            Pred.d[,3],
            function(x) tryCatch(sum(d.expr[x,] < 2), error = function(e){NA}), 
            FUN.VALUE = length(Pred.d[,3])
        )
        Pred.d <- cbind(Pred.d, out.LowexpTarget, Whether_interaction_Ex_based, Low.Exp.C)
        
        # Save main prediction output
        write.csv(Pred.d, "Pred_d.csv", row.names = FALSE)
        
        # 6. Identify secondary targets in cell lines with low primary target expression using computeCor on subsetted data
        Low.i <- which(Pred.d\$Low.Exp.C > 5)
        Pred.d.f <- Pred.d[Low.i, , drop = FALSE]
        write.csv(Pred.d.f, "Pred_d_f.csv", row.names = FALSE)
        
        Low.Exp.G <- NULL
        if (nrow(Pred.d.f) > 0) {
            for (i in 1:nrow(Pred.d.f)){
                Gene.i <- Pred.d.f[,3][i]
                Temp <- tryCatch(names(which(d.expr[Gene.i,] < 2)), error = function(e){NA})
                Low.Exp.G[[length(Low.Exp.G) + 1]] <- Temp
            }
            names(Low.Exp.G) <- Pred.d.f[,3]
        }
        
        sim.LowExp <- NULL
        sec.prism.f.f <- sec.prism.f[Low.i, , drop = FALSE]
        print("Checking row name identity for low expression subset:")
        if (nrow(Pred.d.f) > 0) {
            print(identical(row.names(sec.prism.f.f), Pred.d.f[,1]))
            
            for (i in 1:nrow(Pred.d.f)){
                DRS.L <- sec.prism.f.f[i, Low.Exp.G[[unlist(Pred.d.f[i,3])]], drop = FALSE]
                DRS.L <- t(as.data.frame(DRS.L))
                row.names(DRS.L) <- Pred.d.f[i,1]
                out <- computeCor(Pred.d.f[i,1], DRS.L, KO.GES)
                sim.LowExp[[length(sim.LowExp) + 1]] <- out
            }
            names(sim.LowExp) <- Pred.d.f[,1]
        }
        
        # Save sim.LowExp to RDS
        saveRDS(sim.LowExp, "sim_LowExp.rds")
        
        # 7. Visualize primary targets using plotCor
        if (nrow(Pred.d) > 0) {
            # Visualization 1
            DOI <- Pred.d\$drugName[1]
            GOI <- Pred.d\$MaxTargetName[1]
            pdf("plotCor_primary_target_1.pdf")
            plotCor(DOI, GOI, Pred.d, sec.prism.f, KO.GES, plot = TRUE)
            dev.off()
        }
        
        if (nrow(Pred.d) > 1) {
            # Visualization 2
            DOI <- Pred.d\$drugName[2]
            GOI <- Pred.d\$MaxTargetName[2]
            DrugID <- Pred.d\$DrugID[2]
            DRS <- as.data.frame(sec.prism.f[DrugID,])
            DRS <- t(DRS)
            row.names(DRS) <- DrugID
            
            pdf("plotCor_primary_target_2.pdf")
            plotCor(DOI, GOI, Pred.d[2,], DRS, KO.GES, plot = TRUE)
            dev.off()
        }
        
        # 8. Predict and visualize mutant vs. wild-type target specificity using DMB
        Pred.d.f_mut <- Pred.d
        Pred.d.f.f <- Pred.d.f_mut[which(Pred.d.f_mut\$predicted_resistance_mut == TRUE), , drop = FALSE]
        
        # Visualization 3: Mutant specificity
        if (nrow(Pred.d.f.f) > 0) {
            DOI <- Pred.d.f.f\$drugName[1]
            GOI <- Pred.d.f.f\$MaxTargetName[1]
            DrugID <- Pred.d.f.f\$DrugID[1]
            DRS <- as.data.frame(sec.prism.f[DrugID,])
            DRS <- t(DRS)
            row.names(DRS) <- DrugID
            
            print("Initial 5 outcomes for mutant specificity 1:")
            print(DRS[1, 1:min(5, ncol(DRS))])
            
            pdf("DMB_mutant_specificity_1.pdf")
            out_DMB_1 <- DMB(DOI, GOI, Pred.d.f.f[1,], d.mt, DRS, KO.GES, plot = TRUE)
            dev.off()
            print("DMB Output 1:")
            print(out_DMB_1)
        }
        
        # Visualization 4: Mutant specificity for another drug
        if (nrow(Pred.d.f_mut) > 0) {
            DOI <- Pred.d.f_mut\$drugName[1]
            GOI <- Pred.d.f_mut\$MaxTargetName[1]
            DrugID <- Pred.d.f_mut\$DrugID[1]
            
            DRS <- as.data.frame(sec.prism.f[DrugID,])
            DRS <- t(DRS)
            row.names(DRS) <- DrugID
            
            pdf("DMB_mutant_specificity_2.pdf")
            out_DMB_2 <- DMB(DOI, GOI, Pred.d.f_mut[1,], d.mt, DRS, KO.GES, plot = TRUE)
            dev.off()
            print("DMB Output 2:")
            print(out_DMB_2)
        }
        
        # 9. Predict and visualize secondary targets using DTR and plotSim
        if (nrow(Pred.d) > 0) {
            DrugID <- Pred.d\$DrugID[1]
            DRS <- as.data.frame(sec.prism.f[DrugID,])
            DRS <- t(DRS)
            row.names(DRS) <- DrugID
            
            DOI <- Pred.d\$drugName[1]
            GOI <- Pred.d\$MaxTargetName[1]
            pdf("DTR_secondary_target_1.pdf")
            out_DTR_1 <- DTR(DOI, GOI, Pred.d[1,], d.expr, DRS, KO.GES, CutOff = 2)
            dev.off()
            print("DTR Output 1:")
            print(out_DTR_1)
        }
        
        if (length(sim.LowExp) > 0) {
            # Extract low expression strength and p-values
            sim.LowExp.Strength <- vapply(sim.LowExp, function(x) x[,2], FUN.VALUE = numeric(nrow(sim.LowExp[[1]])))
            write.csv(sim.LowExp.Strength, "sim_LowExp_Strength.csv")
            
            sim.LowExp.Pval <- vapply(sim.LowExp, function(x) x[,1], FUN.VALUE = numeric(nrow(sim.LowExp[[1]])))
            write.csv(sim.LowExp.Pval, "sim_LowExp_Pval.csv")
            
            # Plot similarity
            pdf("plotSim_secondary_target.pdf")
            par(mar = c(4, 4, 5, 2), xpd = TRUE, mfrow = c(1, 2))
            plotSim(sim.LowExp.Pval[,1], sim.LowExp.Strength[,1], colorRampPalette(c("lightblue", 'darkblue')), plot = TRUE)
            dev.off()
            
            # Predict secondary target
            best_sec_gene <- rownames(sim.LowExp.Pval)[which.min(sim.LowExp.Pval[,1])]
            DrugID <- names(sim.LowExp)[1]
            pred_idx <- which(Pred.d\$DrugID == DrugID)[1]
            DOI <- Pred.d\$drugName[pred_idx]
            GOI <- best_sec_gene
            
            DRS <- as.data.frame(sec.prism.f[DrugID,])
            DRS <- t(DRS)
            row.names(DRS) <- DrugID
            
            pdf("DTR_secondary_target_2.pdf")
            out_DTR_2 <- DTR(DOI, GOI, Pred.d[pred_idx,], d.expr, DRS, KO.GES, CutOff = 2)
            dev.off()
            print("DTR Output 2:")
            print(out_DTR_2)
        }
        
        # Print session info
        sessionInfo()

    writeLines(c(
        '"BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION":',
        paste0('    DeepTarget: ', as.character(packageVersion('DeepTarget')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_drug_target_prediction_and_characterization.csv versions.yml
    """
}

workflow BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ secondary_prism.csv, avana_CRISPR.csv, mutations_mat.csv, expression_20Q4.csv, DrugMetadata.csv ] ]

    main:
    BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION(ch_input)

    emit:
    tables   = BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION.out.tables
    plots    = BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION.out.plots
    objects  = BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION.out.objects
    versions = BIOC_DEEPTARGET_DRUG_TARGET_PREDICTION_AND_CHARACTERIZATION.out.versions
}
