#!/usr/bin/env nextflow
// ============================================================
// Bioconductor workflow: splicewiz — star_alignment_and_reference_generation
// Build a STAR genome index and align FASTQ files to generate BAMs using SpliceWiz wrappers.
// Input: genome.fa, transcripts.gtf, sample_1.fastq, sample_2.fastq
// Container: quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0
// Document-derived (two-stage interpret->build) real input-consuming pipeline.
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION {
    tag "${meta.id}"
    label 'process_medium'

    container "quay.io/biocontainers/bioconductor-splicewiz:1.12.0--r45ha27e39d_0"

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
    .bm_deps <- c("SpliceWiz")
    .bm_miss <- .bm_deps[!vapply(.bm_deps, function(.p) requireNamespace(.p, quietly=TRUE), logical(1))]
    if (length(.bm_miss)) {
      if (!requireNamespace("BiocManager", quietly=TRUE)) install.packages("BiocManager", repos="https://cloud.r-project.org")
      bin <- tryCatch(sprintf("https://bioconductor.org/packages/%s/container-binaries/bioconductor_docker", BiocManager::version()), error=function(e) NULL)
      suppressMessages(tryCatch(BiocManager::install(.bm_miss, update=FALSE, ask=FALSE, site_repository=bin), error=function(e) BiocManager::install(.bm_miss, update=FALSE, ask=FALSE)))
    }
    
    library(SpliceWiz)
    
    ref_path = "./Reference"
    
    if ( ! dir.exists ( file.path (ref_path, "resource" ))) { 
        getResources ( reference_path = ref_path, fasta = "genome.fa" , gtf = "transcripts.gtf" ) 
    }
    
    STAR_BuildRef ( reference_path = ref_path, n_threads = 8 )
    
    Experiment <- data.frame(
        sample = "sample_1",
        forward = "sample_1.fastq",
        reverse = "sample_2.fastq"
    )
    
    write.csv(Experiment, "experiment_design.csv", row.names = FALSE)
    
    STAR_alignExperiment ( Experiment = Experiment, STAR_ref_path = file.path ( ref_path , "STAR" ), BAM_output_path = "./bams" , n_threads = 8 , two_pass = FALSE )
    
    generated_bams <- list.files("./bams", pattern = "\\.bam\$", full.names = TRUE)
    writeLines(generated_bams, "generated_bams.txt")

    cat <<-END_VERSIONS > versions.yml
    "BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION":
        splicewiz: \$(Rscript -e 'cat(as.character(packageVersion("splicewiz")))')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_star_alignment_and_reference_generation.csv versions.yml
    """
}

workflow BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), [ genome.fa, transcripts.gtf, sample_1.fastq, sample_2.fastq ] ]

    main:
    BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION(ch_input)

    emit:
    tables   = BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION.out.tables
    plots    = BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION.out.plots
    objects  = BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION.out.objects
    versions = BIOC_SPLICEWIZ_STAR_ALIGNMENT_AND_REFERENCE_GENERATION.out.versions
}
