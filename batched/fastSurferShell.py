import logging
import os
from dataclasses import dataclass
from pathlib import Path
from utils import run_command, logTitle

"""
This module takes in the T1 NIFTI file for a single subjectkey-time point pairing
(e.g., NDARXXXXXXX_baselineYear1Arm1) and runs it through the FastSurfer pipeline.
The subcortical segmentation portion of FastSurfer always runs, while the parcellation piece is
optional (seg_only=True). FastSurfer runs from an Apptainer (singularity) image, whose path must
be passed in. The FastSurfer apptainer image is executed with binds to the local path for to
the directory containing the FreeSurfer license file, the input directory, and the output directory.
The output (a FreeSurfer subject directory) is returned to the specified output directory.
The '--parallel' option is used to run parcellation of both hemispheres in parallel.
The '--nvccli' Apptainer option is used to allow GPU access. Output from FastSurfer is recorded
in the log file as defined in ABCDFastPipe.
"""

@dataclass
class FastSurfer:
    rawsubjses_str: str
    nThreads: str = 4
    runParc: bool = False

    def __post_init__(self):
        self.logger = logging.getLogger(__name__)
        logTitle(f'Running FastSurfer Segmentation for {self.rawsubjses_str}')

        # BIDS-formatting subject_timepoint string and getting the T1 path (as string)
        self.subjses_str = self.rawsubjses_str.replace("_", "_ses-")
        self.subjses_str = "-".join(["sub", self.subjses_str])
        self.subjses_T1 = "_".join([self.subjses_str, "run-01_T1w.nii"])
        self.cwd = os.getcwd()
        self.subjses_T1_imgpath = Path('/work', self.subjses_T1).as_posix()
        try:
            exitcode = self.main()
        except Exception as exc:
            raise exc

    def main(self):
        # Conditional subprocess arguments: https://discuss.python.org/t/syntax-to-skip-elements-when-constructing-a-list-tuple-set-dict/34325/4
        exitcode = run_command(["/fastsurfer/run_fastsurfer.sh",
                                *([] if self.runParc else ["--t1", self.subjses_T1_imgpath]),
                                "--sid", self.subjses_str,
                                "--sd", '/work',
                                *(["--surf_only"] if self.runParc else ["--seg_only"]),
                                "--parallel",
                                "--threads", "4",
                                "--3T"])
        return exitcode
