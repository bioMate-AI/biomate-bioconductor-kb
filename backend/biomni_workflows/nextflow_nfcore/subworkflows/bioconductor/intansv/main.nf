#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: intansv
// This package provides efficient tools to read and integrate structural variations predicted by popul
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/intansv/inst/doc/intansvOverview.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("intansv")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_INTANSV {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-intansv"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-intansv:1.46.0--r44_0' :
        'quay.io/biocontainers/bioconductor-intansv:1.46.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_intansv_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_intansv_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_intansv_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(intansv)
    library(jsonlite)

    # --- Read In Results Of Breakdancer [] ---
    # Key functions: readBreakDancer
    breakdancer.file.path <- system.file("extdata/ZS97.breakdancer.sv",
                                   package="intansv")
    breakdancer.file.path
    breakdancer <- readBreakDancer(breakdancer.file.path)
    str(breakdancer)
    # --- Read In Results Of Cnvnator [] ---
    # Key functions: readCnvnator
    cnvnator.dir.path <- system.file("extdata/cnvnator", package="intansv")
    cnvnator.dir.path
    cnvnator <- readCnvnator(cnvnator.dir.path)
    str(cnvnator)
    # --- Read In Results Of Svseq2 [] ---
    # Key functions: readSvseq
    svseq.dir.path <- system.file("extdata/svseq2", package="intansv")
    svseq.dir.path
    svseq <- readSvseq(svseq.dir.path)
    str(svseq)
    # --- Read In Results Of Delly [] ---
    # Key functions: readDelly
    delly.file.path <- system.file("extdata/ZS97.DELLY.vcf", package="intansv")
    delly.file.path
    delly <- readDelly(delly.file.path)
    str(delly)
    # --- Read In Results Of Pindel [] ---
    # Key functions: readPindel
    pindel.dir.path <- system.file("extdata/pindel", package="intansv")
    pindel.dir.path
    pindel <- readPindel(pindel.dir.path)
    str(pindel)
    # --- Read In Results Of Lumpy [] ---
    # Key functions: readLumpy
    lumpy.file.path <- system.file("extdata/ZS97.LUMPY.vcf",
                       package="intansv")
    lumpy.file.path
    lumpy <- readLumpy(lumpy.file.path)
    str(lumpy)
    # --- Read In Results Of Softsearch [] ---
    # Key functions: readSoftSearch
    softSearch.file.path <- system.file("extdata/ZS97.softsearch", package="intansv")
    softSearch.file.path
    softSearch <- readSoftSearch(softSearch.file.path)
    str(softSearch)
    # --- Methodsmerge [] ---
    # Key functions: methodsMerge
    sv_all_methods <- methodsMerge(breakdancer, pindel, cnvnator, delly, svseq)
    str(sv_all_methods)
    # --- Read In Annotation File Into R [] ---
    # Key functions: file
    anno.file.path <- system.file("extdata/chr05_chr10.anno.txt", package="intansv")
    anno.file.path
    msu_gff_v7 <- read.table(anno.file.path, head=TRUE, as.is=TRUE)
    head(msu_gff_v7)
    # --- Sv Annotation [] ---
    # Key functions: llply
    sv_all_methods.anno <- llply(sv_all_methods,svAnnotation,
                                 genomeAnnotation=msu_gff_v7)
    names(sv_all_methods.anno)
    head(sv_all_methods.anno$del)
    # --- Genomic Distribution [] ---
    # Key functions: plotChromosome
    genome.file.path <- system.file("extdata/chr05_chr10.genome.txt", package="intansv")
    genome.file.path
    genome <- read.table(genome.file.path, head=TRUE, as.is=TRUE)
    plotChromosome(genome, sv_all_methods,1000000)
    # --- Region Visualization [] ---
    # Key functions: plotRegion
    head(msu_gff_v7, n=3)
    plotRegion(sv_all_methods,msu_gff_v7, "chr05", 1, 200000)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_intansv_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_intansv_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_intansv_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_INTANSV:", paste0("    intansv: ", packageVersion("intansv"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_intansv_results.csv
    touch ${prefix}_intansv_output.rds
    echo "BIOC_INTANSV:" > versions.yml
    echo "    intansv: 0.0.0" >> versions.yml
    """
}


workflow BIOC_INTANSV_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_INTANSV(ch_input)

    emit:
    results  = BIOC_INTANSV.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_INTANSV.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_INTANSV.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_INTANSV.out.versions  // channel: path(versions.yml)
}
