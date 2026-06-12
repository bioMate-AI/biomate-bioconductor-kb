#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splatter — splatpop_population_simulation
// Simulate population-scale single-cell RNA-seq count data incorporating genotype structure and eQTL effects.
// Input: vcf, gff
// Container: quay.io/biocontainers/bioconductor-splatter:1.34.0--r45hdfd78af_0
// R packages: SingleCellExperiment, VariantAnnotation, rtracklayer, splatter
// Bioconductor: 3.20 | R: 4.4
// Requires: SingleCellExperiment, VariantAnnotation, rtracklayer, splatter
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Initialize population parameters using newSplatPopParams
//  * 2. [Core Analysis] Simulate population gene means using splatPopSimulateMeans
//  * 3. [Core Analysis] Simulate single-cell counts for the population using

nextflow.enable.dsl = 2

process BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION {
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
    .bm_deps <- c("SingleCellExperiment", "VariantAnnotation", "rtracklayer", "splatter")
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
            library(splatter)
            library(VariantAnnotation)
            library(rtracklayer)
            
            # ==========================================
            # 1. Read User Input Files
            # ==========================================
            
            # Find and read VCF input
            vcf <- NULL
            if (file.exists("vcf.rds")) {
                vcf <- readRDS("vcf.rds")
            } else {
                vcf_files <- list.files(pattern = "\\\\.vcf(\\\\.gz)?\$", ignore.case = TRUE)
                if (length(vcf_files) > 0) {
                    vcf <- VariantAnnotation::readVcf(vcf_files[1], genome = "unknown")
                }
            }
            if (is.null(vcf)) {
                stop("Error: Could not find VCF input file (vcf.rds or *.vcf/*.vcf.gz) in the working directory.")
            }
            
            # Find and read GFF input
            gff <- NULL
            if (file.exists("gff.rds")) {
                gff <- readRDS("gff.rds")
            } else {
                gff_files <- list.files(pattern = "\\\\.(gff|gtf|gff3)(\\\\.gz)?\$", ignore.case = TRUE)
                if (length(gff_files) > 0) {
                    gff_df <- rtracklayer::readGFF(gff_files[1])
                    # Map standard GFF columns to the format expected by splatPop
                    gff <- data.frame(
                        chromosome = as.character(gff_df\$seqid),
                        gene = as.character(gff_df\$gene_id),
                        start = as.integer(gff_df\$start),
                        end = as.integer(gff_df\$end),
                        stringsAsFactors = FALSE
                    )
                    # Fallback if gene_id is not populated but ID is
                    if (all(is.na(gff\$gene)) && "ID" %in% colnames(gff_df)) {
                        gff\$gene <- as.character(gff_df\$ID)
                    }
                    # Remove rows with missing essential annotations
                    gff <- gff[!is.na(gff\$gene) & !is.na(gff\$chromosome), ]
                } else {
                    # Check if GFF is provided as a CSV/TSV table
                    tbl_files <- list.files(pattern = "\\\\.(csv|tsv|txt)\$", ignore.case = TRUE)
                    for (f in tbl_files) {
                        tmp <- tryCatch(
                            read.delim(f, sep = if(grepl("\\\\.csv\$", f)) "," else "\t", header = TRUE),
                            error = function(e) NULL
                        )
                        if (!is.null(tmp) && all(c("chromosome", "gene", "start", "end") %in% colnames(tmp))) {
                            gff <- tmp
                            break
                        }
                    }
                }
            }
            if (is.null(gff)) {
                stop("Error: Could not find GFF input file (gff.rds, *.gff, or a compatible CSV/TSV) in the working directory.")
            }
            
            # Ensure GFF is a data.frame
            gff <- as.data.frame(gff)
            
            # ==========================================
            # 2. Run Workflow Stages
            # ==========================================
            
            # --- Initialize population parameters using newSplatPopParams ---
            params <- newSplatPopParams()
            
            # --- Simulate population gene means using splatPopSimulateMeans ---
            sim_means <- splatPopSimulateMeans(vcf = vcf, gff = gff, params = params)
            
            # --- Simulate single-cell counts for the population using ---
            sim_sc <- splatPopSimulateSC(sim_means, params)
            
            # Run the exact documented wrapper function call
            sim <- splatPopSimulate(vcf = vcf, gff = gff, sparsify = FALSE)
            
            # ==========================================
            # 3. Save Outputs and Results
            # ==========================================
            
            # Save RDS objects of the simulated datasets
            saveRDS(sim_means, "splatpop_sim_means.rds")
            saveRDS(sim_sc, "splatpop_sim_sc.rds")
            saveRDS(sim, "splatpop_sim_full.rds")
            
            # Extract and save count matrix
            counts_matrix <- as.matrix(counts(sim))
            write.csv(counts_matrix, "simulated_counts.csv", row.names = TRUE)
            
            # Save cell and gene metadata
            write.csv(as.data.frame(colData(sim)), "simulated_metadata_cells.csv", row.names = TRUE)
            write.csv(as.data.frame(rowData(sim)), "simulated_metadata_genes.csv", row.names = TRUE)
            
            # Generate diagnostic plots
            pdf("simulation_diagnostic_plots.pdf", width = 10, height = 5)
            par(mfrow = c(1, 2))
            
            # Plot 1: Library size distribution
            hist(colSums(counts_matrix), 
                 main = "Simulated Library Sizes", 
                 xlab = "Total Counts per Cell", 
                 col = "skyblue", 
                 border = "white")
            
            # Plot 2: Gene mean expression distribution
            hist(log10(rowMeans(counts_matrix) + 1), 
                 main = "Simulated Gene Means", 
                 xlab = "log10(Mean Count + 1)", 
                 col = "salmon", 
                 border = "white")
            
            dev.off()

    writeLines(c(
        '"BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION":',
        paste0('    splatter: ', as.character(packageVersion('splatter')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_splatpop_population_simulation.csv versions.yml
    """
}

workflow BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ vcf, gff ] ]

    main:
    BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION(ch_input)

    emit:
    tables   = BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION.out.tables
    plots    = BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION.out.plots
    objects  = BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION.out.objects
    versions = BIOC_SPLATTER_SPLATPOP_POPULATION_SIMULATION.out.versions
}
