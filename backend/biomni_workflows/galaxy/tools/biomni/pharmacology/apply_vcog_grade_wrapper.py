#!/usr/bin/env python3
"""Apply VCOG-CTCAE adverse event grading."""
import sys
import json

def apply_vcog_grade(event_type, severity_value, species="canine"):
    """Apply VCOG grading criteria.
    Args: event_type: type of adverse event, severity_value: numeric severity, species
    """
    # Simplified grading
    if severity_value < 1:
        grade = 1
    elif severity_value < 2:
        grade = 2
    elif severity_value < 3:
        grade = 3
    elif severity_value < 4:
        grade = 4
    else:
        grade = 5
    return {"event_type": event_type, "severity": severity_value, "vcog_grade": grade, "species": species}

def main():
    args = {}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                try:
                    val = float(val)
                except ValueError:
                    pass
                args[key] = val
                i += 2
            else:
                i += 1
        else:
            i += 1
    output_path = args.pop('output', '/dev/stdout')
    result = apply_vcog_grade(**args)
    with open(output_path, 'w') as f:
        json.dump(result, f, indent=2)

if __name__ == '__main__':
    main()
