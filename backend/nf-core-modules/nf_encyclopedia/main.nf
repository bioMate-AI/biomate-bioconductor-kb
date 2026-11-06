#!/usr/bin/env nextflow

nextflow.enable.dsl = 2

// Subworkflows
include { CONVERT_TO_MZML } from "./subworkflows/msconvert"
include {
    BUILD_CHROMATOGRAM_LIBRARY;
    PERFORM_QUANT;
    PERFORM_AGGREGATE_QUANT
} from "./subworkflows/encyclopedia"

// Modules
include { MSSTATS } from "./modules/msstats"


//
// Used for email notifications
//
def email() {
    // Create the email text:
    def (subject, msg) = TalusTemplate.email(workflow, params)
    // Send the email:
    if (params.email) {
        sendMail(
            to: "$params.email",
            subject: subject,
            body: msg
        )
    }
}


//
// Use the DLIB when the ELIB is unavailable.
//
def replace_missing_elib(elib) {
    if (elib == null) {
        return file(params.dlib)
    }
    return elib
}


//
// The main workflow
//
workflow {
    input = file(params.input, checkIfExists: true)
    fasta = file(params.fasta, checkIfExists: true)
    dlib = file(params.dlib, checkIfExists: true)

    // Optional contrasts arg:
    if ( params.contrasts != null ) {
        contrasts = file(params.contrasts, checkIfExists: true)
    } else {
        contrasts = file("${baseDir}/assets/NO_FILE", checkIfExists: true)
    }

    // Get the narrow and wide files:
    ms_files = Channel
        .fromPath(params.input, checkIfExists: true)
        .splitCsv(header: true, strip: true)
        .multiMap { it ->
            runs: it.file
            meta: tuple(
                it.file,
                it.chrlib.toBoolean(),
                it.group ?: '',  // no group if missing
            )
        }

    if ( !ms_files.runs ) {
        error "No MS data files were provided. Nothing to do."
    }

    // Convert raw files to gzipped mzML and group them by experiment.
    // The chrlib and quant channels take the following form:
    // [[file_ids], [mzml_gz_files], is_chrlib, group]
    CONVERT_TO_MZML(ms_files.runs)
    | join(ms_files.meta)
    | groupTuple(by: [2, 3])
    | branch {
        chrlib: it[2]
        quant: !it[2]
    }
    | set { mzml_gz_files }

    // Build chromatogram libraries with EncyclopeDIA:
    // The output is [group, elib]
    BUILD_CHROMATOGRAM_LIBRARY(mzml_gz_files.chrlib, dlib, fasta)
    | set { chrlib_elib_files }

    // Group quant files with either corresponding library ELIB.
    // If none exists, use the DLIB.
    // The output is [group, [quant_mzml_gz_files], elib_file]
    mzml_gz_files.quant
    | map { tuple it[3], it[1] }
    | join(chrlib_elib_files, remainder: true)
    | map { tuple it[0], it[1], replace_missing_elib(it[2]) }
    | set { quant_files }

    // Analyze the quantitative runs with EncyclopeDIA.
    // The output has two channels:
    // local -> [group, [local_elib_files], [mzml_gz_files]]
    // global -> [group, peptides, proteins] or null
    PERFORM_QUANT(quant_files, dlib, fasta, params.aggregate)
    | set { quant_results }

    // Perform an aggregate analysis on all files if needed:
    if ( params.aggregate ) {
        // Aggregate quantitative runs with EncyclopeDIA.
        // The output has one channel:
        // global -> [agg_name, peptides, proteins] or null
        PERFORM_AGGREGATE_QUANT(quant_results.local, dlib, fasta)
        | set { enc_results }
    } else {
        quant_results | set{ enc_results }
    }

    // Run MSstats
    if ( params.msstats.enabled ) {
        MSSTATS(enc_results.global, input, contrasts)
    }
}


//
// This is a dummy workflow for testing
//
workflow dummy {
    println "This is a workflow that doesn't do anything."
}

// Email notifications:
workflow.onComplete { email() }
