#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: bsseq — standard_wgbs_analysis
// Analyze WGBS data to identify differentially methylated regions (DMRs) using in-memory processing.
// Input: raw_alignment_summaries.txt, sample_metadata.csv
// Container: quay.io/biocontainers/bioconductor-bsseq:1.46.0--r45ha27e39d_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: BiocParallel, S4Vectors, bsseq
// Visualizations: plot (ggplot/base)
// QC: low-count filtering
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Instantiate and order the BSseq object
//  * 2. [Core Analysis] Smooth the methylation profiles using BSmooth
//  * 3. [Core Analysis] Filter out low-coverage loci
//  * 4. [Core Analysis] Compute t-statistics with local correction
//  * 5. [Core Analysis] Identify DMRs by thresholding t-statistics
//  * 6. [Visualization & Output] Plot individual or multiple DMRs

nextflow.enable.dsl = 2

process BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS {
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
        
        library(bsseq)
        library(BiocParallel)
        library(S4Vectors)
        
        # 1. Read User Input Files
        if (!file.exists("sample_metadata.csv")) {
            stop("Required input file 'sample_metadata.csv' not found in the working directory.")
        }
        if (!file.exists("raw_alignment_summaries.txt")) {
            stop("Required input file 'raw_alignment_summaries.txt' not found in the working directory.")
        }
        
        metadata <- read.csv("sample_metadata.csv", stringsAsFactors = FALSE)
        
        # Identify sample ID column
        sample_col <- grep("sample|id", colnames(metadata), ignore.case = TRUE, value = TRUE)
        if (length(sample_col) == 0) {
            sample_names <- metadata[, 1]
            metadata\$Sample <- sample_names
        } else {
            sample_names <- metadata[[sample_col[1]]]
            metadata\$Sample <- sample_names
        }
        
        # Identify Type column
        type_col <- grep("type|group", colnames(metadata), ignore.case = TRUE, value = TRUE)
        if (length(type_col) > 0) {
            metadata\$Type <- metadata[[type_col[1]]]
        } else {
            stop("Metadata must contain a 'Type' or 'Group' column.")
        }
        
        # Read alignment summaries
        align_data <- read.delim("raw_alignment_summaries.txt", header = TRUE, stringsAsFactors = FALSE)
        
        # Identify genomic position columns
        chr_col <- grep("chr|seqname|seq|chromosome", colnames(align_data), ignore.case = TRUE, value = TRUE)[1]
        pos_col <- grep("pos|start|position", colnames(align_data), ignore.case = TRUE, value = TRUE)[1]
        
        if (is.na(chr_col) || is.na(pos_col)) {
            stop("Could not identify chromosome or position columns in 'raw_alignment_summaries.txt'.")
        }
        
        # Extract M and Cov matrices
        M_matrix <- matrix(0, nrow = nrow(align_data), ncol = length(sample_names))
        Cov_matrix <- matrix(0, nrow = nrow(align_data), ncol = length(sample_names))
        colnames(M_matrix) <- sample_names
        colnames(Cov_matrix) <- sample_names
        
        for (i in seq_along(sample_names)) {
            s <- sample_names[i]
            # Look for M column
            m_col <- grep(paste0("^M_", s, "\$|^", s, "_M\$|^M\\\\.", s, "\$|^", s, "\\\\.M\$"), colnames(align_data), ignore.case = TRUE, value = TRUE)
            if (length(m_col) == 0) {
                m_candidates <- grep(s, colnames(align_data), value = TRUE)
                m_col <- grep("M|meth", m_candidates, ignore.case = TRUE, value = TRUE)
            }
            # Look for Cov column
            cov_col <- grep(paste0("^Cov_", s, "\$|^", s, "_Cov\$|^Cov\\\\.", s, "\$|^", s, "\\\\.Cov\$|^coverage_", s, "\$|^", s, "_coverage\$"), colnames(align_data), ignore.case = TRUE, value = TRUE)
            if (length(cov_col) == 0) {
                cov_candidates <- grep(s, colnames(align_data), value = TRUE)
                cov_col <- grep("Cov|cov|depth|read", cov_candidates, ignore.case = TRUE, value = TRUE)
            }
            
            if (length(m_col) > 0) {
                M_matrix[, i] <- as.numeric(align_data[[m_col[1]]])
            } else {
                stop(paste("Could not find Methylation (M) column for sample:", s))
            }
            if (length(cov_col) > 0) {
                Cov_matrix[, i] <- as.numeric(align_data[[cov_col[1]]])
            } else {
                stop(paste("Could not find Coverage (Cov) column for sample:", s))
            }
        }
        
        # Instantiate and order the BSseq object
        BS.cancer.ex <- BSseq(
            chr = align_data[[chr_col]],
            pos = align_data[[pos_col]],
            M = M_matrix,
            Cov = Cov_matrix,
            sampleNames = sample_names
        )
        
        pData(BS.cancer.ex) <- DataFrame(metadata, row.names = sample_names)
        BS.cancer.ex <- orderBSseq(BS.cancer.ex)
        BS.cancer.ex <- updateObject(BS.cancer.ex)
        
        # 2. Smooth the methylation profiles using BSmooth
        BS.cancer.ex.fit <- BSmooth(
            BSseq = BS.cancer.ex,
            BPPARAM = MulticoreParam(workers = 1),
            verbose = TRUE)
        
        # 3. Filter out low-coverage loci
        BS.cov <- getCoverage(BS.cancer.ex.fit)
        
        groups <- unique(BS.cancer.ex\$Type)
        if (length(groups) < 2) {
            stop("At least two distinct groups are required in the 'Type' column.")
        }
        group1_name <- groups[1]
        group2_name <- groups[2]
        
        keepLoci.ex <- which(rowSums(BS.cov[, BS.cancer.ex\$Type == group1_name, drop = FALSE] >= 2) >= 2 &
                             rowSums(BS.cov[, BS.cancer.ex\$Type == group2_name, drop = FALSE] >= 2) >= 2)
        BS.cancer.ex.fit <- BS.cancer.ex.fit[keepLoci.ex,]
        
        # 4. Compute t-statistics with local correction
        group1_samples <- sampleNames(BS.cancer.ex.fit)[BS.cancer.ex.fit\$Type == group1_name]
        group2_samples <- sampleNames(BS.cancer.ex.fit)[BS.cancer.ex.fit\$Type == group2_name]
        
        BS.cancer.ex.tstat <- BSmooth.tstat(BS.cancer.ex.fit, 
                                            group1 = group1_samples,
                                            group2 = group2_samples, 
                                            estimate.var = "same",
                                            local.correct = TRUE,
                                            verbose = TRUE)
        
        # Save t-statistic plot
        pdf(file = "tstat_plot.pdf", width = 6, height = 6)
        plot(BS.cancer.ex.tstat)
        dev.off()
        
        # 5. Identify DMRs by thresholding t-statistics
        dmrs0 <- dmrFinder(BS.cancer.ex.tstat, cutoff = c(-4.6, 4.6))
        dmrs <- subset(dmrs0, n >= 3 & abs(meanDiff) >= 0.1)
        
        # Write DMRs to CSV
        write.csv(dmrs, "identified_dmrs.csv", row.names = FALSE)
        
        # 6. Plot individual or multiple DMRs
        pData <- pData(BS.cancer.ex.fit)
        pData\$col <- ifelse(pData\$Type == group1_name, "red", "blue")
        pData(BS.cancer.ex.fit) <- pData
        
        if (nrow(dmrs) >= 1) {
            pdf(file = "single_dmr_plot.pdf", width = 10, height = 5)
            plotRegion(BS.cancer.ex.fit, dmrs[1,], extend = 5000, addRegions = dmrs)
            dev.off()
            
            pdf(file = "dmrs_top200.pdf", width = 10, height = 5)
            num_plots <- min(200, nrow(dmrs))
            plotManyRegions(BS.cancer.ex.fit, dmrs[1:num_plots,], extend = 5000,
                            addRegions = dmrs)
            dev.off()
        } else {
            message("No DMRs found matching the criteria. Plotting skipped.")
        }
        
        # Save RDS objects for downstream analysis
        saveRDS(BS.cancer.ex.fit, "BS.cancer.ex.fit.rds")
        saveRDS(BS.cancer.ex.tstat, "BS.cancer.ex.tstat.rds")

    writeLines(c(
        '"BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS":',
        paste0('    bsseq: ', as.character(packageVersion('bsseq')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_standard_wgbs_analysis.csv versions.yml
    """
}

workflow BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ raw_alignment_summaries.txt, sample_metadata.csv ] ]

    main:
    BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS.out.tables
    plots    = BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS.out.plots
    objects  = BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS.out.objects
    versions = BIOC_BSSEQ_STANDARD_WGBS_ANALYSIS.out.versions
}
