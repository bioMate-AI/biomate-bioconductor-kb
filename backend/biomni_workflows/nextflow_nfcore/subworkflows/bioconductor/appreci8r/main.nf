#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: appreci8R — appreci8_variant_filtration_pipeline
// Combine, annotate, and filter variant calls from multiple tools using the 7-step appreci8 algorithm to classify variants as probably true, polymorphism, or arti
// Input: Sample1.rawMutations.vcf, Sample2.rawMutations.vcf, Sample1.bam, Sample1.bai, Sample2.bam, Sample2.bai, target
// Container: quay.io/biocontainers/bioconductor-appreci8r:1.16.0--r42hdfd78af_0
// R packages: (see script)
// Bioconductor: 3.20 | R: 4.4
// Requires: Biostrings, GO.db, GenomicRanges, TxDb.Hsapiens.UCSC.hg19.knownGene, appreci8R, org.Hs.eg.db
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

// Steps:
//  * 1. [Core Analysis] Target filtration (filterTarget)
//  * 2. [Core Analysis] Normalization (normalize)
//  * 3. [Core Analysis] Annotation (annotate)
//  * 4. [Visualization & Output] Output combination (combineOutput)
//  * 5. [Core Analysis] Coverage and Base Quality evaluation (evaluateCovAndBQ)
//  * 6. [Core Analysis] Characteristics determination (determineCharacteristics)
//  * 7. [Core Analysis] Final filtration and classification (finalFiltration)

nextflow.enable.dsl = 2

process BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE {
    tag "${meta.id}"
    label 'process_medium'

    container "399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-variant_calling:3.20"

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
    .bm_deps <- c("appreci8R", "GenomicRanges", "GO.db", "org.Hs.eg.db", "TxDb.Hsapiens.UCSC.hg19.knownGene", "Biostrings")
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
    library(appreci8R)
    library(GenomicRanges)
    library(GO.db)
    library(org.Hs.eg.db)
    library(TxDb.Hsapiens.UCSC.hg19.knownGene)
    library(Biostrings)
    
    # -----------------------------------------------------------------------------
    # 1. Input Preparation & Setup
    # -----------------------------------------------------------------------------
    
    # Define output folder
    output_folder <- "appreci8_output"
    dir.create(output_folder, showWarnings = FALSE)
    
    # Read target regions from the working directory
    if (file.exists("target")) {
      target <- tryCatch({
        readRDS("target")
      }, error = function(e) {
        tryCatch({
          read.table("target", header = TRUE, stringsAsFactors = FALSE)
        }, error = function(e2) {
          read.table("target", header = FALSE, stringsAsFactors = FALSE)
        })
      })
    } else if (file.exists("target.bed")) {
      target <- read.table("target.bed", header = FALSE, stringsAsFactors = FALSE)
    } else if (file.exists("target.txt")) {
      target <- read.table("target.txt", header = FALSE, stringsAsFactors = FALSE)
    } else {
      stop("Target file not found in the working directory.")
    }
    
    # Ensure target columns are named correctly for appreci8R
    if (is.data.frame(target)) {
      if (ncol(target) >= 3) {
        colnames(target)[1:3] <- c("chr", "start", "end")
      }
    }
    
    # Set up separate directories for the two callers to prevent filterTarget 
    # from reading both files under a single caller name.
    dir.create("dir_caller1", showWarnings = FALSE)
    dir.create("dir_caller2", showWarnings = FALSE)
    
    file.copy("Sample1.rawMutations.vcf", "dir_caller1/Sample1.rawMutations.vcf", overwrite = TRUE)
    file.copy("Sample2.rawMutations.vcf", "dir_caller2/Sample2.rawMutations.vcf", overwrite = TRUE)
    
    # Ensure BAM index files are named compatibly with Rsamtools (.bam.bai)
    if (file.exists("Sample1.bai") && !file.exists("Sample1.bam.bai")) {
      file.copy("Sample1.bai", "Sample1.bam.bai")
    }
    if (file.exists("Sample2.bai") && !file.exists("Sample2.bam.bai")) {
      file.copy("Sample2.bai", "Sample2.bam.bai")
    }
    
    # -----------------------------------------------------------------------------
    # 2. Target Filtration (filterTarget)
    # -----------------------------------------------------------------------------
    
    # Run target filtration for GATK (Caller 1)
    caller_folder <- "dir_caller1"
    gatk_filtered <- filterTarget(output_folder, "GATK", caller_folder, ".rawMutations",
                 ".vcf", TRUE, "", "", targetRegions = target)
    
    # Run target filtration for VarScan (Caller 2)
    caller_folder_vs <- "dir_caller2"
    varscan_filtered <- filterTarget(output_folder, "VarScan", caller_folder_vs, ".rawMutations",
                 ".vcf", TRUE, "", "", targetRegions = target)
    
    # -----------------------------------------------------------------------------
    # 3. Normalization (normalize)
    # -----------------------------------------------------------------------------
    
    # Normalize GATK calls
    caller_name <- "GATK"
    input <- gatk_filtered
    normalized <- appreci8R::normalize(output_folder, caller_name, input,
                                       TRUE, TRUE)
    normalized_GATK <- normalized
    
    # Normalize VarScan calls
    caller_name <- "VarScan"
    input <- varscan_filtered
    normalized <- appreci8R::normalize(output_folder, caller_name, input,
                                       TRUE, TRUE)
    normalized_VarScan <- normalized
    
    # -----------------------------------------------------------------------------
    # 4. Annotation (annotate)
    # -----------------------------------------------------------------------------
    
    # Annotate GATK calls
    caller_name <- "GATK"
    input <- normalized_GATK
    annotated <- annotate(output_folder, caller_name, input,
                 locations = c("coding","spliceSite"),
                 consequences = c("nonsynonymous","frameshift","nonsense"))
    annotated_GATK <- annotated
    
    # Annotate VarScan calls
    caller_name <- "VarScan"
    input <- normalized_VarScan
    annotated <- annotate(output_folder, caller_name, input,
                 locations = c("coding","spliceSite"),
                 consequences = c("nonsynonymous","frameshift","nonsense"))
    annotated_VarScan <- annotated
    
    # -----------------------------------------------------------------------------
    # 5. Output Combination (combineOutput)
    # -----------------------------------------------------------------------------
    
    # Combine annotated calls into a GRangesList
    annotated <- GRangesList()
    annotated[[1]] <- annotated_GATK
    annotated[[2]] <- annotated_VarScan
    
    combined<-combineOutput("", c("GATK","VarScan"), annotated)
    
    # -----------------------------------------------------------------------------
    # 6. Coverage and Base Quality Evaluation (evaluateCovAndBQ)
    # -----------------------------------------------------------------------------
    
    bam_folder <- "./"
    filtered<-evaluateCovAndBQ(output_folder, combined, bam_folder, bq_diff = 20,
                               vaf = 0.001)
    
    # -----------------------------------------------------------------------------
    # 7. Characteristics Determination (determineCharacteristics)
    # -----------------------------------------------------------------------------
    
    characteristics <- determineCharacteristics(output_folder, filtered,
                                                predict = "Provean")
    
    # -----------------------------------------------------------------------------
    # 8. Final Filtration (finalFiltration)
    # -----------------------------------------------------------------------------
    
    final<-finalFiltration(output_folder, frequency_calls = filtered,
                           database_calls = characteristics,
                           combined_calls = combined, damaging_safe = -3,
                           tolerated_safe = -1.5, overlapTools = c("VarScan"),
                           bq_diff = 20,vaf = 0.001)
    
    # -----------------------------------------------------------------------------
    # 9. Export Results
    # -----------------------------------------------------------------------------
    
    # Save final GRanges object as RDS
    saveRDS(final, file = file.path(output_folder, "appreci8_final_results.rds"))
    
    # Save final results as a CSV table
    final_df <- as.data.frame(final)
    write.csv(final_df, file = file.path(output_folder, "appreci8_final_results.csv"), row.names = FALSE)
    
    # Save intermediate results
    write.csv(as.data.frame(filtered), file = file.path(output_folder, "appreci8_filtered_cov_bq.csv"), row.names = FALSE)
    write.csv(as.data.frame(characteristics), file = file.path(output_folder, "appreci8_characteristics.csv"), row.names = FALSE)
    
    # Clean up temporary directories
    unlink("dir_caller1", recursive = TRUE)
    unlink("dir_caller2", recursive = TRUE)

    writeLines(c(
        '"BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE":',
        paste0('    appreci8R: ', as.character(packageVersion('appreci8R')))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_appreci8_variant_filtration_pipeline.csv versions.yml
    """
}

workflow BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Sample1.rawMutations.vcf, Sample2.rawMutations.vcf, Sample1.bam, Sample1.bai, Sample2.bam, Sample2.bai, target ] ]

    main:
    BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE(ch_input)

    emit:
    tables   = BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE.out.tables
    plots    = BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE.out.plots
    objects  = BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE.out.objects
    versions = BIOC_APPRECI8R_APPRECI8_VARIANT_FILTRATION_PIPELINE.out.versions
}
