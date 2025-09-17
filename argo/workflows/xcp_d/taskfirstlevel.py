import numpy
import json
import os
import numpy as np
import pandas as pd
from pathlib import Path
import nibabel as nib
from nilearn.glm.first_level import make_first_level_design_matrix

# Concatenate event timing files
# event_timings_path = Path('/home/fmriprep/output/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func/nback_event_timings/')
event_timings_path = Path('/home/jdrussell3/cloudpipe/argo/workflows/xcp_d/tmp/')
event_timing_files = sorted(list([file for file in event_timings_path.glob('*_task-nback_run-0*_events.tsv')]))
print(event_timing_files)
# events_df = pd.concat([pd.read_csv(f, sep='\t', usecols=range(0, 3)) for f in event_timing_files])

etf_run = 0
last_onset = 0
last_duration = 0

for etf in event_timing_files:
    if event_timing_files.index(etf) == 0:
        etf_data = pd.read_csv(etf, sep='\t', usecols=range(0, 3))
    else:
        etf_run_data = pd.read_csv(etf, sep='\t', usecols=range(0, 3))
        previous_run_last_onset = etf_run_data['onset'].iloc[-1]
        previous_run_last_duration = etf_run_data['duration'].iloc[-1]
        etf_run_data['onset'] = etf_run_data['onset'] + previous_run_last_onset + previous_run_last_duration
        etf_data = pd.concat([etf_data, etf_run_data])

etf_data.to_csv('testevents.tsv', sep='\t', index=False)


# This should be modified to iterate over tasks, but not multiple registrations of that task
# nvols = 0
# for niigz in Path('/home/fmriprep/output/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func/').glob('{{workflow.parameters.subjID}}_{{inputs.parameters.session}}_task-nback_run-0*_space-MNI152NLin2009cAsym_desc-preproc_bold.nii.gz'):
#     img = nib.load(niigz)
#     nvols += img.shape[3]

# TR = 0.8  # Casey et al., 2017)
# frame_times = np.arange(nvols) * TR

# task_confounds = make_first_level_design_matrix(
#     frame_times,
#     events_df,
#     hrf_model="spm",
#     drift_model=None,
#     add_regs=None,
# )

# task_confounds = task_confounds.drop(columns="constant")

# task_confounds.to_csv('/home/fmriprep/output/{{workflow.parameters.subjID}}/{{inputs.parameters.session}}/func/{{workflow.parameters.subjID}}_{{inputs.parameters.session}}_desc-confounds_timeseries.tsv',
#                       sep="\t",
#                       index=False)
