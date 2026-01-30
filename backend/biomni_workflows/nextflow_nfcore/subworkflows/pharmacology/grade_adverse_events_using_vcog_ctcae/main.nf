#!/usr/bin/env nextflow
/*
 * pharmacology/grade_adverse_events_using_vcog_ctcae
 * Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Uses inline-generated mock clinical data (created in script)
params.clinical_data_file = 'mock_clinical_data.csv'

process GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("grade_adverse_events_using_vcog_ctcae_results.json"), emit: results
    tuple val(meta), path("grade_adverse_events_using_vcog_ctcae_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CLINICAL_DATA_FILE="${params.clinical_data_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Create mock clinical data for testing
    python3 << 'MOCKEOF'
import pandas as pd
import numpy as np

# Create mock VCOG-CTCAE adverse event data
np.random.seed(42)
n_samples = 50

data = {
    'subject_id': [f'DOG{i:03d}' for i in np.random.choice(range(1, 21), n_samples)],
    'time_point': np.random.choice(['Day1', 'Day7', 'Day14', 'Day21', 'Day28'], n_samples),
    'symptom': np.random.choice(['anemia', 'neutropenia', 'vomiting', 'diarrhea', 'fever', 'anorexia'], n_samples),
    'severity': np.random.choice(['none', 'mild', 'moderate', 'severe'], n_samples, p=[0.3, 0.4, 0.2, 0.1]),
    'measurement': np.round(np.random.uniform(0.5, 10, n_samples), 2)
}

df = pd.DataFrame(data)
df.to_csv('mock_clinical_data.csv', index=False)
print(f"Created mock clinical data with {len(df)} records")
MOCKEOF

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
from datetime import datetime
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



def grade_adverse_events_using_vcog_ctcae(clinical_data_file):
    '''Grade and monitor adverse events in animal studies using the VCOG-CTCAE standard.

    Parameters
    ----------
    clinical_data_file : str
        Path to a CSV file containing clinical evaluation data with columns:
        subject_id, time_point, symptom, severity, measurement (optional)

    Returns
    -------
    str
        A research log summarizing the adverse event grading process and results.
        The graded events are saved to 'vcog_ctcae_graded_events.csv'.

    '''
    import json
    from datetime import datetime

    import pandas as pd

    # Initialize the research log
    log = "# Adverse Event Grading using VCOG-CTCAE v1.1\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Step 1: Load the clinical data
    log += "## Step 1: Loading clinical evaluation data\\n"
    try:
        data = pd.read_csv(clinical_data_file)
        log += f"Successfully loaded data from {clinical_data_file}\\n"
        log += f"Total records: {len(data)}\\n"
        log += f"Columns found: {', '.join(data.columns)}\\n\\n"
    except Exception as e:
        log += f"Error loading data: {str(e)}\\n"
        return log

    # Step 2: Define VCOG-CTCAE grading criteria
    log += "## Step 2: Applying VCOG-CTCAE grading criteria\\n"

    # Comprehensive VCOG-CTCAE grading criteria based on VCOG-CTCAE v1.1
    vcog_criteria = {
        # Hematologic
        "neutropenia": {
            "description": "Neutrophil count decrease",
            "unit": "cells/µL",
            "grades": {
                0: {"criteria": "≥ 1500", "range": [1500, float("inf")]},
                1: {"criteria": "1000 - <1500", "range": [1000, 1500]},
                2: {"criteria": "500 - <1000", "range": [500, 1000]},
                3: {"criteria": "100 - <500", "range": [100, 500]},
                4: {"criteria": "<100", "range": [0, 100]},
                5: {"criteria": "Death due to neutropenic sepsis", "range": None},
            },
        },
        "anemia": {
            "description": "Hemoglobin decrease",
            "unit": "g/dL",
            "grades": {
                0: {"criteria": "Within reference range", "range": [10, float("inf")]},
                1: {"criteria": "Mild; clinical signs not present", "range": [8, 10]},
                2: {"criteria": "Moderate; clinical signs present", "range": [6.5, 8]},
                3: {"criteria": "Severe; transfusion indicated", "range": [5, 6.5]},
                4: {"criteria": "Life-threatening", "range": [0, 5]},
                5: {"criteria": "Death", "range": None},
            },
        },
        "thrombocytopenia": {
            "description": "Platelet count decrease",
            "unit": "cells/µL",
            "grades": {
                0: {"criteria": "≥ 100,000", "range": [100000, float("inf")]},
                1: {"criteria": "50,000 - <100,000", "range": [50000, 100000]},
                2: {"criteria": "25,000 - <50,000", "range": [25000, 50000]},
                3: {"criteria": "10,000 - <25,000", "range": [10000, 25000]},
                4: {"criteria": "<10,000 or spontaneous bleeding", "range": [0, 10000]},
                5: {"criteria": "Death", "range": None},
            },
        },
        # Gastrointestinal
        "vomiting": {
            "description": "Vomiting frequency",
            "unit": "episodes per 24h period",
            "grades": {
                0: {"criteria": "None", "range": [0, 0]},
                1: {
                    "criteria": "1-2 episodes in 24h; medical intervention not indicated",
                    "range": [1, 2],
                },
                2: {"criteria": "3-5 episodes in 24h; ≤3 days", "range": [3, 5]},
                3: {
                    "criteria": ">5 episodes in 24h; >3 days; hospitalization indicated",
                    "range": [6, float("inf")],
                },
                4: {"criteria": "Life-threatening consequences", "range": None},
                5: {"criteria": "Death", "range": None},
            },
        },
        "diarrhea": {
            "description": "Diarrhea frequency",
            "unit": "episodes per 24h period",
            "grades": {
                0: {"criteria": "None", "range": [0, 0]},
                1: {
                    "criteria": "Increase of <4 stools per day over baseline",
                    "range": [1, 3],
                },
                2: {
                    "criteria": "Increase of 4-6 stools per day over baseline",
                    "range": [4, 6],
                },
                3: {
                    "criteria": "Increase of ≥7 stools per day; hospitalization indicated",
                    "range": [7, float("inf")],
                },
                4: {"criteria": "Life-threatening consequences", "range": None},
                5: {"criteria": "Death", "range": None},
            },
        },
        "anorexia": {
            "description": "Appetite/food intake decrease",
            "unit": "percent of normal intake",
            "grades": {
                0: {"criteria": "Normal", "range": [100, float("inf")]},
                1: {"criteria": "Decreased appetite, but eating", "range": [75, 100]},
                2: {"criteria": "Decreased intake <3 days", "range": [50, 75]},
                3: {"criteria": "Decreased intake ≥3 days", "range": [25, 50]},
                4: {
                    "criteria": "Life-threatening consequences; urgent intervention indicated",
                    "range": [0, 25],
                },
                5: {"criteria": "Death", "range": None},
            },
        },
        # Hepatic
        "alt_increase": {
            "description": "Alanine aminotransferase increased",
            "unit": "x ULN (upper limit of normal)",
            "grades": {
                0: {"criteria": "≤ ULN", "range": [0, 1]},
                1: {"criteria": ">ULN - 2.5xULN", "range": [1, 2.5]},
                2: {"criteria": ">2.5 - 5.0xULN", "range": [2.5, 5]},
                3: {"criteria": ">5.0 - 20.0xULN", "range": [5, 20]},
                4: {"criteria": ">20.0xULN", "range": [20, float("inf")]},
                5: {"criteria": "Death", "range": None},
            },
        },
        # Renal
        "creatinine_increase": {
            "description": "Creatinine increased",
            "unit": "x ULN",
            "grades": {
                0: {"criteria": "≤ ULN", "range": [0, 1]},
                1: {"criteria": ">ULN - 1.5xULN", "range": [1, 1.5]},
                2: {"criteria": ">1.5 - 3.0xULN", "range": [1.5, 3]},
                3: {"criteria": ">3.0 - 6.0xULN", "range": [3, 6]},
                4: {"criteria": ">6.0xULN", "range": [6, float("inf")]},
                5: {"criteria": "Death", "range": None},
            },
        },
        # Constitutional
        "fever": {
            "description": "Fever",
            "unit": "°C",
            "grades": {
                0: {"criteria": "None", "range": [0, 39]},
                1: {"criteria": "39.0 - 39.5°C", "range": [39, 39.5]},
                2: {"criteria": ">39.5 - 40.0°C", "range": [39.5, 40]},
                3: {"criteria": ">40.0 - 41.0°C", "range": [40, 41]},
                4: {"criteria": ">41.0°C for >24 hrs", "range": [41, float("inf")]},
                5: {"criteria": "Death", "range": None},
            },
        },
        "weight_loss": {
            "description": "Weight loss",
            "unit": "percent of baseline weight",
            "grades": {
                0: {"criteria": "<5%", "range": [0, 5]},
                1: {"criteria": "5% - <10%", "range": [5, 10]},
                2: {"criteria": "10% - <20%", "range": [10, 20]},
                3: {"criteria": "≥20%", "range": [20, float("inf")]},
                4: {"criteria": "Life-threatening", "range": None},
                5: {"criteria": "Death", "range": None},
            },
        },
        # Dermatologic
        "alopecia": {
            "description": "Hair loss",
            "unit": None,
            "grades": {
                0: {"criteria": "None", "range": None},
                1: {"criteria": "Hair loss at injection/treatment site", "range": None},
                2: {"criteria": "Moderate alopecia", "range": None},
                3: {"criteria": "Complete alopecia", "range": None},
                4: {"criteria": "Not applicable", "range": None},
                5: {"criteria": "Not applicable", "range": None},
            },
        },
        # Neurologic
        "neuropathy": {
            "description": "Peripheral neuropathy",
            "unit": None,
            "grades": {
                0: {"criteria": "None", "range": None},
                1: {
                    "criteria": "Asymptomatic; clinically detectable on examination",
                    "range": None,
                },
                2: {
                    "criteria": "Mild symptoms; limiting instrumental ADL",
                    "range": None,
                },
                3: {
                    "criteria": "Severe symptoms; limiting self-care ADL",
                    "range": None,
                },
                4: {"criteria": "Life-threatening consequences", "range": None},
                5: {"criteria": "Death", "range": None},
            },
        },
    }

    def apply_vcog_grade(symptom, severity, measurement=None):
        '''Apply VCOG-CTCAE grading criteria to an adverse event.

        Parameters
        ----------
        symptom : str
            The type of adverse event
        severity : str
            The severity description
        measurement : float or None
            Quantitative measurement related to the symptom, if available

        Returns
        -------
        int
            The VCOG-CTCAE grade (0-5)
        str
            Description of the grading rationale

        '''
        # Standard severity-based grading if no specific criteria exist
        grade_map = {
            "none": 0,
            "mild": 1,
            "moderate": 2,
            "severe": 3,
            "life-threatening": 4,
            "death": 5,
        }

        symptom_lower = symptom.lower()

        # Check if the symptom has specific VCOG-CTCAE criteria
        if symptom_lower in vcog_criteria:
            criteria = vcog_criteria[symptom_lower]

            # If measurement is provided and criteria has numeric ranges
            if measurement is not None:
                try:
                    measurement_value = float(measurement)

                    # Find the appropriate grade based on the measurement ranges
                    for grade, grade_info in criteria["grades"].items():
                        if grade_info["range"] is not None:
                            min_val, max_val = grade_info["range"]
                            if min_val <= measurement_value < max_val:
                                return (
                                    grade,
                                    f"Grade {grade}: {criteria['description']} - {criteria['grades'][grade]['criteria']}",
                                )
                except (ValueError, TypeError):
                    # If measurement can't be converted to float, fall back to severity-based grading
                    pass

            # If there's a reported severity with no valid measurement
            if severity.lower() in grade_map:
                # Check if the grade exists in the criteria
                severity_grade = grade_map[severity.lower()]
                if severity_grade in criteria["grades"]:
                    return (
                        severity_grade,
                        f"Grade {severity_grade}: {criteria['description']} - {criteria['grades'][severity_grade]['criteria']}",
                    )

        # Default to using the severity mapping if no specific criteria match
        if severity.lower() in grade_map:
            return grade_map[severity.lower()], f"Grade {grade_map[severity.lower()]}: Based on reported severity"

        # Default grade if no specific criteria match
        return 1, "Grade 1: Default grade (specific criteria not found)"

    # Step 3: Apply grading to each record
    log += "Applying VCOG-CTCAE v1.1 grading criteria to each adverse event...\\n"

    # Create new columns for the grade and rationale
    grading_results = data.apply(
        lambda row: apply_vcog_grade(
            row["symptom"],
            row["severity"],
            row["measurement"] if "measurement" in data.columns else None,
        ),
        axis=1,
    )

    # Split the returned tuples into separate columns
    data["vcog_grade"] = [result[0] for result in grading_results]
    data["grading_rationale"] = [result[1] for result in grading_results]

    # Step 4: Analyze patterns across time points (if available)
    if "time_point" in data.columns:
        log += "\\n## Step 3: Analyzing adverse event patterns across time points\\n"

        # Group by subject and symptom to track progression
        progression_analysis = data.pivot_table(
            index=["subject_id", "symptom"],
            columns="time_point",
            values="vcog_grade",
            aggfunc="max",
        ).reset_index()

        # Calculate if grade is increasing, decreasing, or stable for each subject-symptom pair
        trend_counts = {"increasing": 0, "decreasing": 0, "stable": 0, "fluctuating": 0}

        numeric_columns = [col for col in progression_analysis.columns if col not in ["subject_id", "symptom"]]

        if len(numeric_columns) >= 2:
            # Sort columns to ensure chronological order
            numeric_columns.sort()

            for _, row in progression_analysis.iterrows():
                values = [row[col] for col in numeric_columns if not pd.isna(row[col])]
                if len(values) >= 2:
                    if all(values[i] < values[i + 1] for i in range(len(values) - 1)):
                        trend_counts["increasing"] += 1
                    elif all(values[i] > values[i + 1] for i in range(len(values) - 1)):
                        trend_counts["decreasing"] += 1
                    elif all(values[i] == values[i + 1] for i in range(len(values) - 1)):
                        trend_counts["stable"] += 1
                    else:
                        trend_counts["fluctuating"] += 1

            log += "Adverse event progression patterns:\\n"
            for trend, count in trend_counts.items():
                log += f"- {trend.capitalize()}: {count} subject-symptom pairs\\n"

        # Save progression analysis
        progression_file = "vcog_ctcae_progression_analysis.csv"
        progression_analysis.to_csv(progression_file)
        log += f"\\nDetailed progression analysis saved to: {progression_file}\\n"

    # Step 5: Summarize the grading results
    log += "\\n## Step 4: Summarizing adverse event grades\\n"

    # Count events by grade
    grade_counts = data["vcog_grade"].value_counts().sort_index()
    log += "Grade distribution:\\n"
    for grade, count in grade_counts.items():
        log += f"- Grade {grade}: {count} events\\n"

    # Summarize by symptom type
    symptom_summary = data.groupby("symptom")["vcog_grade"].agg(["max", "mean", "count"])
    log += "\\nSymptom severity summary:\\n"
    for symptom, stats in symptom_summary.iterrows():
        log += f"- {symptom}: max grade = {stats['max']}, avg grade = {stats['mean']:.2f}, count = {stats['count']}\\n"

    # Summarize by subject
    subject_summary = data.groupby("subject_id")["vcog_grade"].agg(["max", "mean", "count"])
    log += f"\\nSubjects with adverse events: {len(subject_summary)}\\n"
    log += f"Subjects with Grade 3+ events: {len(subject_summary[subject_summary['max'] >= 3])}\\n"

    # Create a summary of most severe events
    most_severe = data.sort_values("vcog_grade", ascending=False).head(10)
    log += "\\nTop 10 most severe adverse events:\\n"
    for i, (_, event) in enumerate(most_severe.iterrows(), 1):
        log += f"{i}. Subject {event['subject_id']}: {event['symptom']} (Grade {event['vcog_grade']})\\n"

    # Step 6: Save detailed results to file
    output_file = "vcog_ctcae_graded_events.csv"
    data.to_csv(output_file, index=False)
    log += "\\n## Step 5: Results saved\\n"
    log += f"Detailed graded events saved to: {output_file}\\n"

    # Save the VCOG criteria as a reference
    with open("vcog_ctcae_criteria_reference.json", "w") as f:
        json.dump(vcog_criteria, f, indent=2)
    log += "VCOG-CTCAE criteria reference saved to: vcog_ctcae_criteria_reference.json\\n"

    return log

# Execute the function
try:
    result = grade_adverse_events_using_vcog_ctcae(
        clinical_data_file=auto_convert(os.environ.get("PARAM_CLINICAL_DATA_FILE", "")),
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
    "function": "grade_adverse_events_using_vcog_ctcae",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("grade_adverse_events_using_vcog_ctcae_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("grade_adverse_events_using_vcog_ctcae_output.txt", "w") as f:
    f.write("Biomni: Grade Adverse Events Using Vcog Ctcae" + NL)
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
        biomni_function: "grade_adverse_events_using_vcog_ctcae"
    END_VERSIONS
    """
}

workflow GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE(ch_input)

    emit:
    results = GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.results
    output = GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.output
    versions = GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE_WORKFLOW(ch_input)

    GRADE_ADVERSE_EVENTS_USING_VCOG_CTCAE_WORKFLOW.out.output.view { "Output: $it" }
}
