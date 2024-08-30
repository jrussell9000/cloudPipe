from contextlib import contextmanager
from datetime import datetime
from pathlib import Path

import argparse
import config
import logging
import os
import shutil
import subprocess
import sys


def run_command(command: list, env: os.environ = None, **kwargs):

    from subprocess import Popen, PIPE, STDOUT

    logging.getLogger(__name__)
    # print(command)
    logging.info("Running: " + " ".join(command))
    process = Popen(command,
                    env=env, stdout=PIPE, stderr=STDOUT, shell=False,
                    encoding='utf-8', errors='replace')
    # While the streaming output from the process is not null or the process hasn't returned and exit code
    # print and/or log the output from the process
    while (realtime_output := process.stdout.readline()) != '' or process.poll() is None:
        # print(realtime_output.strip())
        logging.info(realtime_output.strip())
    # Get the exit code from the process and return it
    returncode = process.poll()
    return (returncode)

# Packing up the results in an XZ archive in /tmp
def xzPack(rawsubjses_str: str, suffix: str = None):

    import tarfile
    logging.getLogger('Compression')
    logTitle(f'Compressing Output files for {rawsubjses_str}')

    subjses_str = rawsubjses_str.replace("_", "_ses-")
    subjses_str = "-".join(["sub", subjses_str])

    print(f"Subjses_str is {subjses_str}")

    for logfile in Path('/fastsurfer/log').glob(f'*{subjses_str}*'):
        shutil.copy(logfile, f'/work/{subjses_str}')

    outPath = Path('/work', subjses_str)

    if suffix is not None:
        subjses_str = "_".join([subjses_str, suffix])

    tarPath = Path(f"/tmp/{subjses_str}.tar.xz")
    with tarfile.open(tarPath, "w:xz") as tar:
        for p in outPath.rglob('**'):
            tar.add(p)


# Download a file from a specified S3 bucket
def s3Downloader(rawsubjses_str: str, suffix: str = None):
    import boto3
    import tarfile

    logging.getLogger("Downloading")

    # BIDS formatting the raw subject_timepoint string and appending the suffix
    subjses_str = rawsubjses_str.replace("_", "_ses-")
    subjses_str = "-".join(["sub", subjses_str])
    if suffix is not None:
        subjses_str = "_".join([subjses_str, suffix])

    logTitle(f'Downloading segmentation files ({subjses_str}) for {rawsubjses_str} from S3')

    # Define the parameters for a new AWS resource connection to S3
    s3 = boto3.client('s3',
                      aws_access_key_id=config.aws_access_key_id,
                      aws_secret_access_key=config.aws_secret_access_key)

    if not Path('/work').exists:
        Path('/work').mkdir()

    in_xzFilename_str = ".".join([subjses_str, 'tar.xz'])
    in_xzFilePath = Path('/work', in_xzFilename_str)

    try:
        s3.download_file(config.aws_s3bucket, in_xzFilename_str, in_xzFilePath)
    except Exception as exc:
        print(f'Error downloading segmentation files from S3: {exc}')
        next

    try:
        with tarfile.open(in_xzFilePath) as tar:
            for member in tar.getmembers():
                if member.path.startswith('work/'):
                    member.path = member.path.split('/', 1)[1]
            tar.extractall(f'/work/')
    except Exception as exc:
        print(f'Error decompressing segmentation files from S3: {exc}')
        next

# Upload the archive file to our S3 bucket then delete it (if successful)
def s3Uploader(rawsubjses_str: str, suffix: str = None):
    import boto3

    logging.getLogger("Uploading")
    logTitle(f'Uploading Output files for {rawsubjses_str} to S3')

    subjses_str = rawsubjses_str.replace("_", "_ses-")
    subjses_str = "-".join(["sub", subjses_str])
    if suffix is not None:
        subjses_str = "_".join([subjses_str, suffix])

    # Define the parameters for a new AWS resource connection to S3
    session = boto3.Session(
        aws_access_key_id=config.aws_access_key_id,
        aws_secret_access_key=config.aws_secret_access_key,
        region_name=config.aws_region
    )
    s3 = session.client('s3')

    # Upload the archive file to the S3 bucket
    tarPath = Path("/tmp", str(subjses_str + '.tar.xz'))
    try:
        with open(str(tarPath), "rb") as f:
            s3.upload_fileobj(f, config.aws_s3bucket, tarPath.name)
    except Exception as err:
        print(f'Error uploading subject-ses archive to S3 storage: {err}')
        next
    else:
        os.remove(tarPath)

