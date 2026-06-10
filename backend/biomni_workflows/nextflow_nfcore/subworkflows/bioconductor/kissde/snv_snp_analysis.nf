#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: kissde — snv_snp_analysis
// Identify differentially represented single nucleotide variations (SNVs/SNPs) from KisSplice fasta output.
// Input: output_kissplice_SNV.fa
// Container: quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0
// R packages: kissDE
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_KISSDE_SNV_SNP_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-kissde:1.30.0--r45hdfd78af_0"

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
    .bm_deps <- c("kissDE")
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
    
    # Load the required Bioconductor package
    library(kissDE)
    
    # Define the input file path (must be present in the working directory)
    fileInSNV <- "output_kissplice_SNV.fa"
    
    # Verify that the user input file exists
    if (!file.exists(fileInSNV)) {
      stop(paste("Error: Required input file '", fileInSNV, "' not found in the working directory.", sep = ""))
    }
    
    # 1. Convert KisSplice fasta output to counts using kissplice2counts
    myCounts_SNV <- kissplice2counts(fileInSNV, counts = 0, pairedEnd = TRUE)
    
    # 2. Define condition vector
    myConditions_SNV <- c(rep("TSC", 2), rep("CEU", 2))
    
    # 3. Perform quality control and save the generated plots to a PDF file
    pdf("quality_control_plots.pdf")
    qualityControl(myCounts_SNV, myConditions_SNV)
    dev.off()
    
    # 4. Run differential analysis using diffExpressedVariants
    myResult_SNV <- diffExpressedVariants(myCounts_SNV, myConditions_SNV)
    
    # 5. Export results using writeOutputKissDE
    writeOutputKissDE(myResult_SNV, output = "final_table_significants.tab", adjPvalMax = 0.05)
    
    # 6. Explore results interactively using exploreResults
    # Wrapped in a tryCatch block to prevent pipeline failure in non-interactive environments
    tryCatch({
      exploreResults(rdsFile = "final_table_significants.tab.rds")
    }, error = function(e) {
      message("exploreResults() skipped or failed (this is expected in non-interactive/headless environments): ", e\$message)
    })

    cat <<-END_VERSIONS > versions.yml
    "BIOC_KISSDE_SNV_SNP_ANALYSIS":
        kissde: \$(Rscript -e 'cat(as.character(packageVersion("kissde")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_snv_snp_analysis.csv versions.yml
    """
}

workflow BIOC_KISSDE_SNV_SNP_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ output_kissplice_SNV.fa ] ]

    main:
    BIOC_KISSDE_SNV_SNP_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_KISSDE_SNV_SNP_ANALYSIS.out.tables
    plots    = BIOC_KISSDE_SNV_SNP_ANALYSIS.out.plots
    objects  = BIOC_KISSDE_SNV_SNP_ANALYSIS.out.objects
    versions = BIOC_KISSDE_SNV_SNP_ANALYSIS.out.versions
}
