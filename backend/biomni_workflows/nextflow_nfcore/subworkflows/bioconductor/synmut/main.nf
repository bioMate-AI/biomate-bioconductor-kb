#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: SynMut
// There are increasing demands on designing virus mutants with specific dinucleotide or codon composit
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/SynMut/inst/doc/SynMut.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("SynMut")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_SYNMUT {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-synmut"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-synmut:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-synmut:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_synmut_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_synmut_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_synmut_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(Usage)
    library(jsonlite)

    # --- Input Seq [] ---
    # Key functions: input_seq
    ---------------------------------------------------------------------
    rgd.seq <- input_seq(filepath.fasta, region)
    rgd.seq
    # --- Get Dna [] ---
    # Key functions: get_dna
    ---------------------------------------------------------------------
    get_dna(rgd.seq)
    # --- Str [] ---
    # Key functions: get_region, input_seq
    ---------------------------------------------------------------------
    str(get_region(rgd.seq))
    get_region(input_seq(filepath.fasta))
    # --- Get Cu [] ---
    # Key functions: get_cu, get_du, get_nu
    ---------------------------------------------------------------------
    get_cu(rgd.seq)
    get_du(rgd.seq)
    get_nu(rgd.seq)
    # --- Codon Random [] ---
    # Key functions: codon_random, get_cu
    ---------------------------------------------------------------------
    # Random synonymous mutations
    mut.seq <- codon_random(rgd.seq)
    # Compare the codon usage
    get_cu(mut.seq) - get_cu(rgd.seq)
    # --- Codon To [] ---
    # Key functions: codon_to, get_cu
    ---------------------------------------------------------------------
    # Generate AAC-maximized mutations
    mut.seq <- codon_to(rgd.seq, max.codon = "AAC")
    # Compare the codon usage
    get_cu(mut.seq) - get_cu(rgd.seq)
    # --- Dinu To [] ---
    # Key functions: dinu_to, get_du, get_cu
    ---------------------------------------------------------------------
    # Maximaize the usage of "CG" dinucleotide in the pre-defined region
    mut.seq <- dinu_to(rgd.seq, max.dinu = "cg")
    # Check the dinucelotide usage difference between the mutant and the original
    get_du(mut.seq) - get_du(rgd.seq)
    # --- Get Cu [] ---
    # Key functions: get_cu, codon_mimic, DNAStringSet, get_freq, Usage, get_rscu
    ---------------------------------------------------------------------
    # Use a codon usage vector as a target
    target <- get_cu(rgd.seq)[2,]
    mut.seq <- codon_mimic(rgd.seq, alt = target)
    # Compare the codon usage

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_synmut_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_synmut_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_synmut_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_SYNMUT:", paste0("    synmut: ", packageVersion("SynMut"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_synmut_results.csv
    touch ${prefix}_synmut_output.rds
    echo "BIOC_SYNMUT:" > versions.yml
    echo "    synmut: 0.0.0" >> versions.yml
    """
}


workflow BIOC_SYNMUT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_SYNMUT(ch_input)

    emit:
    results  = BIOC_SYNMUT.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_SYNMUT.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_SYNMUT.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_SYNMUT.out.versions  // channel: path(versions.yml)
}
