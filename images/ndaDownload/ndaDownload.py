import argparse
import configparser
import keyring
import logging
import os
import shutil
import tarfile
import logging

from argparse import Namespace
from contextlib import contextmanager
from dataclasses import dataclass
from pathlib import Path


'''
This module provides programmatic access to the 'download' methods
available as part of NDA-tools. It first (createArgs) creates the argument
parser namespace that would normally be created by the client script downloadcmd.py.
We'll pass the raw subject_timepoint string to the regex filter argument to download
only the files for the current subject/timepoint pairing.

We'll also try to set up NDA authentication in advance to avoid getting a user prompt.
ndaDownloader (currently) tries to import the NDA username and password from config.py
(note: NOT the username/password for the miNDAR package OR login.gov). It then adds those
credentials to keyring as a key to the 'nda-tools' service (see IMPORTANT below).

The args object output by createArgs() is passed to init_and_create_configuration(),
which returns a ClientConfiguration object.  We'll pass this and the args to the
Download module, and start pulling files. When finished, we'll unpack the downloaded
TGZ archives, and (for each) decompress any NIFTI files inside, disregarding any
directory structure (i.e., files only)

###IMPORTANT####
ndaDownloader relies on the python 'keyring' and 'keyrings.alt' modules (yes, they're distinct)
being installed, as they'll be used by NDATools. Keyring manages the credentials used
to authenticate with NDA. Keyrings.alt allows those keys to be stored in various alternative
formats, including plain text. Currently, we're relying on the less than optimal approach of
plain text storage for our keyring. Plain text keyring storage (using keyrings.alt) must be pre-configured by creating a
file named 'keyringrc.cfg' in $HOME/.config/python_keyring/ with the following text inside:

[backend]
default-keyring=keyrings.alt.file.PlaintextKeyring
keyring-path=/tmp/work

## NOTE: Need to migrate to keyring with secretstorage
# https://github.com/jaraco/keyring/blob/main/keyring/backends/SecretService.py

###############################
'''


def initialize():

    parser = argparse.ArgumentParser(
        prog='NDADownloader',
        description='Python-based downloader for pulling files S3 paths in NIMH Data Archive miNDAR packages.')

    parser.add_argument('subj_ses',
                        help="""
                        An underscore joined NIMH Data Archive-formatted 'src_subject_id' and 'timepoint' string
                        of the format NDARINVxxxxxxxx_yyyyyyyyyyyyy, where 'xxx' is the src_subject_id and 'yyy' is the timepoint
                        (e.g., baselineYear1Arm1).
                        """
                        )
    parser.add_argument('-c', '--config',
                        required=False,
                        default='fastproc.cfg',
                        help=""""
                        Fully qualified path to the NDADownloader config file. Defaults to './fastproc.cfg'.
                        """
                        )

    args = parser.parse_args()

    # Create a ConfigParser object
    config = configparser.ConfigParser()

    # Read the configuration file
    config.read(args.config)

    # Access values from the configuration file
    NDA_username = config.get('NDA', 'NDA_username')
    NDA_password = config.get('NDA', 'NDA_password')
    miNDAR_packageID = config.get('NDA', 'miNDAR_packageID')

    # Return a dictionary with the retrieved values
    config_values = {
        'NDA_username': NDA_username,
        'NDA_password': NDA_password,
        'miNDAR_packageID': miNDAR_packageID,
        'rawsubjses_str': args.subj_ses
    }

    return config_values


# Add various title or heading sections to the log file
def logTitle(title: str, level: int = 1):

    logger = logging.getLogger()
    if level == 1:
        tchar = "#"
    elif level == 2:
        tchar = "="
    elif level == 3:
        tchar = "*"
    else:
        tchar = "@"
    logger.info("\n" + len(title) * tchar, extra={'simple': True})
    # 'simple': True removes the log formatting prefix
    logger.info(title, extra={'simple': True})
    logger.info(len(title) * tchar + "\n", extra={'simple': True})

# A context for suppressing stdout from a function
@contextmanager
def suppress_stdout():
    import os
    import sys

    with open(os.devnull, "w") as devnull:
        old_stdout = sys.stdout
        sys.stdout = devnull
        try:
            yield
        finally:
            sys.stdout = old_stdout


# Silence obnoxious messages from nda-tools
with suppress_stdout():
    from NDATools import init_and_create_configuration, NDA_TOOLS_DOWNLOADCMD_LOGS_FOLDER, NDA_TOOLS_DOWNLOADS_FOLDER
    from NDATools.Download import Download

