#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ramwas — cpg_snp_joint_analysis
// Perform a joint association analysis of methylation and genotype data to account for the effects of CpG-SNPs on methylation measurements.
// Input: Coverage, CpG_locations, SNPs, covariates
// Container: quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ramwas:1.34.0--r45h01b2380_0"

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
    .bm_deps <- c("filematrix", "ramwas")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(ramwas)
    library(filematrix)
    
    # Define the project directory as the current working directory
    dr = "."
    
    # Read the user-provided covariates data frame from the working directory
    if (file.exists("covariates.rds")) {
      covariates = readRDS("covariates.rds")
    } else if (file.exists("covariates.txt")) {
      covariates = read.table("covariates.txt", header = TRUE, sep = "\t", stringsAsFactors = FALSE)
    } else if (file.exists("covariates.csv")) {
      covariates = read.csv("covariates.csv", stringsAsFactors = FALSE)
    } else if (file.exists("covariates")) {
      covariates = tryCatch({
        readRDS("covariates")
      }, error = function(e) {
        read.table("covariates", header = TRUE, stringsAsFactors = FALSE)
      })
    } else {
      stop("Error: Covariates file ('covariates.rds', 'covariates.txt', 'covariates.csv', or 'covariates') not found in the working directory.")
    }
    
    # Verify that the required filematrix inputs exist in the working directory
    required_files = c("Coverage.desc", "CpG_locations.desc", "SNPs.desc")
    missing_files = required_files[!file.exists(required_files)]
    if (length(missing_files) > 0) {
      warning(paste("Warning: Missing expected filematrix description files:", paste(missing_files, collapse = ", ")))
    }
    
    # Define parameters for the joint analysis exactly as documented
    param = ramwasParameters(
     dircoveragenorm = dr,
     covariates = covariates,
     modelcovariates = "batch",
     modeloutcome = "sex",
     toppvthreshold = 20,
     fileSNPs = "SNPs"
    )
    
    # Run the joint CpG-SNP association analysis
    message("Running joint CpG-SNP association analysis...")
    ramwasSNPs(param)
    
    # Run a standard MWAS on the same parameters for comparison
    message("Running standard MWAS for comparison...")
    ramwas5MWAS(param)
    
    # Preprocess parameters to locate output directories
    pfull = parameterPreprocess(param)
    
    # Export meaningful results to named output files in the working directory
    message("Exporting results...")
    
    # 1. Export CpG-SNP Joint Analysis Top Findings
    snp_top_file = file.path(pfull\$dirSNPs, "Top_tests.txt")
    if (file.exists(snp_top_file)) {
      snp_top = read.table(snp_top_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
      write.csv(snp_top, "cpg_snp_joint_top_tests.csv", row.names = FALSE)
      message("Saved CpG-SNP joint analysis top tests to 'cpg_snp_joint_top_tests.csv'")
    } else {
      warning("CpG-SNP joint analysis Top_tests.txt not found.")
    }
    
    # 2. Export Standard MWAS Top Findings
    mwas_top_file = file.path(pfull\$dirmwas, "Top_tests.txt")
    if (file.exists(mwas_top_file)) {
      mwas_top = read.table(mwas_top_file, header = TRUE, sep = "\t", stringsAsFactors = FALSE)
      write.csv(mwas_top, "standard_mwas_top_tests.csv", row.names = FALSE)
      message("Saved standard MWAS top tests to 'standard_mwas_top_tests.csv'")
    } else {
      warning("Standard MWAS Top_tests.txt not found.")
    }
    
    # 3. Copy the Standard MWAS QQ Plot
    mwas_qq_file = file.path(pfull\$dirmwas, "QQ_plot.pdf")
    if (file.exists(mwas_qq_file)) {
      file.copy(mwas_qq_file, "standard_mwas_qq_plot.pdf", overwrite = TRUE)
      message("Saved standard MWAS QQ plot to 'standard_mwas_qq_plot.pdf'")
    }
    
    message("Pipeline completed successfully.")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS":
        ramwas: \$(Rscript -e 'cat(as.character(packageVersion("ramwas")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cpg_snp_joint_analysis.csv versions.yml
    """
}

workflow BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ Coverage, CpG_locations, SNPs, covariates ] ]

    main:
    BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS.out.tables
    plots    = BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS.out.plots
    objects  = BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS.out.objects
    versions = BIOC_RAMWAS_CPG_SNP_JOINT_ANALYSIS.out.versions
}