def cleanup(pth: str = '/work'):
    for object in Path(pth).iterdir():
        if object.is_file():
            object.unlink()
        else:
            shutil.rmtree(object)


# Logging to multipe locations based on message type
# https://stackoverflow.com/questions/18911737/using-python-logging-module-to-info-messages-to-one-file-and-err-to-another-file
def setup_logger(rawsubjses_str: str, logDir: str = "/log"):

    subjses_str = rawsubjses_str.replace("_", "_ses-")
    subjses_str = "-".join(["sub", subjses_str])

    # Initiate logger
    logger = logging.getLogger()
    # When using multiprocessing/dask, we need to clear the handlers
    # each run (e.g., each new process/worker) or else they're just appended
    # (results in outputs for multiple subject_ses processes in each log file - this was a major headache to figure out).
    logger.handlers = []
    # The logger level MUST be set, or NO logging will be performed - also a major headache.
    logger.setLevel(logging.INFO)

    # Define paths to stdout and stderr log files
    # MSG_LOG_FILE = Path(logDir) / f"fastPipe_{subjses_str}_{logStart:%H%M%S%d%m%y}.log"
    # ERR_LOG_FILE = Path(logDir) / 'Errors' / f"fastPipe_{subjses_str}_{logStart:%H%M%S%d%m%y}.err"

    MSG_LOG_FILE = Path(logDir) / f"fastPipe_{subjses_str}.log"
    ERR_LOG_FILE = Path(logDir) / f"fastPipe_{subjses_str}_err.log"

    # Make the log file directories if they don't exist
    if not MSG_LOG_FILE.parent.exists():
        MSG_LOG_FILE.parent.mkdir(parents=True)
    if not ERR_LOG_FILE.parent.exists():
        ERR_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

    # What we want the log messages to look like
    log_fmt = "%(asctime)s | %(levelname)s | %(message)s"
    error_fmt = "%(asctime)s | %(levelname)s | %(message)s"
    date_fmt = "%m.%d.%y %H:%M:%S"

    # Setting up the stdout message log
    ## delay=True keeps the file from being created until output is emitted to the log
    msglog_file_handler = logging.FileHandler(MSG_LOG_FILE, mode='w+', delay=True)
    # Use the CustomFormatter defined below to format the look of the log file
    msglog_file_handler.setFormatter(CustomFormatter(log_fmt, date_fmt))
    # Set the level for this handler
    msglog_file_handler.setLevel(logging.INFO)
    logger.addHandler(msglog_file_handler)

    # Streaming logs to stdout - so we can track behavior using kubectl logs
    console_stream_handler = logging.StreamHandler(sys.stdout)
    console_stream_handler.setLevel(logging.INFO)
    logger.addHandler(console_stream_handler)

    errorlog_file_handler = logging.FileHandler(ERR_LOG_FILE, mode='w+', delay=True)
    errorlog_file_handler.setFormatter(CustomFormatter(error_fmt, date_fmt))
    errorlog_file_handler.setLevel(logging.ERROR)
    logger.addHandler(errorlog_file_handler)
    return (logger)

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

# Checking if the subject files are already uploaded to S3
def checkS3(subjses_str: str, access_key_id: str, secret_access_key: str, s3bucket: str, region_name: str = 'us-east-2'):
    import boto3

    logging.getLogger(__name__)

    # Define the parameters for a new AWS resource connection to S3
    s3 = boto3.resource(service_name='s3', region_name=region_name,
                        aws_access_key_id=access_key_id,
                        aws_secret_access_key=secret_access_key)
    # Use the resource connection above to connect to an S3 bucket
    bucket = s3.Bucket(s3bucket)
    # Get a dictionary of all objects in the bucket
    objects = bucket.objects.all()
    done_list = [object.key for object in objects]
    subjses_xz = str(subjses_str + ".tar.xz")
    # If there's an archive file for this subj_ses pairing in the bucket, return true
    if subjses_xz in done_list:
        subjses_done = True
    else:
        subjses_done = False

    return (subjses_done)


