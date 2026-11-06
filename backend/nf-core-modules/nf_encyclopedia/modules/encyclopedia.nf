/* Execute EncyclopeDIA
 *
 * Bioconda includes a wrapper script that makes it difficult to find the jar
 * file. This function calls Java manually, only in the case that a custom
 * jar file is provided for EncyclopeDIA.
 */
def execEncyclopedia(mem) {
    def xmx = "-Xmx${mem.toGiga()-1}G"
    if (params.encyclopedia.jar) {
        return "java -Djava.aws.headless=true ${xmx} -jar ${params.encyclopedia.jar}"
    } else {
        return "EncyclopeDIA ${xmx}"
    }
}


// A utility function for creating the prefixes:
def stem(suffix) {
    return "encyclopedia.${suffix}"
}


process ENCYCLOPEDIA_SEARCH {
    publishDir "${params.result_dir}/${group}/elib", pattern: '*.elib', failOnError: true
    publishDir "${params.result_dir}/${group}/logs", pattern: '*.log', failOnError: true
    label 'process_medium'

    input:
        tuple val(group), path(mzml_gz_file)
        path(library_file)
        path(fasta_file)

    output:
        tuple(
            val(group),
            path("${mzml_gz_file.baseName}.elib"),
            path("${file(mzml_gz_file.baseName).baseName}.dia"),
            path("${mzml_gz_file.baseName}.features.txt.gz"),
            path("${mzml_gz_file.baseName}.encyclopedia.txt"),
            path("${mzml_gz_file.baseName}.encyclopedia.decoy.txt"),
            path("${mzml_gz_file.baseName}.local.log"),
        )

    script:
    """
    gzip -df ${mzml_gz_file}
    ${execEncyclopedia(task.memory)} \\
        -i ${mzml_gz_file.baseName} \\
        -f ${fasta_file} \\
        -l ${library_file} \\
        ${params.encyclopedia.args} \\
        ${params.encyclopedia.local.args} \\
    | tee ${mzml_gz_file.baseName}.local.log
    gzip ${mzml_gz_file.baseName}.features.txt
    """

    stub:
    """
    echo "${library_file}"
    mkdir logs
    touch ${mzml_gz_file.baseName}.elib
    touch ${file(mzml_gz_file.baseName).baseName}.dia
    touch ${mzml_gz_file.baseName}.features.txt.gz
    touch ${mzml_gz_file.baseName}.encyclopedia.txt
    touch ${mzml_gz_file.baseName}.encyclopedia.decoy.txt
    echo "${library_file}" > ${mzml_gz_file.baseName}.local.log
    """
}


process ENCYCLOPEDIA_AGGREGATE {
    publishDir "${params.result_dir}/${group}/elib", pattern: '*.elib', failOnError: true
    publishDir "${params.result_dir}/${group}/logs", pattern: '*.log', failOnError: true
    publishDir "${params.result_dir}/${group}/results", pattern: '*.txt', failOnError: true
    publishDir "${params.result_dir}/${group}/reports", pattern: '*.csv', failOnError: true
    label 'process_high'

    input:
        tuple(
            val(group),
            path(local_elib_files),
            path(local_dia_files),
            path(local_feature_files),
            path(local_encyclopedia_files),
        )
        path(library_file)
        path(fasta_file)
        val output_suffix
        val align

    output:
        tuple(
            val(group),
            path("${stem(output_suffix)}.elib"),
            path("${stem(output_suffix)}.global.log"),
            path("${output_suffix}_detection_summary.csv"),
            emit: "lib"
        )
        tuple(
            val(group),
            path("${stem(output_suffix)}.peptides.txt"),
            path("${stem(output_suffix)}.proteins.txt"),
            emit: "quant",
            optional: true
        )

    script:
    """
    # Decompress the feture files:
    gzip -df ${local_feature_files}
    find * -name '*\\.mzML\\.*' -exec bash -c 'mv \$0 \${0/\\.mzML/\\.dia}' {} \\;

    # Run EncyclopeDIA:
    ${execEncyclopedia(task.memory)} \\
        -libexport \\
        -o ${stem(output_suffix)}.elib \\
        -i ./ \\
        -f ${fasta_file} \\
        -l ${library_file} \\
        ${params.encyclopedia.args} \\
        ${params.encyclopedia.global.args} \\
        -a ${align} \\
    | tee ${stem(output_suffix)}.global.log

    # Better file names:
    if [ "${align}" = true ]; then
        mv ${stem(output_suffix)}.elib.peptides.txt ${stem(output_suffix)}.peptides.txt
        mv ${stem(output_suffix)}.elib.proteins.txt ${stem(output_suffix)}.proteins.txt
    fi

    # Count peptides and proteins:
    echo 'Finding unique peptides and proteins...'
    echo 'Run,Unique Proteins,Unique Peptides' \\
        > ${output_suffix}_detection_summary.csv
    find * -name '*\\.elib' -exec bash -c 'count_peptides_proteins.sh \$0 \\
        >> ${output_suffix}_detection_summary.csv' {} \\;
    echo 'DONE!'
    """

    stub:
    """
    touch ${stem(output_suffix)}.elib

    if [ "${align}" = true ]; then
        touch ${stem(output_suffix)}.peptides.txt
        touch ${stem(output_suffix)}.proteins.txt
    fi

    echo "${library_file}" > ${stem(output_suffix)}.global.log
    touch ${output_suffix}_detection_summary.csv
    """
}
