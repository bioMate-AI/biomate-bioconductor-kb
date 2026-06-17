#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: rnaEditr — region_based_analysis
// Identify co-edited genomic regions, summarize their editing levels, and test their association with a phenotype of interest.
// Input: rnaedit_df, pheno_df, inputGenes_gr
// Container: quay.io/biocontainers/bioconductor-rnaeditr:1.20.0--r45hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: GenomicRanges, rnaEditr
// Visualizations: plot (ggplot/base)
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Identify sub-regions containing closely located RNA editing sites using AllCloseByRegions()
//  * 2. [Core Analysis] Identify co-edited regions within the close-by regions using AllCoeditedRegions()
//  * 3. [Visualization & Output] Summarize RNA editing levels within each co-edited region using SummarizeAllRegions()
//  * 4. [Visualization & Output] Test associations between the summarized regions and the phenotype using TestAssociations()
//  * 5. [Core Analysis] Annotate the region-based results with input regions, close-by regions, and gene symbols using AnnotateResults()

nextflow.enable.dsl = 2

process BIOC_RNAEDITR_REGION_BASED_ANALYSIS {
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
    .bm_deps <- c("rnaEditr", "GenomicRanges")
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
        library(rnaEditr)
        library(GenomicRanges)
        
        # ==========================================
        # 1. READ USER INPUTS
        # ==========================================
        
        # Read RNA editing matrix
        if (file.exists("rnaedit_df.rds")) {
          rnaedit_df <- readRDS("rnaedit_df.rds")
        } else if (file.exists("rnaedit_df.csv")) {
          rnaedit_df <- as.matrix(read.csv("rnaedit_df.csv", row.names = 1, check.names = FALSE))
        } else {
          stop("Error: rnaedit_df file not found (expected rnaedit_df.rds or rnaedit_df.csv in the working directory).")
        }
        
        # Ensure rnaedit_df is a matrix
        if (is.data.frame(rnaedit_df)) {
          rnaedit_df <- as.matrix(rnaedit_df)
        }
        
        # Read Phenotype dataframe
        if (file.exists("pheno_df.rds")) {
          pheno_df <- readRDS("pheno_df.rds")
        } else if (file.exists("pheno_df.csv")) {
          pheno_df <- read.csv("pheno_df.csv", check.names = FALSE)
        } else {
          stop("Error: pheno_df file not found (expected pheno_df.rds or pheno_df.csv in the working directory).")
        }
        
        # Validate pheno_df has 'sample' column
        if (!"sample" %in% colnames(pheno_df)) {
          stop("Error: pheno_df must contain a 'sample' column matching the column names of rnaedit_df.")
        }
        
        # Align samples between rnaedit_df and pheno_df
        common_samples <- intersect(colnames(rnaedit_df), pheno_df\$sample)
        if (length(common_samples) == 0) {
          stop("Error: No matching samples found between rnaedit_df column names and pheno_df\$sample.")
        }
        rnaedit_df <- rnaedit_df[, common_samples, drop = FALSE]
        pheno_df <- pheno_df[match(common_samples, pheno_df\$sample), , drop = FALSE]
        
        # Read inputGenes_gr (GRanges object)
        if (file.exists("inputGenes_gr.rds")) {
          inputGenes_gr <- readRDS("inputGenes_gr.rds")
        } else {
          stop("Error: inputGenes_gr file not found (expected inputGenes_gr.rds in the working directory).")
        }
        
        if (!inherits(inputGenes_gr, "GRanges")) {
          stop("Error: inputGenes_gr must be a GRanges object.")
        }
        
        # ==========================================
        # 2. ADAPT DOCUMENTED WORKFLOW
        # ==========================================
        
        # Step 1: Identify close-by regions
        closeByRegions_gr <- AllCloseByRegions(
          # a GRanges object of genomic regions retrieved or created in section 4.1.
          regions_gr = inputGenes_gr,
          # an RNA editing matrix.
          rnaEditMatrix = rnaedit_df,
          maxGap = 50,
          minSites = 3
        )
        
        if (length(closeByRegions_gr) == 0) {
          warning("No close-by regions found. Saving empty outputs and exiting.")
          write.csv(data.frame(Message = "No close-by regions found"), "association_results.csv", row.names = FALSE)
          quit(status = 0)
        }
        
        # Step 2: Identify co-edited regions
        closeByCoeditedRegions_gr <- AllCoeditedRegions(
          # a GRanges object of close-by regions created by AllCloseByRegions().
          regions_gr = closeByRegions_gr,
          # an RNA editing matrix.
          rnaEditMatrix = rnaedit_df,
          # type of output data.
          output = "GRanges",
          rDropThresh_num = 0.4,
          minPairCorr = 0.1,
          minSites = 3,
          # the method for computing correlations.
          method = "spearman",
          # When no co-edited regions are found in an input genomic region, you want to
          #   output the whole region (when set to TRUE) or NULL (when set to FALSE).
          returnAllSites = FALSE
        )
        
        if (length(closeByCoeditedRegions_gr) == 0) {
          warning("No co-edited regions found. Saving empty outputs and exiting.")
          write.csv(data.frame(Message = "No co-edited regions found"), "association_results.csv", row.names = FALSE)
          quit(status = 0)
        }
        
        # Step 3: Summarize RNA editing levels within each co-edited region
        summarizedRegions_df <- SummarizeAllRegions(
          # a GRanges object of close-by regions created by AllCoeditedRegions().
          regions_gr = closeByCoeditedRegions_gr,
          # an RNA editing matrix.
          rnaEditMatrix = rnaedit_df,
          # available methods: "MaxSites", "MeanSites", "MedianSites", and "PC1Sites".
          selectMethod = MedianSites
        )
        
        # Step 4: Test associations
        # Dynamically determine response variable and type from pheno_df
        potential_vars <- setdiff(colnames(pheno_df), c("sample", "submitter_id"))
        
        if ("sample_type" %in% colnames(pheno_df)) {
          response_var <- "sample_type"
        } else if (all(c("OS.time", "OS") %in% colnames(pheno_df))) {
          response_var <- c("OS.time", "OS")
        } else if (length(potential_vars) == 2) {
          response_var <- potential_vars
        } else {
          # Fallback to the first available column
          response_var <- potential_vars[1]
        }
        
        # Determine response type (binary, continuous, or survival)
        if (length(response_var) == 2) {
          resp_type <- "survival"
        } else if (is.numeric(pheno_df[[response_var]]) && length(unique(pheno_df[[response_var]])) > 5) {
          resp_type <- "continuous"
        } else {
          resp_type <- "binary"
        }
        
        tumor_region_df <- TestAssociations(
          # an RNA editing dataframe with special class "rnaEdit_df" from function
          #   CreateEditingTable() if site-specific analysis, from function 
          #   SummarizeAllRegions() if region-based analysis.
          rnaEdit_df = summarizedRegions_df,
          # a phenotype dataset that must have variable "sample" whose values are a 
          #   exact match to the colnames of "rnaEdit_df".
          pheno_df = pheno_df,
          # name of outcome variable in phenotype dataset "pheno_df" that you want to 
          #   test.
          responses_char = response_var,
          # names of covariate variables in phenotype dataset "pheno_df" that you want
          #   to add into the model.
          covariates_char = NULL,
          # type of outcome variable that you input in argument "responses_char".
          respType = resp_type,
          # order the final results by p-values or not.
          orderByPval = TRUE
        )
        
        # Step 5: Annotate results
        # Dynamically determine genome from input GRanges, fallback to hg19
        input_genome <- unique(as.character(genome(inputGenes_gr)))
        input_genome <- input_genome[input_genome %in% c("hg19", "hg38")]
        if (length(input_genome) == 0) {
          input_genome <- "hg19"
        } else {
          input_genome <- input_genome[1]
        }
    
        tumor_annot_df <- AnnotateResults(
          # the output dataset from function TestAssociations().
          results_df = tumor_region_df,
          # close-by regions which is a output of AllCloseByRegions().
          closeByRegions_gr = closeByRegions_gr,
          # input regions, which are created in section 4.1.
          inputRegions_gr = inputGenes_gr,
          genome = input_genome,
          # the type of analysis result from function TestAssociations(), since we are 
          #   doing region-based analysis, use default here.
          analysis = "region-based"
        )
        
        # ==========================================
        # 3. WRITE OUTPUTS
        # ==========================================
        
        # Save tabular results
        write.csv(summarizedRegions_df, "summarized_regions.csv", row.names = FALSE)
        write.csv(tumor_region_df, "association_results.csv", row.names = FALSE)
        write.csv(tumor_annot_df, "annotated_association_results.csv", row.names = FALSE)
        
        # Save GRanges objects
        saveRDS(closeByRegions_gr, "closeByRegions.rds")
        saveRDS(closeByCoeditedRegions_gr, "closeByCoeditedRegions.rds")
        
        # Generate and save correlation plot for the first co-edited region
        if (length(closeByCoeditedRegions_gr) > 0) {
          pdf("editing_correlations_first_region.pdf", width = 7, height = 7)
          PlotEditingCorrelations(
            region_gr = closeByCoeditedRegions_gr[1],
            rnaEditMatrix = rnaedit_df
          )
          dev.off()
        }
        
        message("Pipeline completed successfully. Outputs written to the working directory.")

    writeLines(c(
        '"BIOC_RNAEDITR_REGION_BASED_ANALYSIS":',
        paste0('    rnaEditr: ', as.character(packageVersion('rnaEditr')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_region_based_analysis.csv versions.yml
    """
}

workflow BIOC_RNAEDITR_REGION_BASED_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rnaedit_df, pheno_df, inputGenes_gr ] ]

    main:
    BIOC_RNAEDITR_REGION_BASED_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RNAEDITR_REGION_BASED_ANALYSIS.out.tables
    plots    = BIOC_RNAEDITR_REGION_BASED_ANALYSIS.out.plots
    objects  = BIOC_RNAEDITR_REGION_BASED_ANALYSIS.out.objects
    versions = BIOC_RNAEDITR_REGION_BASED_ANALYSIS.out.versions
}
