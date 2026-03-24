#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pram
// Publicly available RNA-seq data is routinely used for retrospective analysis to elucidate new biolog
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pram/inst/doc/pram.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pram")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PRAM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pram"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pram:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pram:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pram_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pram_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pram_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GRanges)
    library(jsonlite)

    # --- Accessexample [] ---
    # Key functions: file
    system.file('extdata/demo/in.gtf', package='pram')
    # --- Defigranges [] ---
    # Key functions: defIgRanges
    pram::defIgRanges(system.file('extdata/gtf/defIgRanges_in.gtf', package='pram'),
                    genome = 'hg38')
    # --- Prepigbam [] ---
    # Key functions: GRanges, tempfile, prepIgBam
    finbam =system.file('extdata/bam/CMPRep2.sortedByCoord.raw.bam',
                        package='pram')
    iggrs = GenomicRanges::GRanges('chr10:77236000-77247000:+')
    foutbam = tempfile(fileext='.bam')
    pram::prepIgBam(finbam, iggrs, foutbam)
    # --- Selmodel [] ---
    # Key functions: tempfile, selModel
    fin_gtf = system.file('extdata/gtf/selModel_in.gtf', package='pram')
    fout_gtf = tempfile(fileext='.gtf')
    pram::selModel(fin_gtf, fout_gtf)
    # --- Evalmodel [] ---
    # Key functions: fread, evalModel
    fmdl = system.file('extdata/benchmark/plcf.tsv', package='pram')
    ftgt = system.file('extdata/benchmark/tgt.tsv',  package='pram')
    mdldt = data.table::fread(fmdl, header=TRUE, sep="\t")
    tgtdt = data.table::fread(ftgt, header=TRUE, sep="\t")
    pram::evalModel(mdldt, tgtdt)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pram_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pram_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pram_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PRAM:", paste0("    pram: ", packageVersion("pram"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pram_results.csv
    touch ${prefix}_pram_output.rds
    echo "BIOC_PRAM:" > versions.yml
    echo "    pram: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PRAM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PRAM(ch_input)

    emit:
    results  = BIOC_PRAM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PRAM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PRAM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PRAM.out.versions  // channel: path(versions.yml)
}
