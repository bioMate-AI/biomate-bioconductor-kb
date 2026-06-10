library(ggkegg)

# Create bpsp00270 (KEGG Pathway KGML format)
# The workflow checks for the existence of this file to avoid downloading it.
kgml_content <- '<?xml version="1.0"?>
<!DOCTYPE pathway SYSTEM "https://www.kegg.jp/kegg/xml/KGML_v0.7.2_.dtd">
<pathway name="path:bpsp00270" org="bpsp" number="00270"
         title="Test Pathway"
         image="https://www.kegg.jp/kegg/pathway/bpsp/bpsp00270.png"
         link="https://www.kegg.jp/kegg-bin/show_pathway?bpsp00270">
    <entry id="1" name="bpsp:1234" type="gene"
           link="https://www.kegg.jp/dbget-bin/www_bget?bpsp:1234">
        <graphics name="Gene1" fgcolor="#000000" bgcolor="#BFFFBF"
                  type="rectangle" x="100" y="100" width="46" height="17"/>
    </entry>
</pathway>'
writeLines(kgml_content, "bpsp00270")

# Create N00002 (KEGG Network flat file format)
# The workflow checks for the existence of this file to avoid downloading it.
network_content <- 'ENTRY       N00002                      Network
NAME        Test Network
DEFINITION  gene1 -> gene2
///
'
writeLines(network_content, "N00002")