@dataclass
class Downloader():
    NDA_username: str
    NDA_password: str
    miNDAR_packageID: str
    rawsubjses_str: str

    def __post_init__(self):
        self.logger = logging.getLogger(__name__)
        logTitle(f'Downloading and Unpacking Scan Files for {self.rawsubjses_str}')
        self.main()

    def passwordCheck(self):
        # Check and/or set the keyring password for 'nda-tools'
        if keyring.get_password('nda-tools', self.NDA_username) is None:
            keyring.set_password('nda-tools', self.NDA_username, self.NDA_password)

    def createArgs(self):
        # the clientscript 'downloadcmd.py' includes an argparser that generates
        # a namespace with the following objects
        args = Namespace(
            datastructure=None,
            # Where will be downloading to?
            directory=["~/work"],
            # Filter the contents of the miNDAR package by a given subject_timepoint
            file_regex=self.rawsubjses_str,
            log_dir=None,
            # Specify the miNDAR package ID number (NDA>Profile>Data Packages>ID Column)
            package=self.miNDAR_packageID,
            paths=None,
            s3_destination=None,
            txt=None,
            # Specify the username for logging in to NDA
            # (do NOT specify the username for login.gov or the username for accessing the miNDAR package itself)
            username=self.NDA_username,
            verbose=False,
            verify=False,
            workerThreads=1)
        return args

    # Initiate the download for this subject_timepoint
    def download(self, clientConfigObj, args):
        # Parse out the raw subject ID (e.g., NDAR_XXXXXXX)
        rawsubj_str = self.rawsubjses_str.split("_")[0]
        # Parse out the raw time point (e.g., baselineyear1arm1)
        rawses_str = self.rawsubjses_str.split("_")[1]
        try:
            self.logger.info(f'Now downloading scan files for subject '
                             f'{rawsubj_str}, timepoint {rawses_str}...')
            # Define the download parameters (from config, args) and start it
            s3Download = Download(clientConfigObj, args)
            s3Download.start()
        except Exception as exc:
            self.logger.exception(exc, exc_info=True)
            raise exc

    # Loop over all the tgz files in the subject_ses folder and unpack them
    def unpack(self):
        self.logger.info('Unpacking all the TGZ files...')

        # Defining a function that will selectively decompress the NIFTI files from the archive
        def niiextract(tgz):
            try:
                with tarfile.open(tgz, "r") as tar:
                    # Only extract the NIFTI files
                    members = [member for member in tar.getmembers() if member.name.split(".")[-1] == "nii"]
                    for member in members:
                        # Don't extract parent folders, just the files
                        member.name = Path(member.name).name
                        print(member.name)
                        self.logger.info(f'Decompressing {member.name}...')
                    tar.extractall(path="/home/nonroot/work", members=members)
            except Exception as exc:
                self.logger.exception(f'Failed to unpack {tgz}: {exc}', exc_info=True)
                raise exc
            else:
                os.remove(tgz)

        # For each TGZ file we've downloaded, decompress any NIFTI files inside it
        try:
            [niiextract(tgz) for tgz in Path("/home/nonroot/work").rglob(f'{self.rawsubjses_str}*.tgz')]
        except Exception as exc:
            raise exc

    def main(self):
        try:
            args = self.createArgs()
            # init_and_create_configuration performs authentication and looks for the nda-tools
            # password in keyring. Let's add it now to avoid a prompt.
            self.passwordCheck()
            # nda-tools skips files in its running log of prior downloads....
            # Delete this log if it exists (e.g., if we're running locally); assume we know what we're doing
            print("/".join([NDA_TOOLS_DOWNLOADS_FOLDER, self.miNDAR_packageID]))
            if Path("/".join([NDA_TOOLS_DOWNLOADS_FOLDER, self.miNDAR_packageID])).exists():
                shutil.rmtree("/".join([NDA_TOOLS_DOWNLOADS_FOLDER, self.miNDAR_packageID]))
            # init_and_create_configuration takes in the namespace 'args' (defined above) and
            # outputs the ClientConfiguration object required by NDATools.Download()
            clientConfigObj = init_and_create_configuration(args, NDA_TOOLS_DOWNLOADCMD_LOGS_FOLDER)
            # The NDA 'Download' module asks for the args namespace and the ClientConfiguration object
            self.download(clientConfigObj, args)
            # Unpack the downloaded TGZ archives and remove any directory structure (retain NIFTI files only)
            # then delete the archive file
            self.unpack()
        except Exception as exc:
            self.logger.exception(f'Encountered exception while downloading and unpacking files: {exc}', exc_info=True)
            raise exc


if __name__ == '__main__':
    config_values = initialize()
    Downloader(**config_values)
