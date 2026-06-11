#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: qPLEXanalyzer — qplex_quantitative_proteomics
// Perform a comprehensive quantitative proteomics analysis of TMT data, including quality control, normalization, peptide-to-protein aggregation, optional regress
// Input: intensity.csv, coldata.csv
// Container: 1.28.2--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: MSnbase, limma, qPLEXanalyzer
// Visualizations: volcano plot
// QC: missing-value handling
// Generated from full documentation (real input-consuming pipeline).
// ============================================================

nextflow.enable.dsl = 2

process BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS {
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
    .bm_deps <- c("qPLEXanalyzer", "MSnbase", "limma")
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
    library(qPLEXanalyzer)
    library(MSnbase)
    library(limma)
    
    # ---------------------------------------------------------
    # --- Load and Preprocess Input Data ---
    # ---------------------------------------------------------
    
    # Read input files
    if (!file.exists("intensity.csv") || !file.exists("coldata.csv")) {
        stop("Required input files 'intensity.csv' and/or 'coldata.csv' are missing.")
    }
    
    intensities <- read.csv("intensity.csv", check.names = FALSE, stringsAsFactors = FALSE)
    coldata <- read.csv("coldata.csv", check.names = FALSE, stringsAsFactors = FALSE)
    
    # Ensure feature_id column is present
    if (!"feature_id" %in% colnames(intensities)) {
        colnames(intensities)[1] <- "feature_id"
    }
    
    # Synthesize Sequences and Accessions columns required by qPLEXanalyzer
    intensities\$Sequences <- intensities\$feature_id
    intensities\$Accessions <- intensities\$feature_id
    
    # Align intensity columns with coldata samples
    common_samples <- intersect(coldata\$sample, colnames(intensities))
    if (length(common_samples) == 0) {
        stop("No matching samples found between intensity.csv and coldata.csv")
    }
    
    metadata <- coldata[coldata\$sample %in% common_samples, ]
    colnames(metadata)[colnames(metadata) == "sample"] <- "SampleName"
    colnames(metadata)[colnames(metadata) == "condition"] <- "SampleGroup"
    
    # Reorder intensities to place sample columns at the end
    feature_cols <- c("feature_id", "Sequences", "Accessions")
    intensities_clean <- intensities[, c(feature_cols, metadata\$SampleName)]
    indExpData <- 4:ncol(intensities_clean)
    
    # Remove rows with missing values in intensity columns to satisfy qPLEXanalyzer requirements
    intensities_clean <- intensities_clean[complete.cases(intensities_clean[, indExpData]), ]
    
    # Convert to MSnset object
    MSnset_data <- convertToMSnset(intensities_clean,
                                   metadata = metadata,
                                   indExpData = indExpData,
                                   Sequences = "Sequences",
                                   Accessions = "Accessions")
    
    # Add a small constant to avoid log of zero or negative values
    exprs(MSnset_data) <- exprs(MSnset_data) + 1.01
    
    # ---------------------------------------------------------
    # --- Quality Control Visualizations ---
    # ---------------------------------------------------------
    
    pdf("qc_plots.pdf", width = 8, height = 6)
    
    message("Generating QC plots...")
    try(print(intensityPlot(MSnset_data, title = "Peptide Intensity Distribution")))
    try(print(intensityBoxplot(MSnset_data, title = "Peptide Intensity Boxplot")))
    try(print(rliPlot(MSnset_data, title = "Relative Peptide Intensity")))
    try(print(corrPlot(MSnset_data)))
    try(print(hierarchicalPlot(MSnset_data)))
    try(print(pcaPlot(MSnset_data, labelColumn = "SampleGroup", pointsize = 3)))
    
    dev.off()
    
    # ---------------------------------------------------------
    # --- Data Normalization ---
    # ---------------------------------------------------------
    
    message("Normalizing data...")
    # Use groupScaling if multiple groups exist, otherwise fallback to standard scaling
    if (length(unique(metadata\$SampleGroup)) > 1) {
        MSnset_norm <- groupScaling(MSnset_data, 
                                    scalingFunction = median, 
                                    groupingColumn = "SampleGroup")
    } else {
        MSnset_norm <- normalizeScaling(MSnset_data, 
                                        scalingFunction = median)
    }
    
    # ---------------------------------------------------------
    # --- Aggregation of Peptides to Proteins ---
    # ---------------------------------------------------------
    
    message("Aggregating peptide intensities to protein level...")
    # Create a matching annotation data frame
    annotation <- data.frame(
        Accessions = unique(intensities_clean\$Accessions),
        GeneSymbol = unique(intensities_clean\$Accessions),
        Gene = unique(intensities_clean\$Accessions),
        Description = unique(intensities_clean\$Accessions),
        stringsAsFactors = FALSE
    )
    
    MSnset_Pnorm <- summarizeIntensities(MSnset_norm,
                                         summarizationFunction = sum,
                                         annotation = annotation)
    
    # Plot peptide vs protein intensity for a representative protein
    first_protein_id <- fData(MSnset_data)\$Accessions[1]
    pdf("peptide_intensity_plot.pdf", width = 8, height = 6)
    try(peptideIntensityPlot(MSnset_data,
                             combinedIntensities = MSnset_Pnorm,
                             ProteinID = first_protein_id,
                             ProteinName = first_protein_id))
    dev.off()
    
    # ---------------------------------------------------------
    # --- Optional Regression Analysis (for qPLEX-RIME) ---
    # ---------------------------------------------------------
    
    if ("IgG" %in% pData(MSnset_Pnorm)\$SampleGroup) {
        message("IgG control detected. Performing regression analysis...")
        IgG_ind <- which(pData(MSnset_Pnorm)\$SampleGroup == "IgG")
        dummy_bait <- fData(MSnset_Pnorm)\$Accessions[1]
        
        pdf("regression_plot.pdf", width = 8, height = 6)
        try({
            Reg_data <- regressIntensity(MSnset_Pnorm,
                                         controlInd = IgG_ind,
                                         ProteinId = dummy_bait)
        })
        dev.off()
    }
    
    # ---------------------------------------------------------
    # --- Differential Statistical Analysis ---
    # ---------------------------------------------------------
    
    message("Performing differential statistical analysis...")
    groups <- unique(pData(MSnset_Pnorm)\$SampleGroup)
    groups_no_igg <- groups[groups != "IgG"]
    
    if (length(groups_no_igg) >= 2) {
        # Define contrast between the first two non-IgG groups
        contrast_name <- paste0(groups_no_igg[1], "_vs_", groups_no_igg[2])
        contrast_formula <- paste0(groups_no_igg[1], " - ", groups_no_igg[2])
        contrasts <- setNames(contrast_formula, contrast_name)
    
        diffstats <- computeDiffStats(MSnset_Pnorm, contrasts = contrasts)
    
        # Extract results, adjusting for IgG control if present
        if ("IgG" %in% groups) {
            diffexp <- getContrastResults(diffstats, contrast = contrast_name, controlGroup = "IgG")
        } else {
            diffexp <- getContrastResults(diffstats, contrast = contrast_name)
        }
    
        # Save results
        write.csv(diffexp, "differential_results.csv", row.names = FALSE)
    
        # Generate MA and Volcano plots
        pdf("ma_volcano_plots.pdf", width = 8, height = 6)
        try(maVolPlot(diffstats, contrast = contrast_name, plotType = "MA", title = contrast_formula))
        try(maVolPlot(diffstats, contrast = contrast_name, plotType = "Volcano", title = contrast_formula))
        dev.off()
        
        message("Analysis complete. Outputs written successfully.")
    } else {
        warning("At least two non-IgG groups are required for differential analysis. Skipping differential testing.")
        write.csv(data.frame(Message = "At least two non-IgG groups are required for differential analysis."),
                  "differential_results.csv", row.names = FALSE)
        
        pdf("ma_volcano_plots.pdf", width = 8, height = 6)
        plot(0, type='n', axes=FALSE, ann=FALSE)
        text(1, 1, "Not enough groups for differential analysis", cex=1.2)
        dev.off()
    }

    writeLines(c(
        '"BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS":',
        paste0('    qPLEXanalyzer: ', as.character(packageVersion('qPLEXanalyzer')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_qplex_quantitative_proteomics.csv versions.yml
    """
}

workflow BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ input files ] ]

    main:
    BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS(ch_input)

    emit:
    tables   = BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS.out.tables
    plots    = BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS.out.plots
    objects  = BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS.out.objects
    versions = BIOC_QPLEXANALYZER_QPLEX_QUANTITATIVE_PROTEOMICS.out.versions
}
