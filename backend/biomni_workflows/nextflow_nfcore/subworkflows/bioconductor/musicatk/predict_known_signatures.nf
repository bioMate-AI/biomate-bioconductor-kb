#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: musicatk — predict_known_signatures
// Predict exposures of pre-existing mutational signatures (e.g., COSMIC) in a dataset instead of discovering them de novo.
// Input: public_TCGA.LUSC.maf, public_LUAD_TCGA-97-7938.vcf
// Container: quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-musicatk:2.4.0--r45h1f0d9b5_0"

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
    .bm_deps <- c("BSgenome.Hsapiens.UCSC.hg38", "musicatk")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    # Load required libraries
    library(musicatk)
    library(BSgenome.Hsapiens.UCSC.hg38)
    
    # Set seed for reproducibility
    set.seed(1)
    
    # Define input files from the working directory
    lusc_maf <- "public_TCGA.LUSC.maf"
    luad_vcf <- "public_LUAD_TCGA-97-7938.vcf"
    
    # Extract variants from the user-provided files
    variants <- extract_variants(c(lusc_maf, luad_vcf))
    
    # Select genome
    g <- select_genome("hg38")
    
    # Create musica object
    musica <- create_musica_from_variants(x = variants, genome = g)
    
    # Build standard table for SBS96
    build_standard_table(musica, g = g, modality = "SBS96")
    
    # Discover signatures to generate the "ex_result" model needed for downstream steps
    discover_signatures(
      musica = musica, modality = "SBS96", num_signatures = 3,
      algorithm = "nmf", model_id = "ex_result", nstart = 2
    )
    
    # Load COSMIC V2 signatures directly from the package namespace to avoid data()
    cosmic_v2_sigs <- musicatk::cosmic_v2_sigs
    
    # Predict exposures using COSMIC V2 signatures
    predict_exposure(
      musica = musica, modality = "SBS96",
      signature_res = cosmic_v2_sigs, model_id = "ex_pred_result",
      signatures_to_use = c(1, 4, 7, 13), algorithm = "lda"
    )
    
    # Plot exposures and save to PDF
    pdf("ex_pred_result_bar_plot.pdf")
    plot_exposures(musica, "ex_pred_result", plot_type = "bar")
    dev.off()
    
    # Map subtypes and save to CSV
    subtype_map <- cosmic_v2_subtype_map("lung")
    write.csv(subtype_map, "cosmic_v2_lung_subtype_map.csv", row.names = FALSE)
    
    # Get the discovered model
    model <- get_model(musica, "result", "SBS96", "ex_result")
    
    # Predict exposures using our discovered signatures
    predict_exposure(
      musica = musica, modality = "SBS96",
      signature_res = model, algorithm = "lda",
      model_id = "pred_our_sigs"
    )
    
    # Compare the two prediction results
    comparison <- compare_results(musica,
      model_id = "ex_pred_result",
      other_model_id = "pred_our_sigs", threshold = 0.60
    )
    
    # Save comparison results to CSV
    write.csv(comparison, "comparison_results.csv", row.names = FALSE)
    
    # Save the final musica object to RDS
    saveRDS(musica, "musica_object.rds")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES":
        musicatk: \$(Rscript -e 'cat(as.character(packageVersion("musicatk")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_predict_known_signatures.csv versions.yml
    """
}

workflow BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ public_TCGA.LUSC.maf, public_LUAD_TCGA-97-7938.vcf ] ]

    main:
    BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES(ch_input)

    emit:
    tables   = BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES.out.tables
    plots    = BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES.out.plots
    objects  = BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES.out.objects
    versions = BIOC_MUSICATK_PREDICT_KNOWN_SIGNATURES.out.versions
}
