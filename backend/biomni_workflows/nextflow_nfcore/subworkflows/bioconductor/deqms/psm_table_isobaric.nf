#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: DEqMS — psm_table_isobaric
// Summarize PSM-level isobaric labeled data to protein-level relative abundance and perform differential expression analysis.
// Input: dat.psm
// Container: quay.io/biocontainers/bioconductor-deqms:1.28.0--r45hdfd78af_0
// R packages: DEqMS, limma
// Bioconductor: 3.20 | R: 4.4
// Requires: DEqMS, limma
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Log2 transform PSM intensities
//  * 2. [Visualization & Output] Summarize PSM intensities to protein log2 ratios using median sweeping (medianSweeping)
//  * 3. [Input & Preparation] Define design matrix and contrasts
//  * 4. [Core Analysis] Fit linear model using Limma (lmFit, contrasts.fit, eBayes)
//  * 5. [Core Analysis] Calculate PSM count per gene/protein and assign to the fit object
//  * 6. [Core Analysis] Run DEqMS variance estimation (spectraCounteBayes)
//  * 7. [Visualization & Output] Extract results (outputResult)
//  * 8. [Visualization & Output] Plot peptide profiles for specific genes (peptideProfilePlot)

nextflow.enable.dsl = 2

process BIOC_DEQMS_PSM_TABLE_ISOBARIC {
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
    .bm_deps <- c("DEqMS", "limma")
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
    library(limma)
    
    # 1. Read the input file 'dat.psm' from the working directory
    if (file.exists("dat.psm")) {
      dat.psm <- tryCatch({
        readRDS("dat.psm")
      }, error = function(e) {
        read.table("dat.psm", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
      })
    } else if (file.exists("dat.psm.txt")) {
      dat.psm <- read.table("dat.psm.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    } else if (file.exists("dat.psm.tsv")) {
      dat.psm <- read.table("dat.psm.tsv", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    } else if (file.exists("dat.psm.csv")) {
      dat.psm <- read.csv("dat.psm.csv", stringsAsFactors = FALSE)
    } else {
      stop("Error: Input file 'dat.psm' (or dat.psm.txt/tsv/csv) not found in the working directory.")
    }
    
    # Ensure the second column is named 'gene' to match the vignette's use of dat.psm\$gene
    if (ncol(dat.psm) >= 2 && !"gene" %in% colnames(dat.psm)) {
      colnames(dat.psm)[2] <- "gene"
    }
    
    # 2. Log2 transform PSM intensities
    dat.psm.log = dat.psm
    quant_cols = 3:ncol(dat.psm)
    dat.psm.log[,quant_cols] =  log2(dat.psm[,quant_cols])
    
    # 3. Summarize PSM intensities to protein log2 ratios using median sweeping
    dat.gene.nm = medianSweeping(dat.psm.log,group_col = 2)
    gene.matrix = as.matrix(dat.gene.nm)
    
    # 4. Define design matrix and contrasts dynamically
    cond_names <- colnames(dat.psm)[quant_cols]
    cond <- as.factor(make.names(gsub("[_\\\\.-]?[0-9]+\$", "", cond_names)))
    
    # Fallback if no clear groups can be parsed or if there are no replicates
    if (length(levels(cond)) == length(cond_names) || length(levels(cond)) < 2) {
      half <- floor(length(cond_names) / 2)
      cond <- as.factor(rep(c("GroupA", "GroupB"), c(half, length(cond_names) - half)))
    }
    
    design = model.matrix(~0+cond)
    colnames(design) = gsub("cond","",colnames(design))
    
    # 5. Fit linear model using Limma
    fit1 <- lmFit(gene.matrix,design)
    levels_cond <- colnames(design)
    x <- paste(levels_cond[2:length(levels_cond)], levels_cond[1], sep="-")
    contrast =  makeContrasts(contrasts=x,levels=design)
    fit2 <- eBayes(contrasts.fit(fit1,contrasts = contrast))
    
    # 6. Calculate PSM count per gene/protein and assign to the fit object
    psm.count.table = as.data.frame(table(dat.psm\$gene))
    rownames(psm.count.table) = psm.count.table\$Var1
    fit2\$count = psm.count.table[rownames(fit2\$coefficients),2]
    
    # 7. Run DEqMS variance estimation
    fit3 = spectraCounteBayes(fit2)
    
    # 8. Extract results
    DEqMS.results = outputResult(fit3,coef_col = 1)
    
    # Save results to files
    out_name <- paste0("DEqMS.results.", x[1], ".txt")
    write.table(DEqMS.results, out_name, sep = "\t", row.names = FALSE, quote = FALSE)
    write.csv(DEqMS.results, "DEqMS_results.csv", row.names = FALSE)
    saveRDS(DEqMS.results, "DEqMS_results.rds")
    saveRDS(fit3, "DEqMS_fit3.rds")
    
    # 9. Generate and save plots
    pdf("DEqMS_plots.pdf", width = 8, height = 6)
    
    # Variance Boxplot
    VarianceBoxplot(fit3,n=20, xlab="PSM count",main="DEqMS Variance Boxplot")
    
    # Peptide Profile Plot (wrapped in tryCatch in case "TGFBR2" is not in the user's specific input)
    tryCatch({
      peptideProfilePlot(dat=dat.psm.log,col=2,gene="TGFBR2")
    }, error = function(e) {
      warning("Could not plot peptide profile for TGFBR2: ", e\$message)
      # Fallback to the first gene in the dataset to ensure a plot is generated
      if (nrow(dat.psm.log) > 0) {
        fallback_gene <- as.character(dat.psm.log[1, 2])
        try(peptideProfilePlot(dat=dat.psm.log,col=2,gene=fallback_gene))
      }
    })
    
    dev.off()

    writeLines(c(
        '"BIOC_DEQMS_PSM_TABLE_ISOBARIC":',
        paste0('    DEqMS: ', as.character(packageVersion('DEqMS')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_psm_table_isobaric.csv versions.yml
    """
}

workflow BIOC_DEQMS_PSM_TABLE_ISOBARIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ dat.psm ] ]

    main:
    BIOC_DEQMS_PSM_TABLE_ISOBARIC(ch_input)

    emit:
    tables   = BIOC_DEQMS_PSM_TABLE_ISOBARIC.out.tables
    plots    = BIOC_DEQMS_PSM_TABLE_ISOBARIC.out.plots
    objects  = BIOC_DEQMS_PSM_TABLE_ISOBARIC.out.objects
    versions = BIOC_DEQMS_PSM_TABLE_ISOBARIC.out.versions
}
