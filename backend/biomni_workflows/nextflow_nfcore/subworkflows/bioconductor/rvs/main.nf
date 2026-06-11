#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: RVS — single_or_multiple_variant_sharing
// Compute sharing probabilities and p-values for single or multiple rare variants across one or more pedigrees.
// Input: pedigree_data.txt, genotype_data.ped
// Container: quay.io/biocontainers/bioconductor-rvs:1.32.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: RVS, kinship2, snpStats
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Load pedigree structures and genotype data. 2. Calculate sharing probabilities for individual families or multiple families using 

nextflow.enable.dsl = 2

process BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING {
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
    suppressMessages(library(RVS))
    suppressMessages(library(kinship2))
    suppressMessages(library(snpStats))
    
    # ==========================================
    # STAGE 1: Load pedigree structures and genotype data
    # ==========================================
    
    # Read pedigree data from the working directory
    ped_df <- read.table("pedigree_data.txt", header=TRUE, stringsAsFactors=FALSE)
    
    # Convert the pedigree data frame into individual pedigree objects
    fam_ids <- unique(ped_df\$famid)
    ped_list <- list()
    for (fid in fam_ids) {
        sub_df <- ped_df[ped_df\$famid == fid, ]
        dad <- sub_df\$dadid
        dad[dad == 0 | dad == "0"] <- NA
        mom <- sub_df\$momid
        mom[mom == 0 | mom == "0"] <- NA
        
        # Create pedigree object using kinship2
        ped_list[[as.character(fid)]] <- pedigree(
            id = sub_df\$id, 
            dadid = dad, 
            momid = mom, 
            sex = sub_df\$sex, 
            affected = sub_df\$affected, 
            famid = sub_df\$famid
        )
    }
    
    # Read genotype data in LINKAGE format from the working directory
    sample <- snpStats::read.pedfile("genotype_data.ped")
    
    # Match families between pedigree and genotype data
    valid_famids <- intersect(names(ped_list), as.character(unique(sample\$fam\$pedigree)))
    
    # Subset ped_list and sample to valid families
    ped_list <- ped_list[valid_famids]
    keep_idx <- as.character(sample\$fam\$pedigree) %in% valid_famids
    sample\$genotypes <- sample\$genotypes[keep_idx, , drop=FALSE]
    sample\$fam <- sample\$fam[keep_idx, , drop=FALSE]
    
    # ==========================================
    # STAGE 2: Calculate sharing probabilities using RVsharing
    # ==========================================
    
    # Compute sharing probability for a single family
    p <- RVsharing(ped_list[[1]])
    
    # Compute sharing probabilities for all families
    fams <- ped_list
    sharing_probs <- suppressMessages(RVsharing(fams))
    sharing_probs_sig <- signif(sharing_probs, 3)
    
    # Save sharing probabilities to CSV
    write.csv(as.data.frame(sharing_probs), "sharing_probabilities.csv", row.names=TRUE)
    
    # ==========================================
    # STAGE 3: Compute p-value for single variants using multipleFamilyPValue
    # ==========================================
    
    geno_matrix <- as(sample\$genotypes, "numeric")
    var1 <- geno_matrix[, 1]
    
    af <- sum(var1, na.rm=TRUE) / (2 * sum(!is.na(var1)))
    if (!is.na(af) && af > 0.5) {
        carriers <- var1 < 2
    } else {
        carriers <- var1 > 0
    }
    
    sharing_pattern <- sapply(names(sharing_probs), function(fid) {
        idx <- which(as.character(sample\$fam\$pedigree) == fid)
        fam_carriers <- carriers[idx]
        fam_carriers <- fam_carriers[!is.na(fam_carriers)]
        if (length(fam_carriers) == 0) return(FALSE)
        all(fam_carriers)
    })
    names(sharing_pattern) <- names(sharing_probs)
    
    single_p_val <- multipleFamilyPValue(sharing_probs, sharing_pattern)
    
    # Save single variant p-value
    write(single_p_val, file="single_variant_p_value.txt")
    
    # ==========================================
    # STAGE 4: Compute p-values for multiple variants using multipleVariantPValue
    # ==========================================
    
    famids <- unique(sample\$fam\$pedigree)
    fams <- list()
    for (i in seq_along(famids))
    {
        fid <- as.character(famids[i])
        fams[[i]] <- ped_list[[fid]]
        fams[[i]]\$famid <- rep(famids[i], length(fams[[i]]\$id))
    }
    
    sharingProbs <- suppressMessages(RVsharing(fams))
    
    # Compute multiple variant p-values without correction
    result <- multipleVariantPValue(sample\$genotypes, sample\$fam, sharingProbs)
    
    # Compute multiple variant p-values with Bonferroni correction
    result_bonf <- multipleVariantPValue(sample\$genotypes, sample\$fam, sharingProbs, filter='bonferroni', alpha=0.05)
    
    # Save multiple variant results
    write.csv(as.data.frame(result\$pvalues), "multiple_variant_pvalues.csv", row.names=TRUE)
    write.csv(as.data.frame(result_bonf\$pvalues), "multiple_variant_pvalues_bonferroni.csv", row.names=TRUE)
    
    # Save RDS objects of the results
    saveRDS(result, "multiple_variant_results.rds")
    saveRDS(result_bonf, "multiple_variant_results_bonferroni.rds")
    
    # ==========================================
    # STAGE 5: Sensitivity analysis for MAF and kinship coefficients
    # ==========================================
    
    # Set up PDF for sensitivity plots
    pdf("sensitivity_analysis_plots.pdf", width=12, height=6)
    par(mfrow=c(1,2))
    
    num_variants <- min(3, length(result\$pvalues))
    if (num_variants > 0) {
        # 1. Minor Allele Frequency (MAF) Sensitivity Analysis
        freq <- seq(0,0.05,0.005)
        variants <- names(sort(result\$pvalues))[1:num_variants]
        pvals_maf <- matrix(nrow=length(freq), ncol=length(variants))
        pvals_maf[1,] = sort(result\$pvalues)[1:num_variants]
        for (i in 2:length(freq))
        {
            sharingProbs_maf <- suppressMessages(RVsharing(fams, alleleFreq=freq[i]))
            pvals_maf[i,] <- multipleVariantPValue(sample\$genotypes[,variants, drop=FALSE], sample\$fam, sharingProbs_maf)\$pvalues
        }
        colnames(pvals_maf) <- variants
        write.csv(pvals_maf, "maf_sensitivity_pvalues.csv", row.names=TRUE)
        
        # Plot MAF sensitivity
        plot(NULL, xlim=c(min(freq),max(freq)), ylim=c(0,max(pvals_maf, na.rm=TRUE)), type='l',
            xlab="minor allele frequency", ylab="p-value",
            main="Sensitivity of p-value to allele frequency")
        colors <- c("black", "red", "blue")[1:num_variants]
        for (v in 1:num_variants) {
            lines(freq, pvals_maf[,v], col=colors[v])
        }
        legend("topleft", legend=colnames(pvals_maf), col=colors, lty=1)
        
        # 2. Kinship Coefficient Sensitivity Analysis
        kin_coef <- seq(0, 0.05, length=6)
        pvals_kin <- matrix(nrow=length(kin_coef), ncol=length(variants))
        pvals_kin[1,] = sort(result\$pvalues)[1:num_variants]
        for (i in 2:length(kin_coef))
        {
            sharingProbs_kin <- suppressMessages(RVsharing(fams, kinshipCoeff=kin_coef[i]))
            pvals_kin[i,] <- multipleVariantPValue(sample\$genotypes[,variants, drop=FALSE], sample\$fam, sharingProbs_kin)\$pvalues
        }
        colnames(pvals_kin) <- variants
        write.csv(pvals_kin, "kinship_sensitivity_pvalues.csv", row.names=TRUE)
        
        # Plot Kinship sensitivity
        plot(NULL, xlim=c(min(kin_coef), max(kin_coef)), ylim=c(0,max(pvals_kin, na.rm=TRUE)), type='l',
            xlab="kinship coefficient", ylab="p-value",
            main="Sensitivity of p-value to kinship")
        for (v in 1:num_variants) {
            lines(kin_coef, pvals_kin[,v], col=colors[v])
        }
        legend("topleft", legend=colnames(pvals_kin), col=colors, lty=1)
    } else {
        plot(NULL, xlim=c(0,1), ylim=c(0,1), main="No variants available for sensitivity analysis")
    }
    
    dev.off()
    
    # ==========================================
    # STAGE 6: Enrichment test across all variants
    # ==========================================
    
    enrich_p <- enrichmentPValue(sample\$genotypes, sample\$fam, sharingProbs, 0.001)
    write(enrich_p, file="enrichment_p_value.txt")

    writeLines(c(
        '"BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING":',
        paste0('    RVS: ', as.character(packageVersion('RVS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_single_or_multiple_variant_sharing.csv versions.yml
    """
}

workflow BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ pedigree_data.txt, genotype_data.ped ] ]

    main:
    BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING(ch_input)

    emit:
    tables   = BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING.out.tables
    plots    = BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING.out.plots
    objects  = BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING.out.objects
    versions = BIOC_RVS_SINGLE_OR_MULTIPLE_VARIANT_SHARING.out.versions
}
