#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEqMS — maxquant_lfq
// Perform differential protein expression analysis using MaxQuant label-free quantification (LFQ) output.
// Input: proteinGroups.txt
// Container: quay.io/biocontainers/bioconductor-deqms:1.28.0--r45hdfd78af_0
// R packages: DEqMS, limma, matrixStats
// Bioconductor: 3.20 | R: 4.4
// Requires: DEqMS, limma, matrixStats
// Visualizations: box plot
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Input & Preparation] Read and filter out decoy/contaminant matches
//  * 2. [Core Analysis] Extract LFQ intensity columns and filter for missing values
//  * 3. [Core Analysis] Extract unique/razor peptide counts and add a pseudocount of 1
//  * 4. [Core Analysis] Log2 transform intensities
//  * 5. [Input & Preparation] Define design matrix and contrasts
//  * 6. [Core Analysis] Fit linear model using Limma (lmFit, contrasts.fit, eBayes)
//  * 7. [Core Analysis] Assign peptide count to the fit object
//  * 8. [Core Analysis] Run DEqMS variance estimation (spectraCounteBayes)
//  * 9. [Visualization & Output] Extract results (outputResult)

nextflow.enable.dsl = 2

process BIOC_DEQMS_MAXQUANT_LFQ {
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
    .bm_deps <- c("DEqMS", "limma", "matrixStats")
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
    library(DEqMS)
    library(matrixStats)
    library(limma)
    
    # 1. Read and filter out decoy/contaminant matches
    df.prot = read.table("proteinGroups.txt",header=T,sep="\t",stringsAsFactors = F,
                            comment.char = "",quote ="")
    df.prot = df.prot[!df.prot\$Reverse=="+",]
    df.prot = df.prot[!df.prot\$Contaminant=="+",]
    
    # 2. Extract LFQ intensity columns and filter for missing values
    lfq_cols <- grep("^LFQ\\\\.intensity\\\\.", colnames(df.prot))
    df.LFQ = df.prot[, lfq_cols, drop=FALSE]
    df.LFQ[df.LFQ==0] <- NA
    rownames(df.LFQ) = df.prot\$Majority.protein.IDs
    
    # Dynamically infer experimental design from sample names
    sample_names <- sub("^LFQ\\\\.intensity\\\\.", "", colnames(df.prot)[lfq_cols])
    class <- as.factor(gsub("[_\\\\.]?[0-9]+\$", "", sample_names))
    
    # Filter protein table. DEqMS requires a minimum of two values for each group.
    valid_per_group <- sapply(levels(class), function(g) {
      rowSums(!is.na(df.LFQ[, class == g, drop=FALSE]))
    })
    keep_idx <- rowSums(valid_per_group >= 2) == length(levels(class))
    df.LFQ.filter = df.LFQ[keep_idx, , drop=FALSE]
    
    # 3. Extract unique/razor peptide counts and add a pseudocount of 1
    pep_col_names <- paste0("Razor.and.unique.peptides.", sample_names)
    if (!all(pep_col_names %in% colnames(df.prot))) {
      pep_col_names <- paste0("Peptides.", sample_names)
    }
    pep.count.table = data.frame(count = rowMins(as.matrix(df.prot[, pep_col_names, drop=FALSE])),
                                 row.names = df.prot\$Majority.protein.IDs)
    pep.count.table\$count = pep.count.table\$count+1
    
    # 4. Log2 transform intensities
    protein.matrix = log2(as.matrix(df.LFQ.filter))
    
    # 5. Define design matrix and contrasts
    design = model.matrix(~0+class)
    colnames(design) = gsub("class","",colnames(design))
    
    # 6. Fit linear model using Limma
    fit1 = lmFit(protein.matrix,design = design)
    contrast_str <- paste(levels(class)[1], levels(class)[2], sep="-")
    cont <- makeContrasts(contrasts=contrast_str, levels = design)
    fit2 = contrasts.fit(fit1,contrasts = cont)
    fit3 <- eBayes(fit2)
    
    # 7. Assign peptide count to the fit object
    fit3\$count = pep.count.table[rownames(fit3\$coefficients),"count"]
    min(fit3\$count)
    
    # 8. Run DEqMS variance estimation
    fit4 = spectraCounteBayes(fit3)
    
    # Save Variance Boxplot to PDF
    pdf("VarianceBoxplot.pdf", width=8, height=6)
    VarianceBoxplot(fit4, n=20, main = "Label-free dataset PXD000279",
                    xlab="peptide count + 1")
    dev.off()
    
    # 9. Extract results
    DEqMS.results = outputResult(fit4,coef_col = 1)
    
    # Add Gene names to the data frame if Gene.names column exists in the input
    rownames(df.prot) = df.prot\$Majority.protein.IDs
    if ("Gene.names" %in% colnames(df.prot)) {
      DEqMS.results\$Gene.name = df.prot[DEqMS.results\$gene,]\$Gene.names
    }
    
    # Write outputs to files
    out_filename <- paste0(contrast_str, ".DEqMS.results.txt")
    write.table(DEqMS.results, out_filename, sep = "\t",
                row.names = F,quote=F)
    saveRDS(DEqMS.results, "DEqMS_results.rds")

    writeLines(c(
        '"BIOC_DEQMS_MAXQUANT_LFQ":',
        paste0('    DEqMS: ', as.character(packageVersion('DEqMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_maxquant_lfq.csv versions.yml
    """
}

workflow BIOC_DEQMS_MAXQUANT_LFQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ proteinGroups.txt ] ]

    main:
    BIOC_DEQMS_MAXQUANT_LFQ(ch_input)

    emit:
    tables   = BIOC_DEQMS_MAXQUANT_LFQ.out.tables
    plots    = BIOC_DEQMS_MAXQUANT_LFQ.out.plots
    objects  = BIOC_DEQMS_MAXQUANT_LFQ.out.objects
    versions = BIOC_DEQMS_MAXQUANT_LFQ.out.versions
}
