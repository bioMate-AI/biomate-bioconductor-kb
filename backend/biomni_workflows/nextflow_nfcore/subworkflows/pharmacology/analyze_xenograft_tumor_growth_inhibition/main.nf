#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_xenograft_tumor_growth_inhibition
 * Analyze tumor growth inhibition in xenograft models across different treatment groups.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.data_path = null  // Required: path to CSV/TSV with tumor volume measurements (columns: Mouse_ID, Treatment, Day, Volume_mm3)
params.time_column = 'Day'
params.volume_column = 'Volume_mm3'
params.group_column = 'Treatment'
params.subject_column = 'Mouse_ID'
params.output_dir = './results'

process ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_xenograft_tumor_growth_inhibition_results.json"), emit: results
    tuple val(meta), path("analyze_xenograft_tumor_growth_inhibition_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DATA_PATH="${params.data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_COLUMN="${params.time_column?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VOLUME_COLUMN="${params.volume_column?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GROUP_COLUMN="${params.group_column?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SUBJECT_COLUMN="${params.subject_column?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import os
import numpy as np
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def analyze_xenograft_tumor_growth_inhibition(
    data_path,
    time_column,
    volume_column,
    group_column,
    subject_column,
    output_dir="./results",
):
    '''Analyze tumor growth inhibition in xenograft models across different treatment groups.

    Parameters
    ----------
    data_path : str
        Path to CSV or TSV file containing tumor volume measurements. The file should have columns for
        time, volume, treatment group, and subject ID
    time_column : str
        Name of the column containing time points (e.g., 'Day', 'Time')
    volume_column : str
        Name of the column containing tumor volume measurements
    group_column : str
        Name of the column containing treatment group labels
    subject_column : str
        Name of the column containing subject/mouse identifiers
    output_dir : str, optional
        Directory to save output files (default: "./results")

    Returns
    -------
    str
        Research log summarizing the analysis steps, findings, and generated file paths

    '''
    import os

    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    import statsmodels.api as sm
    from scipy import stats
    from statsmodels.formula.api import ols
    from statsmodels.stats.multicomp import pairwise_tukeyhsd

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize research log
    log = "# Xenograft Tumor Growth Inhibition Analysis\\n\\n"

    # Load data from file
    log += "## 1. Data Loading and Summary\\n\\n"
    try:
        if data_path.endswith(".csv"):
            data_df = pd.read_csv(data_path)
        elif data_path.endswith((".tsv", ".txt")):
            data_df = pd.read_csv(data_path, sep="\\t")
        else:
            log += "Error: Unsupported file format. Please provide a CSV or TSV file.\\n"
            return log
        log += f"Successfully loaded tumor growth data from {data_path}\\n"
    except Exception as e:
        log += f"Error loading data: {str(e)}\\n"
        return log

    # Validate required columns
    required_columns = [time_column, volume_column, group_column, subject_column]
    missing_columns = [col for col in required_columns if col not in data_df.columns]
    if missing_columns:
        log += f"Error: Missing required columns: {', '.join(missing_columns)}\\n"
        return log

    # Get unique groups and time points
    groups = data_df[group_column].unique()
    time_points = sorted(data_df[time_column].unique())
    n_groups = len(groups)
    log += f"- Number of treatment groups: {n_groups} ({', '.join(map(str, groups))})\\n"
    log += f"- Number of time points: {len(time_points)}\\n"
    log += f"- Number of subjects: {data_df[subject_column].nunique()}\\n"
    log += f"- Total number of measurements: {len(data_df)}\\n\\n"

    # 2. Calculate group statistics at each time point
    log += "## 2. Tumor Growth Analysis\\n\\n"

    # Group statistics
    stats_df = (
        data_df.groupby([group_column, time_column])[volume_column]
        .agg(mean="mean", sem=lambda x: stats.sem(x), count="count")
        .reset_index()
    )

    # Save group statistics
    stats_file = os.path.join(output_dir, "tumor_volume_statistics.csv")
    stats_df.to_csv(stats_file, index=False)
    log += f"Group statistics saved to: {stats_file}\\n\\n"

    # 3. Calculate tumor growth rates
    log += "## 3. Tumor Growth Rate Analysis\\n\\n"

    growth_rates = {}
    for group in groups:
        group_data = data_df[data_df[group_column] == group]

        # Calculate growth rate for each subject
        subject_growth_rates = []
        for subject in group_data[subject_column].unique():
            subject_data = group_data[group_data[subject_column] == subject]

            if len(subject_data) >= 2:
                # Simple linear regression for growth rate
                x = subject_data[time_column].values
                y = subject_data[volume_column].values
                slope, _, _, _, _ = stats.linregress(x, y)
                subject_growth_rates.append(slope)

        growth_rates[group] = subject_growth_rates
        mean_rate = np.mean(subject_growth_rates)
        sem_rate = stats.sem(subject_growth_rates)

        log += (
            f"- {group}: Mean growth rate = {mean_rate:.2f} ± {sem_rate:.2f} mm³/day (n={len(subject_growth_rates)})\\n"
        )

    # 4. Calculate Tumor Growth Inhibition (TGI)
    log += "\\n## 4. Tumor Growth Inhibition (TGI)\\n\\n"

    # Identify control group (assuming the first group is control)
    control_group = groups[0]
    log += f"Control group: {control_group}\\n\\n"

    # Calculate TGI for the final time point
    final_time = max(time_points)
    final_data = data_df[data_df[time_column] == final_time]

    control_final_mean = final_data[final_data[group_column] == control_group][volume_column].mean()

    tgi_results = {}
    for group in groups:
        if group == control_group:
            continue

        group_final_mean = final_data[final_data[group_column] == group][volume_column].mean()
        tgi = ((control_final_mean - group_final_mean) / control_final_mean) * 100
        tgi_results[group] = tgi

        log += f"- {group}: TGI = {tgi:.1f}% (relative to {control_group})\\n"

    # 5. Statistical Analysis
    log += "\\n## 5. Statistical Analysis\\n\\n"

    # Repeated measures ANOVA
    log += "### Repeated Measures ANOVA\\n\\n"

    try:
        # Prepare data for repeated measures ANOVA
        formula = f"{volume_column} ~ C({group_column}) * C({time_column}) + C({subject_column})"
        model = ols(formula, data=data_df).fit()
        anova_table = sm.stats.anova_lm(model, typ=2)

        # Save ANOVA results
        anova_file = os.path.join(output_dir, "repeated_measures_anova.csv")
        anova_table.to_csv(anova_file)

        log += f"ANOVA results saved to: {anova_file}\\n\\n"

        # Extract p-values
        group_effect_p = anova_table.loc[f"C({group_column})", "PR(>F)"]
        time_effect_p = anova_table.loc[f"C({time_column})", "PR(>F)"]
        interaction_p = anova_table.loc[f"C({group_column}):C({time_column})", "PR(>F)"]

        log += f"- Treatment effect: p = {group_effect_p:.4f}\\n"
        log += f"- Time effect: p = {time_effect_p:.4f}\\n"
        log += f"- Treatment × Time interaction: p = {interaction_p:.4f}\\n\\n"

        # Post-hoc analysis at final time point
        log += "### Post-hoc Analysis (Final Time Point)\\n\\n"

        # Perform Tukey's HSD test
        tukey = pairwise_tukeyhsd(endog=final_data[volume_column], groups=final_data[group_column], alpha=0.05)

        # Save Tukey results
        tukey_file = os.path.join(output_dir, "tukey_posthoc_results.txt")
        with open(tukey_file, "w") as f:
            f.write(str(tukey.summary()))

        log += f"Tukey's HSD results saved to: {tukey_file}\\n\\n"

        # Summarize significant comparisons
        tukey_df = pd.DataFrame(data=tukey._results_table.data[1:], columns=tukey._results_table.data[0])

        sig_pairs = tukey_df[tukey_df["p-adj"] < 0.05]
        if len(sig_pairs) > 0:
            log += "Significant pairwise comparisons:\\n"
            for _, row in sig_pairs.iterrows():
                log += f"- {row['group1']} vs {row['group2']}: p = {row['p-adj']:.4f}\\n"
        else:
            log += "No significant pairwise comparisons found.\\n"

    except Exception as e:
        log += f"Error in statistical analysis: {str(e)}\\n"

    # 6. Generate tumor growth curves
    log += "\\n## 6. Tumor Growth Visualization\\n\\n"

    plt.figure(figsize=(10, 6))

    for group in groups:
        group_stats = stats_df[stats_df[group_column] == group]
        plt.errorbar(
            group_stats[time_column],
            group_stats["mean"],
            yerr=group_stats["sem"],
            label=group,
            capsize=3,
            marker="o",
        )

    plt.xlabel(f"{time_column} (days)")
    plt.ylabel(f"Tumor Volume ({volume_column})")
    plt.title("Xenograft Tumor Growth Curves")
    plt.legend()
    plt.grid(True, linestyle="--", alpha=0.7)

    # Save the plot
    plot_file = os.path.join(output_dir, "tumor_growth_curves.png")
    plt.savefig(plot_file, dpi=300, bbox_inches="tight")
    plt.close()

    log += f"Tumor growth curve plot saved to: {plot_file}\\n"

    # 7. Conclusion
    log += "\\n## 7. Conclusion\\n\\n"

    # Summarize most effective treatment
    if tgi_results:
        best_treatment = max(tgi_results.items(), key=lambda x: x[1])
        log += f"The most effective treatment was {best_treatment[0]} with a tumor growth inhibition of {best_treatment[1]:.1f}%.\\n"

    # Statistical significance summary
    try:
        if group_effect_p < 0.05:
            log += "Statistical analysis confirmed significant differences between treatment groups.\\n"
        else:
            log += "No statistically significant differences were found between treatment groups.\\n"
    except Exception:
        pass

    return log

# Execute the function
try:
    result = analyze_xenograft_tumor_growth_inhibition(
        data_path=auto_convert(os.environ.get("PARAM_DATA_PATH", "")),
        time_column=auto_convert(os.environ.get("PARAM_TIME_COLUMN", "")),
        volume_column=auto_convert(os.environ.get("PARAM_VOLUME_COLUMN", "")),
        group_column=auto_convert(os.environ.get("PARAM_GROUP_COLUMN", "")),
        subject_column=auto_convert(os.environ.get("PARAM_SUBJECT_COLUMN", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "analyze_xenograft_tumor_growth_inhibition",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_xenograft_tumor_growth_inhibition_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_xenograft_tumor_growth_inhibition_output.txt", "w") as f:
    f.write("Biomni: Analyze Xenograft Tumor Growth Inhibition" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "analyze_xenograft_tumor_growth_inhibition"
    END_VERSIONS
    """
}

workflow ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION(ch_input)

    emit:
    results = ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.results
    output = ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.output
    versions = ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION_WORKFLOW(ch_input)

    ANALYZE_XENOGRAFT_TUMOR_GROWTH_INHIBITION_WORKFLOW.out.output.view { "Output: $it" }
}
