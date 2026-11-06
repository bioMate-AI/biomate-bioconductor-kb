#!/usr/bin/env nextflow
nextflow.enable.dsl=2
process MAKE_NAME {
    output:
    path "name.txt", emit: name
    script:
    """
    echo "World" > name.txt
    """
}
process SAY_HELLO {
    input:
    path name_file
    output:
    path "hello.txt"
    script:
    """
    sed 's/.*/Hello, &!/' ${name_file} > hello.txt
    """
}
workflow {
    MAKE_NAME()
    SAY_HELLO(MAKE_NAME.out.name)
}
