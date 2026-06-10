#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: ribor — translational_efficiency_and_optional_data
// Extract optional coverage and RNA-Seq data from a .ribo file to perform translational efficiency analysis.
// Input: HEK293_ingolia.ribo
// Container: quay.io/biocontainers/bioconductor-ribor:1.22.0--r45hdfd78af_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-ribor:1.22.0--r45hdfd78af_0"

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
    .bm_deps <- c("ribor")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required library
    library(ribor)
    
    # Define the input file path in the working directory
    file.path <- "HEK293_ingolia.ribo"
    
    # Check if the input file exists
    if (!file.exists(file.path)) {
      stop(paste("Required input file '", file.path, "' not found in the working directory.", sep=""))
    }
    
    # 1. Initialize the Ribo class object
    original.ribo <- Ribo(file.path, rename = rename_default)
    
    # 2. Check for optional data fields (coverage, RNA-Seq, metadata) using get_info()
    experiment.info <- get_info(ribo.object = original.ribo)[['experiment.info']]
    write.csv(experiment.info, "experiment_info.csv", row.names = FALSE)
    
    has.metadata <- experiment.info[experiment.info\$metadata == TRUE, "experiment"]
    experiment <- has.metadata[1]
    
    # 3. Retrieve metadata using get_metadata()
    # Print to console as documented
    get_metadata(ribo.object = original.ribo,
                 name        = experiment,
                 print       = TRUE)
    
    # Capture metadata to save as a text file
    metadata_content <- capture.output(
      get_metadata(ribo.object = original.ribo,
                   name        = experiment,
                   print       = TRUE)
    )
    writeLines(metadata_content, "experiment_metadata.txt")
    
    # 4. Extract nucleotide-level coverage for specific transcripts using get_coverage()
    has.coverage <- experiment.info[experiment.info\$coverage == TRUE, "experiment"]
    cov <- get_coverage(ribo.object = original.ribo,
                        name        = "MYC-206",
                        range.lower = 28,
                        range.upper = 32,
                        length      = TRUE,
                        alias       = TRUE,
                        tidy        = TRUE,
                        experiment  = has.coverage)
    
    # Save coverage data
    saveRDS(cov, "MYC-206_coverage.rds")
    write.csv(as.data.frame(cov), "MYC-206_coverage.csv", row.names = FALSE)
    
    # 5. Extract RNA-Seq region counts using get_rnaseq()
    has.rnaseq <- experiment.info[experiment.info\$rna.seq == TRUE, "experiment"]
    rnaseq <- get_rnaseq(ribo.object = original.ribo,
                         tidy        = FALSE,
                         alias       = TRUE,
                         experiment  = has.rnaseq)
    
    # Save general RNA-Seq data
    saveRDS(rnaseq, "rnaseq_all_regions.rds")
    write.csv(as.data.frame(rnaseq), "rnaseq_all_regions.csv", row.names = FALSE)
    
    # 6. Calculate translational efficiency by dividing ribosome profiling CDS counts by RNA-Seq CDS counts
    rnaseq_CDS <- get_rnaseq(ribo.object = original.ribo,
                             tidy        = TRUE,
                             alias       = TRUE,
                             region      = "CDS",
                             compact     = FALSE,
                             experiment  = "GSM1606108")
    
    rc_CDS <- get_region_counts(ribo.object    = original.ribo,
                                tidy       = TRUE,
                                alias      = TRUE,
                                transcript = FALSE,
                                region     = "CDS",
                                compact    = FALSE,
                                experiment = "GSM1606108")
    
    # Open PDF device to save diagnostic and analysis plots
    pdf("translational_efficiency_plots.pdf", width = 7, height = 5)
    
    # Plot 1: RNA-Seq Density
    plot(density(log2(rnaseq_CDS\$count)), xlab = "Log 2 of RNA-Seq Count", main = "RNA-Seq Density")
    
    # Filter out transcripts with count value less than 2 for either ribosome profiling region counts or rnaseq
    filtered_transcripts <- which(rnaseq_CDS\$count > 2 & rc_CDS\$count > 2)
    rnaseq_CDS           <- rnaseq_CDS[filtered_transcripts, ]
    rc_CDS               <- rc_CDS[filtered_transcripts, ]
    
    # Plot 2: Relationship between ribosome profiling and RNA-Seq counts
    plot(log2(rnaseq_CDS\$count), log2(rc_CDS\$count), xlab = "RNA-Seq", ylab = "Ribosome Profiling", main = "log2 CDS Read Counts", pch = 19, cex = 0.5)
    
    # Calculate translational efficiency
    te_CDS    <- rc_CDS\$count/rnaseq_CDS\$count
    
    # Plot 3: Density of Translational Efficiency
    plot(density(log2(te_CDS)), xlab = "Log 2 of Translation Efficiency", main = "Translational Efficiency Density")
    
    # Close PDF device
    dev.off()
    
    # Identify transcripts with high translational efficiency (> 0.25)
    high_te <- rc_CDS\$transcript[which(te_CDS > .25)]
    
    # Save translational efficiency results
    te_results <- data.frame(
      transcript = rc_CDS\$transcript,
      ribo_count = rc_CDS\$count,
      rnaseq_count = rnaseq_CDS\$count,
      translational_efficiency = te_CDS
    )
    write.csv(te_results, "translational_efficiency_CDS.csv", row.names = FALSE)
    
    # Save list of high translational efficiency transcripts
    writeLines(as.character(high_te), "high_te_transcripts.txt")
    
    message("Pipeline completed successfully. Outputs generated:")
    message("- experiment_info.csv")
    message("- experiment_metadata.txt")
    message("- MYC-206_coverage.csv / .rds")
    message("- rnaseq_all_regions.csv / .rds")
    message("- translational_efficiency_plots.pdf")
    message("- translational_efficiency_CDS.csv")
    message("- high_te_transcripts.txt")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA":
        ribor: \$(Rscript -e 'cat(as.character(packageVersion("ribor")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_translational_efficiency_and_optional_data.csv versions.yml
    """
}

workflow BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ HEK293_ingolia.ribo ] ]

    main:
    BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA(ch_input)

    emit:
    tables   = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA.out.tables
    plots    = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA.out.plots
    objects  = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA.out.objects
    versions = BIOC_RIBOR_TRANSLATIONAL_EFFICIENCY_AND_OPTIONAL_DATA.out.versions
}
