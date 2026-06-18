#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: methtargetedngs — profile_hmm_analysis
// Build a Profile HMM from a multiple sequence alignment and calculate sequence likelihoods.
// Input: msa.fasta, Tumor.fasta
// Container: quay.io/biocontainers/bioconductor-methtargetedngs:1.42.0--r45hdfd78af_0
// R packages: MethTargetedNGS
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-methtargetedngs:1.42.0--r45hdfd78af_0"

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
    .bm_deps <- c("MethTargetedNGS")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      options(repos = c(CRAN = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"))  # CRAN binaries (Posit PPM)
      .bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressWarnings(suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=.bin), error=function(e) try(install.packages(.bm_miss), silent=TRUE))))
    }

    # [biomate] flatten staged inputs (stageAs '?/*' -> numbered subdirs)
    for (.bm_d in list.files(".", full.names = TRUE)) {
      if (dir.exists(.bm_d) && grepl("/[0-9]+\$", .bm_d)) {
        for (.bm_e in list.files(.bm_d, full.names = TRUE)) {
          if (!file.exists(basename(.bm_e))) try(file.copy(.bm_e, ".", recursive = TRUE), silent = TRUE)
        }
      }
    }
    
    # Load the required library
    library(MethTargetedNGS)
    
    # Validate that the required user input files exist in the working directory
    if (!file.exists("msa.fasta")) {
      stop("Error: Required input file 'msa.fasta' (multiple sequence alignment) is missing from the working directory.")
    }
    
    if (!file.exists("Tumor.fasta")) {
      stop("Error: Required input file 'Tumor.fasta' (query sequences) is missing from the working directory.")
    }
    
    # Define input file paths
    msa <- "msa.fasta"
    tumor <- "Tumor.fasta"
    
    # --- Build Profile HMM using hmmbuild (if the external HMMER ---
    if (file.exists("/usr/bin/hmmbuild")) {
      message("Building Profile HMM from MSA...")
      hmmbuild(file_seq=msa, file_out="hmm", pathHMMER = "/usr/bin/")
      message("Profile HMM successfully built and saved to 'hmm'.")
    } else {
      warning("HMMER binary '/usr/bin/hmmbuild' not found. Skipping HMM construction.")
    }
    
    # --- Calculate sequence likelihoods against the HMM using ---
    if (file.exists("/usr/bin/nhmmer")) {
      if (file.exists("hmm")) {
        message("Calculating sequence likelihoods against the HMM...")
        res <- nhmmer("hmm", tumor, pathHMMER = "/usr/bin/")
        
        # Display the total likelihood score
        message("Total Likelihood Score:")
        print(res\$Total.Likelihood.Score)
        
        # Save the results to output files
        write.csv(res, "likelihood_scores.csv", row.names = FALSE)
        saveRDS(res, "nhmmer_results.rds")
        message("Results successfully saved to 'likelihood_scores.csv' and 'nhmmer_results.rds'.")
      } else {
        warning("HMM file 'hmm' does not exist. Cannot run nhmmer.")
      }
    } else {
      warning("HMMER binary '/usr/bin/nhmmer' not found. Skipping likelihood calculation.")
    }

    writeLines(c(
        '"BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS":',
        paste0('        methtargetedngs: ', as.character(packageVersion("methtargetedngs")))
    ), "versions.yml")
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_profile_hmm_analysis.csv versions.yml
    """
}

workflow BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ msa.fasta, Tumor.fasta ] ]

    main:
    BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS(ch_input)

    emit:
    tables   = BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS.out.tables
    plots    = BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS.out.plots
    objects  = BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS.out.objects
    versions = BIOC_METHTARGETEDNGS_PROFILE_HMM_ANALYSIS.out.versions
}
