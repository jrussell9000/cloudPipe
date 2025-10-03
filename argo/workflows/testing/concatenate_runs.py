# -*- coding: utf-8 -*-
"""
Concatenates multiple fMRI timing files (event files) into a single file,
adjusting the onset times based on the duration of the preceding runs.

This is useful for running a single GLM on concatenated fMRI data.
"""

import argparse
import os
import sys
import nibabel as nib
from pathlib import Path
from typing import List


def get_run_durations(
        input_files: List[str]) -> List[float]:
    """
    Gets the duration of multiple fmri runs (passed as input_files list) in seconds
    and outputs them in a list
    """
    run_durations = []
    for i in input_files:
        if not os.path.exists(i):
            print(f"Error: Input file not found: {i}", file=sys.stderr)
            sys.exit(1)
        img = nib.load(input_files[i])
        header = img.header

        num_TRs = header.get_data_shape()[3]
        time_step = header.get_zooms()[3]

        total_time_seconds = num_TRs * time_step


def concatenate_fmri_timings(
        input_files: List[str], run_durations: List[float], output_file: str) -> None:
    """
    Reads multiple fMRI timing files, adjusts onsets, and writes to a single
    output file.

    The timing files are expected to be in a 3-column format (onset, duration,
    modulation) separated by spaces or tabs.

    Args:
        input_files: A list of paths to the input timing files.
        run_durations: A list of durations (in seconds) for each fMRI run.
                       The order must correspond to the input_files list.
        output_file: The path where the concatenated output file will be saved.
    """
    # --- Input Validation ---
    if len(input_files) != len(run_durations):
        print(
            "Error: The number of input files must match the number of run durations.",
            file=sys.stderr,
        )
        sys.exit(1)

    if not all(Path(f).exists() for f in input_files):
        missing_files = [f for f in input_files if not Path(f).exists()]
        print(
            f"Error: The following input files were not found: {', '.join(missing_files)}",
            file=sys.stderr,
        )
        sys.exit(1)

    # --- Main Logic ---
    cumulative_offset = 0.0
    concatenated_events = []

    print("Processing files...")
    for i, file_path in enumerate(input_files):
        try:
            with open(file_path, 'r') as f:
                lines = f.readlines()

            run_duration = run_durations[i]
            print(f"  - Reading '{file_path}' (Run duration: {run_duration}s, Cumulative offset: {cumulative_offset:.2f}s)")

            for line in lines[1:]:
                line = line.strip()
                if not line:
                    continue  # Skip empty lines

                parts = line.split()
                if len(parts) < 3:
                    print(
                        f"    Warning: Skipping malformed line in {file_path}: '{line}'",
                        file=sys.stderr,
                    )
                    continue

                # Read original values and convert to float
                original_onset = float(parts[0])
                duration = float(parts[1])
                trial_type = parts[2]

                # Adjust the onset time by adding the cumulative duration of previous runs
                adjusted_onset = original_onset + cumulative_offset

                # Store the new event line
                concatenated_events.append(f"{adjusted_onset:.4f}\t{duration:.4f}\t{trial_type}\n")

            # Update the cumulative offset for the next run
            cumulative_offset += run_duration

        except FileNotFoundError:
            print(f"Error: Input file not found: {file_path}", file=sys.stderr)
            sys.exit(1)
        except ValueError as e:
            print(
                f"Error processing file {file_path}. Ensure it contains valid numbers. Details: {e}",
                file=sys.stderr,
            )
            sys.exit(1)
        except Exception as e:
            print(
                f"An unexpected error occurred processing {file_path}: {e}", file=sys.stderr
            )
            sys.exit(1)

    # --- Write Output ---
    try:
        with open(output_file, 'w') as f_out:
            f_out.writelines(concatenated_events)
        print(f"\nSuccessfully concatenated {len(input_files)} files into '{output_file}'")
        print(f"Total duration accounted for: {cumulative_offset:.2f}s")
    except IOError as e:
        print(
            f"Error: Could not write to output file '{output_file}'. Details: {e}",
            file=sys.stderr,
        )
        sys.exit(1)


def main():
    """
    Parses command-line arguments and runs the concatenation function.
    """
    confounds_root = Path("/xcpd_input/custom_confounds/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func/")
    func_root = Path("/fmriprep_output/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func")
    event_timings_path = Path("/xcpd_input/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func/{{inputs.parameters.task}}_event_timings")
    event_timing_files = sorted(list([file for file in event_timings_path.glob('*_task-{{inputs.parameters.task}}_run-0*_events.tsv')]))
    niis = sorted(list([niigz for niigz in func_root.glob('*task-{{inputs.parameters.task}}_run-0*_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz')]))

    get_run_durations(niis)

    concatenate_fmri_timings(args.input_files, args.run_durations, args.output_file)


if __name__ == '__main__':
    main()
