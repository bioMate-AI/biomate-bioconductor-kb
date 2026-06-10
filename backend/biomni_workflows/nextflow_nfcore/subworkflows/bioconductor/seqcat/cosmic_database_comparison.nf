#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: seqcat — cosmic_database_comparison
// Compare sample SNV profiles against external COSMIC somatic mutation profiles to authenticate cell lines.
// Input: subset_CosmicCLP_MutantExport.tsv.gz, example.vcf.gz
// Container: quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0
// R packages: seqCAT
// Bioconductor: 3.21 | R: 4.5
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-seqcat:1.32.0--r45hdfd78af_0"

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
    .bm_deps <- c("seqCAT")
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
    library("seqCAT")
    
    # Define the input files in the working directory as specified
    vcf <- "example.vcf.gz"
    file <- "subset_CosmicCLP_MutantExport.tsv.gz"
    
    # Verify that the required input files exist
    if (!file.exists(vcf)) {
      stop(paste("Required input VCF file not found in working directory:", vcf))
    }
    if (!file.exists(file)) {
      stop(paste("Required input COSMIC file not found in working directory:", file))
    }
    
    # 1. Create the SNV profile for HCT116
    hct116 <- create_profile(vcf, "HCT116")
    
    # 2. List available cell lines in the COSMIC file
    cell_lines <- list_cosmic(file)
    
    # 3. Read the specific COSMIC profile for HCT116
    cosmic <- read_cosmic(file, "HCT116")
    
    # 4. Compare the sample profile to the COSMIC profile
    hct116_cosmic <- compare_profiles(hct116, cosmic)
    
    # 5. Create additional profiles for comparison
    hke3 <- create_profile(vcf, "HKE3")
    rko <- create_profile(vcf, "RKO", min_depth = 15, filter_gd = FALSE)
    
    # 6. Perform one-to-many comparisons against COSMIC
    profiles <- list(hct116, hke3, rko)
    many_cosmic <- compare_many(profiles, one = cosmic)
    
    # Write meaningful output files to the working directory
    # Save the list of available COSMIC cell lines
    writeLines(cell_lines, "cosmic_cell_lines_list.txt")
    
    # Save the individual profiles as CSVs
    write.csv(as.data.frame(hct116), "profile_hct116.csv", row.names = FALSE)
    write.csv(as.data.frame(hke3), "profile_hke3.csv", row.names = FALSE)
    write.csv(as.data.frame(rko), "profile_rko.csv", row.names = FALSE)
    write.csv(as.data.frame(cosmic), "profile_cosmic_hct116.csv", row.names = FALSE)
    
    # Save the binary comparison against COSMIC
    write.csv(as.data.frame(hct116_cosmic), "hct116_vs_cosmic_comparison.csv", row.names = FALSE)
    
    # Save the many-to-one COSMIC comparison results
    # many_cosmic[[1]] contains the similarity statistics
    write.csv(as.data.frame(many_cosmic[[1]]), "many_vs_cosmic_similarities.csv", row.names = FALSE)
    
    # Save the full comparison object as an RDS file for downstream analysis
    saveRDS(many_cosmic, "many_vs_cosmic_results.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON":
        seqcat: \$(Rscript -e 'cat(as.character(packageVersion("seqcat")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_cosmic_database_comparison.csv versions.yml
    """
}

workflow BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ subset_CosmicCLP_MutantExport.tsv.gz, example.vcf.gz ] ]

    main:
    BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON(ch_input)

    emit:
    tables   = BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON.out.tables
    plots    = BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON.out.plots
    objects  = BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON.out.objects
    versions = BIOC_SEQCAT_COSMIC_DATABASE_COMPARISON.out.versions
}
