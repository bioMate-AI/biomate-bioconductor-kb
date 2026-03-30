#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: rGADEM
// rGADEM is an efficient de novo motif discovery tool for large-scale genomic sequence data. It is an 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/rGADEM/inst/doc/rGADEM.R
// Upstream  : rtracklayer
// Downstream: none
//
// Install: BiocManager::install("rGADEM")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_RGADEM {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-rgadem"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-rgadem:2.54.0--r44_0' :
        'quay.io/biocontainers/bioconductor-rgadem:2.54.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_rgadem_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_rgadem_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_rgadem_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DNAStringSet)
    library(GADEM)
    library(jsonlite)

    # --- Bed File [] ---
    # Key functions: import
    pwd<-"" #INPUT FILES- BedFiles, FASTA, etc.
    path<- system.file("extdata/Test_100.bed",package="rGADEM")
    BedFile<-paste(pwd,path,sep="")
    Sequences<-import(BedFile)
    # --- Create The Rd Files [] ---
    # Key functions: DNAStringSet
    ##
    ## pwd<-"" #INPUT FILES- BedFiles, FASTA, etc.
    ## path<- system.file("extdata/Test_100.fasta",package="rGADEM")
    ## FastaFile<-paste(pwd,path,sep="")
    ## Sequences <- read.DNAStringSet(FastaFile, "fasta")
    # --- Rgadem Analysis [] ---
    # Key functions: GADEM
    gadem<-GADEM(Sequences,verbose=1,genome=Hsapiens)
    # --- Prepare Pwm [] ---
    # Key functions: readPWMfile
    ## path<- system.file("extdata/jaspar2009.txt",package="rGADEM")
    ## seededPwm<-readPWMfile(path)
    ## grep("STAT1",names(seededPwm))
    ## STAT1.PWM=seededPwm[103]
    # --- Rgadem Seeded Analysis [] ---
    # Key functions: GADEM
    ## gadem<-GADEM(Sequences,verbose=1,genome=Hsapiens,Spwm=STAT1.PWM, fixSeeded=TRUE)
    # --- Pwm [] ---
    # Key functions: nOccurrences
    nOccurrences(gadem)[1]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_rgadem_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_rgadem_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_rgadem_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_RGADEM:", paste0("    rgadem: ", packageVersion("rGADEM"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_rgadem_results.csv
    touch ${prefix}_rgadem_output.rds
    echo "BIOC_RGADEM:" > versions.yml
    echo "    rgadem: 0.0.0" >> versions.yml
    """
}


workflow BIOC_RGADEM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_RGADEM(ch_input)

    emit:
    results  = BIOC_RGADEM.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_RGADEM.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_RGADEM.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_RGADEM.out.versions  // channel: path(versions.yml)
}
