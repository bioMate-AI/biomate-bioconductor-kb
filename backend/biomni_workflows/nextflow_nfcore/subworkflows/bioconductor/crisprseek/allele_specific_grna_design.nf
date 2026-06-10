#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: crisprseek — allele_specific_grna_design
// Compare two sequences (differing by a SNP) to identify gRNAs that preferentially target one allele over the other.
// Input: rs362331C.fa, rs362331T.fa
// Container: quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0
// R packages: CRISPRseek
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-crisprseek:1.50.0--r45hdfd78af_0"

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
    .bm_deps <- c("CRISPRseek")
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
    
    # Load required library
    library(CRISPRseek)
    
    # Define input file paths from the working directory as specified by the user
    inputFile1Path <- "rs362331C.fa"
    inputFile2Path <- "rs362331T.fa"
    outputDir <- getwd()
    
    # Verify that the user-provided input files exist in the working directory
    if (!file.exists(inputFile1Path)) {
      stop(paste("Required input file missing:", inputFile1Path))
    }
    if (!file.exists(inputFile2Path)) {
      stop(paste("Required input file missing:", inputFile2Path))
    }
    
    # Stage 1: Run compare2Sequences on the two input FASTA files
    message("Running compare2Sequences to identify and score gRNAs...")
    res <- compare2Sequences(inputFile1Path,
                             inputFile2Path, 
                             outputDir = outputDir,
                             overwrite = TRUE)
    
    # Display the head of the results as documented in the vignette
    message("Preview of comparison results:")
    print(head(res[, c("name", "gRNAPlusPAM", "scoreForSeq1", "scoreForSeq2", "gRNAefficacy", "scoreDiff")]))
    
    # Save the complete raw comparison results
    write.csv(res, file = "all_compared_gRNAs.csv", row.names = FALSE)
    saveRDS(res, file = "all_compared_gRNAs.rds")
    
    # Stage 2: Evaluate cleavage scores and score differences to select allele-specific gRNAs
    # Convert score columns to numeric to facilitate filtering, handling potential non-numeric annotations safely
    res\$scoreDiff <- suppressWarnings(as.numeric(as.character(res\$scoreDiff)))
    res\$scoreForSeq1 <- suppressWarnings(as.numeric(as.character(res\$scoreForSeq1)))
    res\$scoreForSeq2 <- suppressWarnings(as.numeric(as.character(res\$scoreForSeq2)))
    
    # Select gRNAs that preferentially target Allele 1 (Seq 1) over Allele 2 (Seq 2)
    # High scoreForSeq1, low scoreForSeq2, resulting in a high positive scoreDiff
    allele1_specific <- res[which(res\$scoreDiff > 50), ]
    allele1_specific <- allele1_specific[order(allele1_specific\$scoreDiff, decreasing = TRUE), ]
    
    # Select gRNAs that preferentially target Allele 2 (Seq 2) over Allele 1 (Seq 1)
    # High scoreForSeq2, low scoreForSeq1, resulting in a high negative scoreDiff
    allele2_specific <- res[which(res\$scoreDiff < -50), ]
    allele2_specific <- allele2_specific[order(allele2_specific\$scoreDiff, decreasing = FALSE), ]
    
    # Write the selected allele-specific gRNAs to named output files
    write.csv(allele1_specific, file = "allele1_C_specific_gRNAs.csv", row.names = FALSE)
    write.csv(allele2_specific, file = "allele2_T_specific_gRNAs.csv", row.names = FALSE)
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN":
        crisprseek: \$(Rscript -e 'cat(as.character(packageVersion("crisprseek")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_allele_specific_grna_design.csv versions.yml
    """
}

workflow BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ rs362331C.fa, rs362331T.fa ] ]

    main:
    BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN(ch_input)

    emit:
    tables   = BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN.out.tables
    plots    = BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN.out.plots
    objects  = BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN.out.objects
    versions = BIOC_CRISPRSEEK_ALLELE_SPECIFIC_GRNA_DESIGN.out.versions
}
