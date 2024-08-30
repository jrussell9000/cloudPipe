import dask
import logging
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from utils import run_command, setup_freesurfer, logTitle


class SubSegment():

    def __init__(self, rawsubjses_str: str, inputs_dir: str, outputs_dir: str, nThreads: str, MCRdir: str,
                 freeSurferDir: str = None, setupFreeSurfer: bool = False):

        self.subjses_str = rawsubjses_str.replace("_", "_ses-")
        self.subjses_str = "-".join(["sub", self.subjses_str])
        self.inputs_dir_pathstr = inputs_dir
        self.inputs_dir = Path(inputs_dir)
        self.subjses_T1 = "_".join([self.subjses_str, "run-01_T1w.nii"])
        self.subjses_T1_localpath = Path(self.inputs_dir / self.subjses_T1)
        self.subjses_T2 = "_".join([self.subjses_str, "run-01_T2w.nii"])
        self.subjses_T2_localpath = Path(self.inputs_dir / self.subjses_T2)
        self.outputs_dir_pathstr = outputs_dir
        self.outputs_dir = Path(outputs_dir)
        self.nThreads = nThreads
        self.MCRdir = MCRdir
        self.setupFreeSurfer = setupFreeSurfer

        # Initialize FreeSurfer if necessary
        if setupFreeSurfer:
            setup_freesurfer(freeSurferDir, self.outputs_dir_pathstr)

        # Creating a runtime environment for the subsegmentation tasks
        self.subseg_env = os.environ.copy()

        # Setting the number of threads for segmentation
        self.subseg_env["ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS"] = nThreads

        # Setting paths to MCR libraries
        MCRdirs = f"{self.MCRdir}".join(["", "/sys/os/glnxa64:", "/bin/glnxa64:", "/runtime/glnxa64:", "/extern/bin/glnxa64"])
        self.subseg_env["LD_LIBRARY_PATH"] = MCRdirs

        # Naming logger
        self.logger = logging.getLogger('Subsegmentation')
        self.runsubseg()

    # Hippocamus and Amygdala Subfield/nuclei segmentation
    def segHippoAmyg(self):

        segHippoAmyg_starttime = datetime.now()
        logTitle(f"Segmenting Hippocamus and Amygdala for {self.subjses_str}", level=2)
        try:
            if Path(self.subjses_T2_localpath).exists():
                run_command(
                    ['segmentHA_T2.sh', self.subjses_str, str(self.subjses_T2_localpath), 'T2', '1', str(self.outputs_dir)], shell=True, env=self.subseg_env)
            else:
                run_command(
                    ['segmentHA_T1.sh', self.subjses_str, str(self.outputs_dir)], shell=True, env=self.subseg_env)
        except Exception as exc:
            self.logger.exception(exc)
        else:
            # Discard the T2 if segmentation ran correctly (we no longer need it)
            if Path(self.subjses_T2_localpath).exists():
                os.remove(self.subjses_T2_localpath)
                self.logger.info(f"Removed {self.subjses_T2_localpath}")
        segHippoAmyg_endtime = datetime.now()
        segHippoAmyg_runtime = segHippoAmyg_endtime - segHippoAmyg_starttime
        self.logger.info(f"Segmentation of Hippocamus and Amygdala completed in: {segHippoAmyg_runtime}")

    # Thalamic Nuclei Segmentation
    def segThalamus(self):

        segThal_starttime = datetime.now()
        logTitle(f"Segmenting Thalamic Nuclei for {self.subjses_str}", level=2)
        try:
            run_command(['segmentThalamicNuclei.sh', self.subjses_str, str(self.outputs_dir)], env=self.subseg_env)
        except Exception as exc:
            self.logger.exception(exc)

        segThalamus_endtime = datetime.now()
        segThalamus_runtime = segThalamus_endtime - segThal_starttime
        self.logger.info(f"Segmentation of Thalamic Nuclei completed in: {segThalamus_runtime}")

    # Brainstem Segmentation
    def segBrainstem(self):

        segBrainstem_starttime = datetime.now()
        logTitle(f"Segmenting Brainstem for {self.subjses_str}", level=2)
        try:
            run_command(['segmentBS.sh', self.subjses_str, str(self.outputs_dir)], env=self.subseg_env)
        except Exception as exc:
            self.logger.exception(exc)

        segBrainstem_endtime = datetime.now()
        segBrainstem_runtime = segBrainstem_endtime - segBrainstem_starttime
        self.logger.info(f"Brainstem segmentation completed in: {segBrainstem_runtime}")

    # Hypothalamus Segmentation
    def segHypothalamus(self):

        segHypothalamus_starttime = datetime.now()
        logTitle(f"Segmenting Hypothalamus for {self.subjses_str}", level=2)
        try:
            run_command(['mri_segment_hypothalamic_subunits', '--s', self.subjses_str,
                         '--sd', str(self.outputs_dir)],
                        env=self.subseg_env)
        except Exception as exc:
            self.logger.exception(exc)

        segHypothalamus_endtime = datetime.now()
        segHypothalamus_runtime = segHypothalamus_endtime - segHypothalamus_starttime
        self.logger.info(f"Segmentation of Hypothalamus completed in: {segHypothalamus_runtime}")

    # Miscellaneous Subcortical Segmentation: fornix, NA, AC, septal nuclei, mamillary bodies, hypothalamus
    def segSubcortical(self):

        segSubcortical_starttime = datetime.now()
        logTitle(f"Segmenting miscellaneous subcortical structures for {self.subjses_str}", level=2)
        try:
            run_command(['mri_sclimbic_seg', '--s', self.subjses_str, '--sd', str(self.outputs_dir),
                         '--etiv', '--write_volumes', '--write_qa_stats', '--threads', self.nThreads,
                         '--cuda-device', '0'],
                        env=self.subseg_env)
        except Exception as exc:
            self.logger.exception(exc)

        segSubcortical_endtime = datetime.now()
        segSubcortical_runtime = segSubcortical_endtime - segSubcortical_starttime
        self.logger.info(f"Segmentation of miscellaneous subcortical structures completed in: {segSubcortical_runtime}")

    def runsubseg(self):
        self.segHippoAmyg()
        self.segThalamus()
        self.segBrainstem()
        self.segHypothalamus()
        self.segSubcortical()
        return (self.subjses_str)


# outputs_dir = "/fastscratch/jdr/ABCD/fastSurf/outputs"
# inputs_dir = "/fastscratch/jdr/ABCD/fastSurf/inputs"
# S = SubSegment("NDARINV0CP9XGTP_2YearFollowUpYArm1", inputs_dir, outputs_dir, "2", "/fastscratch/jdr/apps/freesurfer/MCRv97")
