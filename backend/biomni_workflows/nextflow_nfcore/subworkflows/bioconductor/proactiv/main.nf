#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: proactiv — alternative_promoter_analysis
// Quantify promoter activity and identify alternative promoter usage across conditions from RNA-Seq junction or BAM files.
// Input: files, gtf.file
// Container: quay.io/biocontainers/bioconductor-proactiv:1.20.0--r45hdfd78af_0
// R packages: AnnotationDbi, dplyr, ggplot2, gridExtra, proActiv, Rtsne
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-proactiv:1.20.0--r45hdfd78af_0"

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
    .bm_deps <- c("AnnotationDbi", "dplyr", "ggplot2", "gridExtra", "proActiv", "Rtsne")
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
    library(proActiv)
    library(AnnotationDbi)
    library(ggplot2)
    library(dplyr)
    library(gridExtra)
    library(Rtsne)
    
    message("Starting proActiv alternative promoter analysis pipeline...")
    
    # ==========================================
    # 1. Prepare Promoter Annotations
    # ==========================================
    
    # Search for GTF or TxDb files in the current working directory
    gtf_files <- list.files(pattern = "\\\\.gtf(\\\\.gz)?\$", full.names = TRUE)
    txdb_files <- list.files(pattern = "\\\\.(sqlite|db)\$", full.names = TRUE)
    
    promoterAnnotation <- NULL
    
    if (length(txdb_files) > 0) {
      txdb.file <- txdb_files[1]
      message("Found TxDb file: ", txdb.file)
      message("Loading TxDb database...")
      txdb <- loadDb(txdb.file)
      message("Preparing promoter annotation from TxDb...")
      promoterAnnotation <- preparePromoterAnnotation(txdb = txdb,
                                                     species = 'Homo_sapiens')
    } else if (length(gtf_files) > 0) {
      gtf.file <- gtf_files[1]
      message("Found GTF file: ", gtf.file)
      message("Preparing promoter annotation from GTF...")
      promoterAnnotation <- preparePromoterAnnotation(file = gtf.file,
                                                     species = 'Homo_sapiens')
    } else {
      stop("Error: No GTF file (*.gtf, *.gtf.gz) or TxDb file (*.sqlite, *.db) found in the working directory.")
    }
    
    # ==========================================
    # 2. Quantify Promoter Activity
    # ==========================================
    
    # Search for STAR/TopHat2 junction files or BAM files in the working directory
    files <- list.files(pattern = "(\\\\.SJ\\\\.out\\\\.tab|\\\\.SJ\\\\.out\\\\.tab\\\\.gz|\\\\.bam)\$", full.names = TRUE)
    
    if (length(files) == 0) {
      stop("Error: No input junction or BAM files (*.SJ.out.tab, *.SJ.out.tab.gz, *.bam) found in the working directory.")
    }
    
    message("Found ", length(files), " input file(s) for quantification:")
    print(files)
    
    # Dynamically determine experimental conditions based on file names or split them
    condition <- rep("Condition1", length(files))
    if (any(grepl("A549", files, ignore.case = TRUE))) {
      condition[grepl("A549", files, ignore.case = TRUE)] <- "A549"
    }
    if (any(grepl("HepG2", files, ignore.case = TRUE))) {
      condition[grepl("HepG2", files, ignore.case = TRUE)] <- "HepG2"
    }
    
    # Fallback: If no specific conditions are detected and we have multiple files, split them into two groups
    if (length(unique(condition)) == 1 && length(files) >= 2) {
      condition <- rep(c("Condition1", "Condition2"), length.out = length(files))
    }
    
    message("Assigned conditions: ", paste(condition, collapse = ", "))
    
    # Run proActiv promoter quantification
    message("Running proActiv quantification...")
    result <- proActiv(files = files, 
                       promoterAnnotation = promoterAnnotation,
                       condition = condition)
    
    # Save raw result object
    saveRDS(result, "proactiv_raw_result.rds")
    
    # ==========================================
    # 3. Filter Single-Exon Transcripts
    # ==========================================
    message("Filtering out single-exon transcripts/promoters with NA counts...")
    result <- result[complete.cases(assays(result)\$promoterCounts),]
    
    # Save filtered result object
    saveRDS(result, "proactiv_filtered_result.rds")
    
    # ==========================================
    # 4. Identify Alternative Promoters
    # ==========================================
    referenceCondition <- unique(condition)[1]
    message("Identifying alternative promoters using reference condition: ", referenceCondition)
    
    alternativePromoters <- getAlternativePromoters(result = result, 
                                                   referenceCondition = referenceCondition)
    
    # Save alternative promoters object
    saveRDS(alternativePromoters, "alternative_promoters.rds")
    
    # Export alternative promoters to CSV tables if detected
    if (!is.null(alternativePromoters)) {
      if (!is.null(alternativePromoters\$upReg) && nrow(alternativePromoters\$upReg) > 0) {
        write.csv(alternativePromoters\$upReg, "alternative_promoters_upregulated.csv", row.names = FALSE)
        message("Upregulated alternative promoters saved to 'alternative_promoters_upregulated.csv'")
      }
      if (!is.null(alternativePromoters\$downReg) && nrow(alternativePromoters\$downReg) > 0) {
        write.csv(alternativePromoters\$downReg, "alternative_promoters_downregulated.csv", row.names = FALSE)
        message("Downregulated alternative promoters saved to 'alternative_promoters_downregulated.csv'")
      }
    }
    
    # ==========================================
    # 5. Visualization
    # ==========================================
    message("Generating visualization plots...")
    
    # Determine a gene of interest to plot
    gene_to_plot <- NULL
    if (!is.null(alternativePromoters)) {
      all_alt_genes <- unique(c(alternativePromoters\$upReg\$geneId, alternativePromoters\$downReg\$geneId))
      if (length(all_alt_genes) > 0 && !all(is.na(all_alt_genes))) {
        gene_to_plot <- all_alt_genes[1]
      }
    }
    if (is.null(gene_to_plot)) {
      rdata <- rowData(result)
      if (nrow(rdata) > 0) {
        gene_to_plot <- rdata\$geneId[1]
      }
    }
    
    # 5.1 Boxplot of Promoter Activity and Gene Expression
    if (!is.null(gene_to_plot)) {
      message("Plotting promoter activity for gene: ", gene_to_plot)
      plots <- boxplotPromoters(result, gene_to_plot)
      
      pdf("boxplot_promoters.pdf", width = 10, height = 6)
      grid.arrange(plots[[1]], plots[[3]], nrow = 1, ncol = 2, widths = c(3, 2))
      dev.off()
      message("Boxplot saved to 'boxplot_promoters.pdf'")
    }
    
    # 5.2 Promoter Category Proportion
    rdata <- rowData(result)
    unique_conditions <- unique(condition)
    pdata1_list <- list()
    
    for (cond in unique_conditions) {
      class_col <- paste0(cond, ".class")
      if (class_col %in% colnames(rdata)) {
        pdata1_list[[cond]] <- data.frame(
          cellLine = cond,
          promoterClass = as.factor(rdata[[class_col]])
        )
      }
    }
    
    if (length(pdata1_list) > 0) {
      pdata1 <- do.call(rbind, pdata1_list)
      p1 <- ggplot(na.omit(pdata1)) +
        geom_bar(aes(x = cellLine, fill = promoterClass)) + 
        xlab('Conditions') + ylab('Count') + labs(fill = 'Promoter Category') +
        ggtitle('Categorization of Promoters')
      
      ggsave("promoter_categories.pdf", plot = p1, width = 6, height = 5)
      message("Promoter category plot saved to 'promoter_categories.pdf'")
    }
    
    # 5.3 Major/Minor Promoters by Position
    target_cond <- if (length(unique_conditions) >= 2) unique_conditions[2] else unique_conditions[1]
    class_col <- paste0(target_cond, ".class")
    
    if (class_col %in% colnames(rdata) && "promoterPosition" %in% colnames(rdata)) {
      pdata2 <- as_tibble(rdata) %>%
        mutate(promoterPosition = ifelse(promoterPosition > 5, 5, promoterPosition)) %>%
        filter(!!sym(class_col) %in% c('Major', 'Minor'))
      
      if (nrow(pdata2) > 0) {
        p2 <- ggplot(pdata2) +
          geom_bar(aes(x = promoterPosition, fill = as.factor(!!sym(class_col))), position = 'fill') +
          xlab(expression(Promoter ~ Position ~ "5'" %->% "3'")) + ylab('Percentage') + 
          labs(fill = 'Promoter Category') + ggtitle(paste('Major/Minor Promoter Proportion in', target_cond)) + 
          scale_y_continuous(breaks = seq(0, 1, 0.25), labels = paste0(seq(0, 100, 25), '%')) +
          scale_x_continuous(breaks = seq(1, 5), labels = c('1', '2', '3', '4', '>=5'))
        
        ggsave("major_minor_proportion.pdf", plot = p2, width = 6, height = 5)
        message("Major/minor promoter proportion plot saved to 'major_minor_proportion.pdf'")
      }
    }
    
    # 5.4 Major Promoter Activity and Gene Expression
    mean_col <- paste0(target_cond, ".mean")
    gene_mean_col <- paste0(target_cond, ".gene.mean")
    
    if (all(c(class_col, mean_col, gene_mean_col) %in% colnames(rdata))) {
      majorPromoter <- as_tibble(rdata) %>% 
        group_by(geneId) %>% 
        mutate(promoterCount = n()) %>% 
        filter(!!sym(class_col) == 'Major') 
      
      if (nrow(majorPromoter) > 0) {
        pdata3 <- data.frame(proActiv = majorPromoter[[mean_col]],
                             geneExp = majorPromoter[[gene_mean_col]],
                             promoterCount = majorPromoter\$promoterCount)
        
        p3 <- ggplot(pdata3, aes(x = geneExp, y = proActiv)) + 
          geom_point(aes(colour = promoterCount), alpha = 0.5) +
          ggtitle(paste('Major Promoter Activity vs. Gene Expression in', target_cond)) + 
          xlab('Average Gene Expression') + ylab('Average Major Promoter Activity') +
          labs(colour = 'Number of \n Annotated Promoters') +
          geom_abline(slope = 1, intercept = 0, colour = 'red', linetype = 'dashed')
        
        ggsave("major_promoter_vs_gene_exp.pdf", plot = p3, width = 7, height = 5)
        message("Major promoter vs gene expression plot saved to 'major_promoter_vs_gene_exp.pdf'")
      }
    }
    
    # 5.5 t-SNE Plot
    abs_activity <- assays(result)\$absolutePromoterActivity
    if (!is.null(abs_activity) && nrow(abs_activity) > 0) {
      data_tsne <- abs_activity[rowSums(abs_activity) > 0, , drop = FALSE]
      if (nrow(data_tsne) > ncol(data_tsne)) {
        data_tsne <- data.frame(t(data_tsne))
        data_tsne\$Sample <- as.factor(condition)
        
        perp <- min(1, floor((nrow(data_tsne) - 1) / 3))
        if (perp >= 1) {
          set.seed(40)
          tsne.out <- Rtsne(as.matrix(subset(data_tsne, select = -c(Sample))), perplexity = perp)
          
          pdf("tsne_plot.pdf", width = 6, height = 6)
          plot(x = tsne.out\$Y[, 1], y = tsne.out\$Y[, 2], bg = data_tsne\$Sample, asp = 1,
               col = 'black', pch = 24, cex = 4,
               main = 't-SNE plot with active promoters',
               xlab = 'T-SNE1', ylab = 'T-SNE2')
          legend('topright', inset = .02, title = 'Conditions',
                 legend = unique(condition), pch = 24, pt.bg = 1:length(unique(condition)), cex = 1.2, bty = 'n')
          dev.off()
          message("t-SNE plot saved to 'tsne_plot.pdf'")
        }
      }
    }
    
    message("Pipeline completed successfully!")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS":
        proactiv: \$(Rscript -e 'cat(as.character(packageVersion("proactiv")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_alternative_promoter_analysis.csv versions.yml
    """
}

workflow BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ files, gtf.file ] ]

    main:
    BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS.out.tables
    plots    = BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS.out.plots
    objects  = BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS.out.objects
    versions = BIOC_PROACTIV_ALTERNATIVE_PROMOTER_ANALYSIS.out.versions
}
