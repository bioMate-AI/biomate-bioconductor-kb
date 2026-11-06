# Parameters for nf-encyclopedia

The following parameters can be used to customize various aspects of the nf-encyclopedia pipeline. 
These may either be specified as command line arguments, prefixed with `--`, or in a new NextFlow configuration file.
For example:
```title="pipeline.config"
params {
    input = 'input.csv'
    dlib  = 'proteins.dlib'
    fasta = 'proteins.fasta'
}
```

## Input/Output Parameters
- **input** (string, *required*) - A comma-separated values (CSV) file specifying the mass spectrometry data files to be analyzed. This file must have at least two columns: `file` `chrlib`. 
  The `file` columns contains the paths to the mass spectrometry data files in formats supported by MSconvert. 
  The `chrlib` column contains either `true` or `false` depending on whether a file should be considered part of a chromatogram library or not. 
  The optional `group` maybe used to specify which chromatogram library files should be used to analyze each quantitative run. 
  Optionally, `condition` and `bioreplicate` columns can be included and will be used by MSstats.
  These columns are ignored for chromatogram library files.
  See the [MSstats documentation](https://msstats.org/msstats-2/) for details.
  Here is an example (note that the `condition`, `bioreplicate`, and `group` are optional):

    | file     | chrlib | condition | bioreplicate | group  |
    |----------|--------|-----------|--------------|--------|
    | lib1.raw | true   |           |              | batch1 |
    | lib2.raw | true   |           |              | batch2 |
    | trt1.raw | false  | treatment | patient1     | batch1 |
    | trt2.raw | false  | treatment | patient2     | batch2 |
    | ctr1.raw | false  | control   | patient3     | batch1 |
    | ctr2.raw | false  | control   | patient4     | batch2 |


- **dlib** (string, *required*) -  A spectral library in EncyclopeDIA's DLIB format. 
  See the [EncyclopeDIA](https://bitbucket.org/searleb/encyclopedia/wiki/Home)  documentation for details.

- **fasta** (string, *required*) -  The FASTA containing the subset of proteins sequences for which to search.
 
- **contrasts** (string, *required*) - The contrast matrix defining the hypothesis tests to perform with MSstats provided as a comma-separated values (CSV) file. 
  The columns of the file should denote conditions from the `input` CSV file.
  The first column defines the name of each hypothesis test.
  See the  [MSstats documentation](https://msstats.org/msstats-2/) for more details.
  This is an example contrast matrix for the input example above:
  
    |                    | treatment | control |
    |--------------------|----------:|--------:|
    | TreatmentVsControl |         1 |      -1 |

-  **result_dir** (string) - Where results will be saved. *Default:* `'results'`
-  **report_dir** (string) -  Where reports will be saved. *Default:* `'reports'`
-  **mzml_dir** (string) -  Where mzML files will be saved. *Default:* `'mzml'`
-  **email** (string) - An email to alert on completion.

## Grouping Parameters
 
 - **aggregate** (boolean) - Aggregate groups into a single analysis. 
   If `true`, each group will be searched with EncyclopeDIA separately against their respective chomatogram library.
   These search results are subsequently aggregated and the false discovery rate (FDR) is estimated for the combined groups.
   If `false`, the groups are analyzed individually and FDR is estimated within each group.
   *Default:*  `false`
 
- **agg_name** (string) - The file prefix to use for the aggregated data. *Default:* `'aggregated'`
 

## MSconvert Parameters

- **msconvert.demultiplex** (boolean) - Demultiplex overlapping DIA windows. *Default:* `true`
- **msconvert.force** (boolean) - Force existing mzML files to be reconverted. *Default* `false`

## EncyclopeDIA Parameters

- **encyclopedia.chrlib_suffix** (string) - The suffix to append to chromatogram library result files.
  *Default:* `'chrlib'`

-  **encyclopedia.quant_suffix** (string) - The suffix to append to quantitative result files.
   *Default* `'quant'`

- **encyclopedia.args** (string) -  Command line arguments to pass to all EncyclopeDIA analyses.
  The default attempts to match the defaults from the EncyclopeDIA graphical user interface.
  *Default:* `'-percolatorVersion v3-01 -quantifyAcrossSamples true -scoringBreadthType window'`

- **encyclopedia.local.args** (string) - Additional command line arguments to use when searching files.
    *Default:* `''`

- **encyclopedia.global.args** (string) -  Additional command line arguments to use when quantifying detected peptides across multiple runs.
    *Default:*  `''`

- **encyclopedia.jar** (string) - The location of the EncyclopeDIA  executable. 
  Use `null` if EncyclopeDIA was installed with bioconda.
  The default is the location in the Docker container.
    *Default:* `'/code/encyclopedia.jar'`

## MSstats Parameters

- **msstats.enabled** (boolean) - Enable MSstats protein quantification. *Default:* `true`

- **msstats.normalization** (string) - The normalization method used by MSstats.
  Must be one of `'equalizeMedians'`, `'quantile'`, or `'none'`.
  *Default:* `'equalizeMedians'`

- **msstats.reports** (boolean) - Generate MSstats reports. *Default:* `false`

## Resource Parameters

Change these to reflect your compute environment.

- **max_memory** (string) - The maximum memory allowed for each process. *Default:* `'128.GB'`
- **max_cpus** (integer) - The maximum number of CPUs for each process. *Default:* `16`
- **max_time** (string) - The maximum execution time for each process. *Default:* `'240.h'`