class CustomFormatter(logging.Formatter):

    # Calling os.system("") 'enables' ANSI codes
    os.system("")

    # Colored logging formatter, adapted from https://stackoverflow.com/a/56944256/3638629
    grey = '\x1b[38;21m'
    blue = '\x1b[38;5;39m'
    yellow = '\x1b[38;5;226m'
    red = '\x1b[38;5;196m'
    bold_red = '\x1b[31;1m'
    white = '\x1b[38;5;15m'
    reset = '\x1b[0m'

    def __init__(self, fmt: str, datefmt: str):
        super().__init__()
        self.fmt = fmt
        self.datefmt = datefmt
        self.FORMATS = {
            logging.DEBUG: self.grey + self.fmt + self.reset,
            logging.INFO: self.white + self.fmt + self.reset,
            logging.WARNING: self.yellow + self.fmt + self.reset,
            logging.ERROR: self.red + self.fmt + self.reset,
            logging.CRITICAL: self.bold_red + self.fmt + self.reset
        }

    def format(self, record):
        # Add an attribute that disables the formatter prefix (if true)
        # else format the message as specified herein
        # https://stackoverflow.com/questions/34954373/disable-format-for-some-messages
        if hasattr(record, 'simple') and record.simple:
            return record.getMessage()
        else:
            log_fmt = self.FORMATS.get(record.levelno)
            formatter = logging.Formatter(fmt=log_fmt, datefmt=self.datefmt)
            return formatter.format(record)


def shell_source(script: str):
    """Sometimes you want to emulate the action of "source" in bash,
    settings some environment variables. Here is a way to do it."""

    # Source the script passed in above, output the new shell environment, and save it
    # '.' is equal to source in bash;
    pipe = subprocess.Popen(". %s; env" % script, stdout=subprocess.PIPE, shell=True, executable="bash", text=True)
    output = pipe.communicate()[0]  # Grab the shell enviornment variables in a new-line delimited list
    env = dict((line.split("=", 1) for line in output.splitlines()))  # Split the new-line delimited list of key=value pairs into a dictionary
    os.environ.update(env)  # Update the environment - adds/changes any variables that are different in the passed environment


def setup_freesurfer(freesurfer_pathstr: str = None, subjects_dir_pathstr: str = None):

    ### Setting up FreeSurfer through Python ###
    # Set FreeSurfer environment variables as specified above
    os.environ["FREESURFER_HOME"] = freesurfer_pathstr
    os.environ["SUBJECTS_DIR"] = subjects_dir_pathstr

    # Tell FreeSurferEnv.sh to override (overwrite) pre-existing environment variables when setting up
    os.environ["FS_OVERRIDE"] = "1"
    setupFSenv = freesurfer_pathstr + "/SetUpFreeSurfer.sh"

    # Per https://docs.python.org/3/library/subprocess.html#subprocess.Popen:
    # when shell=True, the default shell is /bin/sh unless otherwise defined by 'executable' arg
    pipe = subprocess.Popen("source %s; env" % setupFSenv, stdout=subprocess.PIPE, shell=True, executable="bash", text=True)
    # Capture the shell enviornment variables in a new-line delimited list
    output = pipe.communicate()[0]
    # Split the new-line delimited list of key=value pairs into a dictionary
    env = dict((line.split("=", 1) for line in output.splitlines()))
    # Use the dictionary to update the current environment
    os.environ.update(env)


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

class HelpFormatter(argparse.HelpFormatter):
    """
    Help formatter that forces line breaks in texts where the text is <br>.
    """

    def _linebreak_sub(self):
        """
        Get the linebreak substitution string.

        Returns:
            str: The linebreak substitution string ("<br>").
        """
        return getattr(self, "linebreak_sub", "<br>")

    def _fill_text(self, text, width, indent):
        """
        Fill text with line breaks based on the linebreak substitution string.

        Args:
            text (str): The input text.
            width (int): The width for filling the text.
            indent (int): The indentation level.

        Returns:
            str: The formatted text with line breaks.
        """
        texts = text.split(self._linebreak_sub())
        return "\n".join(
            [super(HelpFormatter, self)._fill_text(tex, width, indent) for tex in texts]
        )

    def _split_lines(self, text: str, width: int):
        """
        Split lines in the text based on the linebreak substitution string.

        Args:
            text (str): The input text.
            width (int): The width for splitting lines.

        Returns:
            list: The list of lines.
        """
        texts = text.split(self._linebreak_sub())
        from itertools import chain

        return list(
            chain.from_iterable(
                super(HelpFormatter, self)._split_lines(tex, width) for tex in texts
            )
        )
