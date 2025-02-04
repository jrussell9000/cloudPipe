import argparse
import configparser
import keyring
import logging
import os
import shutil
import tarfile
import logging
import subprocess

import ants
import antspynet
import nibabel as nb

from argparse import Namespace
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


'''
This module performs the 'minimal processing' steps as originally described 
in Hagler et al., 2017 and originally coded at github.com/ABCD-STUDY/Minimally-Processed-Image-Sharing .
It presumes that the incoming raw data (e.g., ABCD Fasttrack) have previously been
NIFTI-converted and organized into BIDS-format. 
###############################
'''

def initialize():

    parser = argparse.ArgumentParser(
        prog='minproc',
        description='Python-based minimal processing, as defined by Hagler et al. 2017.')

    parser.add_argument('-s', '--subjses',
                        dest="subjses",
                        required=True,
                        type=str,
                        help="""
                        An underscore joined NIMH Data Archive-formatted 'src_subject_id' and 'timepoint' string
                        of the format NDARINVxxxxxxxx_yyyyyyyyyyyyy, where 'xxx' is the src_subject_id and 'yyy' is the timepoint
                        (e.g., baselineYear1Arm1).
                        """
                        )
    parser.add_argument('-t', '--type',
                        dest="type",
                        required=True,
                        type=str,
                        help="""
                        An underscore joined NIMH Data Archive-formatted 'src_subject_id' and 'timepoint' string
                        of the format NDARINVxxxxxxxx_yyyyyyyyyyyyy, where 'xxx' is the src_subject_id and 'yyy' is the timepoint
                        (e.g., baselineYear1Arm1).
                        """
                        )
    parser.add_argument('-t', '--threads',
                        type=int,
                        dest="threads",
                        default=4)
    passed_args = parser.parse_args()

    return passed_args

@dataclass
class MinProc:
    subjses: str
    type: str
    threads: int

    # def __post_init__(self):
    #     self.subjses = self.subjses
    #     self.type = self.type
    #     self.threads = self.threads

    def run(self):
        self._run_minproc()

    def n4biascorrect(self):
        image = ants.image_read(self.t1w)
        image_n4 = ants.n4_bias_field_correction(image)
        image_out = ants.image_write()

    def threetissueseg(self, image_in):
        image = ants.image_read(image_in)
        bext = antspynet.brain_extraction(image, modality="t1threetissue", verbose=True)
        seg = bext['segmentation_image']

    def centerT1intensity(self):
        image = nb.load(self.t1w)
        intensities = image.get_fdata()

    def _run_minproc(self):
