#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: YAPSA — supervised_signature_analysis
// Perform supervised mutational signature analysis on a cohort of samples using known signatures and signature-specific cutoffs, followed by visualization and sam
// Input: lymphoma_Nature2013_df, BSgenome.Hsapiens.UCSC.hg19
// Container: quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0
// R packages: BSgenome, BSgenome.Hsapiens.UCSC.hg19, ComplexHeatmap, BiocStyle, Biostrings, knitr, YAPSA
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-yapsa:1.36.1--r45hdfd78af_0"

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
    .bm_deps <- c("BSgenome", "BSgenome.Hsapiens.UCSC.hg19", "ComplexHeatmap", "BiocStyle", "Biostrings", "knitr", "YAPSA")
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
    library(YAPSA)
    library(BSgenome)
    library(ComplexHeatmap)
    
    # Define parameters
    word_length <- 3
    
    # 1. Read User Input Files from the Working Directory
    if (file.exists("lymphoma_Nature2013_df.rds")) {
      lymphoma_Nature2013_df <- readRDS("lymphoma_Nature2013_df.rds")
    } else if (file.exists("lymphoma_Nature2013_df.csv")) {
      lymphoma_Nature2013_df <- read.csv("lymphoma_Nature2013_df.csv", stringsAsFactors = FALSE)
    } else {
      stop("Required input file 'lymphoma_Nature2013_df' (RDS or CSV) not found in the working directory.")
    }
    
    if (file.exists("BSgenome.Hsapiens.UCSC.hg19.rds")) {
      BSgenome.Hsapiens.UCSC.hg19 <- readRDS("BSgenome.Hsapiens.UCSC.hg19.rds")
    } else {
      library(BSgenome.Hsapiens.UCSC.hg19)
      BSgenome.Hsapiens.UCSC.hg19 <- BSgenome.Hsapiens.UCSC.hg19::BSgenome.Hsapiens.UCSC.hg19
    }
    
    # Ensure chromosome names have the 'chr' prefix to match hg19 reference genome
    if (!all(grepl("^chr", lymphoma_Nature2013_df\$CHROM))) {
      lymphoma_Nature2013_df\$CHROM <- paste0("chr", lymphoma_Nature2013_df\$CHROM)
      lymphoma_Nature2013_df\$CHROM <- gsub("chrMT", "chrM", lymphoma_Nature2013_df\$CHROM)
    }
    
    # Construct lymphoma_PID_df from the input dataframe to avoid using bundled data()
    lymphoma_PID_df <- unique(lymphoma_Nature2013_df[, c("PID", "SUBGROUP")])
    rownames(lymphoma_PID_df) <- lymphoma_PID_df\$PID
    lymphoma_PID_df <- data.frame(SUBGROUP = lymphoma_PID_df\$SUBGROUP, row.names = lymphoma_PID_df\$PID)
    lymphoma_PID_df\$PID <- rownames(lymphoma_PID_df)
    
    # 2. Load Known Signatures and Optimal Cutoffs directly from package namespace (avoiding data() calls)
    current_sig_df <- YAPSA::AlexCosmicValid_sig_df
    current_sigInd_df <- YAPSA::AlexCosmicValid_sigInd_df
    current_cutoff_df <- YAPSA::cutoffCosmicValid_abs_df
    current_cost_factor <- 6
    current_cutoff_vector <- current_cutoff_df[current_cost_factor,]
    
    # 3. Build the Mutational Catalogue
    lymphomaNature2013_mutCat_list <- create_mutation_catalogue_from_df(
      lymphoma_Nature2013_df, this_seqnames.field = "CHROM",
      this_start.field = "POS", this_end.field = "POS",
      this_PID.field = "PID", this_subgroup.field = "SUBGROUP",
      this_refGenome = BSgenome.Hsapiens.UCSC.hg19, this_wordLength = word_length)
    lymphomaNature2013_mutCat_df <- as.data.frame(
      lymphomaNature2013_mutCat_list\$matrix)
    
    # 4. Run Supervised Linear Combination Decomposition (LCD) with Signature-Specific Cutoffs
    lymphoma_COSMIC_listsList <- LCD_complex_cutoff_combined(
      in_mutation_catalogue_df = lymphomaNature2013_mutCat_df,
      in_cutoff_vector = current_cutoff_vector,
      in_signatures_df = current_sig_df,
      in_sig_ind_df = current_sigInd_df)
    
    # 5. Annotate Sample Subgroups
    COSMIC_subgroups_df <- make_subgroups_df(lymphoma_PID_df, lymphoma_COSMIC_listsList\$cohort\$exposures)
    result_cohort <- lymphoma_COSMIC_listsList\$cohort
    
    # Map cohort results to the variable name expected by the documented heatmap call
    CosmicValid_cutoffGen_LCDlist <- lymphoma_COSMIC_listsList\$cohort
    
    # 6. Visualization and Clustering
    # Save absolute and relative signature exposures barplot
    pdf("exposures_barplot.pdf", width = 12, height = 8)
    exposures_barplot(
      in_exposures_df = result_cohort\$exposures,
      in_signatures_ind_df = result_cohort\$out_sig_ind_df,
      in_subgroups_df = COSMIC_subgroups_df)
    dev.off()
    
    # Save sample clustering heatmap
    pdf("exposures_heatmap.pdf", width = 10, height = 8)
    complex_heatmap_exposures(
      CosmicValid_cutoffGen_LCDlist\$norm_exposures, 
      COSMIC_subgroups_df, 
      CosmicValid_cutoffGen_LCDlist\$out_sig_ind_df, 
      in_data_type="norm exposures", 
      in_subgroup_colour_column="col", 
      in_method="manhattan", 
      in_subgroup_column="subgroup")
    dev.off()
    
    # 7. Write Output Tables and Objects
    write.csv(lymphomaNature2013_mutCat_df, "lymphomaNature2013_mutCat_df.csv", row.names = TRUE)
    write.csv(result_cohort\$exposures, "COSMIC_absolute_exposures.csv", row.names = TRUE)
    write.csv(result_cohort\$norm_exposures, "COSMIC_relative_exposures.csv", row.names = TRUE)
    saveRDS(lymphoma_COSMIC_listsList, "lymphoma_COSMIC_listsList.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS":
        YAPSA: \$(Rscript -e 'cat(as.character(packageVersion("YAPSA")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_supervised_signature_analysis.csv versions.yml
    """
}

workflow BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ lymphoma_Nature2013_df, BSgenome.Hsapiens.UCSC.hg19 ] ]

    main:
    BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS.out.tables
    plots    = BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS.out.plots
    objects  = BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS.out.objects
    versions = BIOC_YAPSA_SUPERVISED_SIGNATURE_ANALYSIS.out.versions
}
