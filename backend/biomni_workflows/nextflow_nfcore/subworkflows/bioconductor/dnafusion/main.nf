#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: dnafusion — eml4_alk_fusion_analysis
// Detect, characterize, and identify EML4-ALK gene fusion variants and breakpoints from paired-end BAM files.
// Input: file.bam
// Container: quay.io/biocontainers/bioconductor-dnafusion:1.12.0--r45hdfd78af_0
// R packages: DNAfusion
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-dnafusion:1.12.0--r45hdfd78af_0"

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
    .bm_deps <- c("DNAfusion")
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
    
    # Check for required input file
    input_bam <- "file.bam"
    if (!file.exists(input_bam)) {
      stop(paste("Error: Input file", input_bam, "not found in the working directory."))
    }
    
    # Load required library
    library(DNAfusion)
    
    # 1. Detect EML4-ALK mate pair reads
    message("Running EML4_ALK_detection...")
    H3122_result <- EML4_ALK_detection(
      file = input_bam, 
      genome = "hg38", 
      mates = 2
    )
    saveRDS(H3122_result, file = "EML4_ALK_detection_result.rds")
    
    # 2. Identify EML4 sequence leading to the breakpoint
    message("Running EML4_sequence...")
    eml4_seq <- EML4_sequence(
      H3122_result, 
      genome = "hg38", 
      basepairs = 20
    )
    saveRDS(eml4_seq, file = "EML4_sequence_result.rds")
    if (is.character(eml4_seq)) {
      writeLines(eml4_seq, con = "EML4_sequence.txt")
    } else {
      write.csv(as.data.frame(eml4_seq), file = "EML4_sequence.csv", row.names = TRUE)
    }
    
    # 3. Identify ALK sequence following the breakpoint
    message("Running ALK_sequence...")
    alk_seq <- ALK_sequence(
      H3122_result, 
      genome = "hg38", 
      basepairs = 20
    )
    saveRDS(alk_seq, file = "ALK_sequence_result.rds")
    if (is.character(alk_seq)) {
      writeLines(alk_seq, con = "ALK_sequence.txt")
    } else {
      write.csv(as.data.frame(alk_seq), file = "ALK_sequence.csv", row.names = TRUE)
    }
    
    # 4. Identify genomic breakpoint positions
    message("Running break_position...")
    eml4_break_pos <- break_position(
      H3122_result, 
      genome = "hg38", 
      gene = "EML4"
    )
    saveRDS(eml4_break_pos, file = "break_position_EML4_result.rds")
    if (is.character(eml4_break_pos)) {
      writeLines(eml4_break_pos, con = "break_position_EML4.txt")
    } else {
      write.csv(as.data.frame(eml4_break_pos), file = "break_position_EML4.csv", row.names = TRUE)
    }
    
    # 5. Calculate read depth at the breakpoint
    message("Running break_position_depth...")
    eml4_break_depth <- break_position_depth(
      input_bam, 
      H3122_result, 
      genome = "hg38", 
      gene = "EML4"
    )
    saveRDS(eml4_break_depth, file = "break_position_depth_EML4_result.rds")
    writeLines(as.character(eml4_break_depth), con = "break_position_depth_EML4.txt")
    
    # 6. Perform a combined analysis
    message("Running EML4_ALK_analysis...")
    H3122_results <- EML4_ALK_analysis(
      file = input_bam, 
      genome = "hg38", 
      mates = 2, 
      basepairs = 20
    )
    saveRDS(H3122_results, file = "EML4_ALK_analysis_results.rds")
    
    # 7. Identify introns containing the breakpoint
    message("Running introns_ALK_EML4...")
    introns_res <- introns_ALK_EML4(
      file = input_bam, 
      genome = "hg38"
    )
    saveRDS(introns_res, file = "introns_ALK_EML4_result.rds")
    if (is.data.frame(introns_res)) {
      write.csv(introns_res, file = "introns_ALK_EML4.csv", row.names = FALSE)
    } else {
      writeLines(as.character(introns_res), con = "introns_ALK_EML4.txt")
    }
    
    # 8. Identify the specific EML4-ALK variant
    message("Running find_variants...")
    variants_res <- find_variants(
      file = input_bam, 
      genome = "hg38"
    )
    saveRDS(variants_res, file = "find_variants_result.rds")
    if (is.data.frame(variants_res)) {
      write.csv(variants_res, file = "find_variants.csv", row.names = FALSE)
    } else {
      writeLines(as.character(variants_res), con = "find_variants.txt")
    }
    
    message("Pipeline completed successfully. Outputs saved to working directory.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS":
        dnafusion: \$(Rscript -e 'cat(as.character(packageVersion("dnafusion")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_eml4_alk_fusion_analysis.csv versions.yml
    """
}

workflow BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ file.bam ] ]

    main:
    BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS.out.tables
    plots    = BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS.out.plots
    objects  = BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS.out.objects
    versions = BIOC_DNAFUSION_EML4_ALK_FUSION_ANALYSIS.out.versions
}
