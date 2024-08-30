#!/usr/bin/env python
# fmt:off
import config
import os
# FastSurfer (actually numpy) crashes when run with multiple threads
# https://github.com/Deep-MI/FastSurfer/issues/371
# Temporary fix is to set all possible numpy threads variables before loading numpy
nThreads = config.nThreads
os.environ["OMP_NUM_THREADS"] = nThreads
os.environ["OPENBLAS_NUM_THREADS"] = nThreads
os.environ["MKL_NUM_THREADS"] = nThreads
os.environ["VECLIB_MAXIMUM_THREADS"] = nThreads
os.environ["NUMEXPR_NUM_THREADS"] = nThreads

import argparse
import boto3
import ndaDownload
import sys
import time

from boto3.dynamodb.conditions import Attr
from dataclasses import dataclass
from datetime import datetime
from fastSurferShell import FastSurfer
from utils import cleanup, logTitle, s3Uploader, s3Downloader, xzPack, setup_logger
from pathlib import Path
# fmt:on

####################
# ## ARGUMENTS ### #
####################


def make_parser() -> argparse.ArgumentParser:

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "-b", "--batchindex",
        type=str,
        dest="batchindex",
        required=True)

    parser.add_argument(
        "-a", "--all",
        action='store_true',
        dest="getAll",
        required=False)

    parser.add_argument(
        "-p", "--runParc",
        action="store_true",
        dest="runParc",
        required=False)

    return parser


def setProcessingFlag(dbtable, batchindex: str, rawsubjses_str: str, val: int):
    batchindex = int(batchindex)
    dbtable.update_item(
        Key={
            'BatchIndex': batchindex,
            'subject_timepoint': rawsubjses_str
        },
        UpdateExpression='SET InProcessing = :val1',
        ExpressionAttributeValues={
            ':val1': val
        }
    )


def setSegmentedFlag(dbtable, batchindex: str, rawsubjses_str: str, val: int):
    batchindex = int(batchindex)
    dbtable.update_item(
        Key={
            'BatchIndex': batchindex,
            'subject_timepoint': rawsubjses_str
        },
        UpdateExpression='SET Segmented = :val1',
        ExpressionAttributeValues={
            ':val1': val
        }
    )

def getIDs(dbtable, batchIndex: str, getall: bool = False, runParc: bool = False) -> list:
    # DynamoDB table scans return paginated results, and have to be repeated to get the full results
    # https://stackoverflow.com/questions/36780856/complete-scan-of-dynamodb-with-boto3
    # Due to the use of the 'Import from S3 CSV' method for writing items to DynamoDB, ALL
    # columns are string type
    # If we're getting ALL IDs, regardless of processing status...
    batchIndex = int(batchIndex)
    if getall:
        print('Retrieving subject IDs...')
        if runParc:
            # Scan the table for keys with the specified batchIndex number and return their subject_timepoints
            idScan = dbtable.scan(
                FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('Segmented').eq(1),
                ConsistentRead=True,
                ProjectionExpression='subject_timepoint'
            )
            ids2run = [d['subject_timepoint'] for d in idScan['Items']]
            # Keep running the scan until we've received all the subject_timepoints
            while 'LastEvaluatedKey' in idScan:
                idScan = dbtable.scan(
                    FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('Segmented').eq(1),
                    ConsistentRead=True,
                    ProjectionExpression='subject_timepoint',
                    ExclusiveStartKey=idScan['LastEvaluatedKey']
                )
                # Extend the running list with the additional subject_timepoints
                ids2run.extend([d['subject_timepoint'] for d in idScan['Items']])
        else:
            # Scan the table for keys with the specified batchIndex number and return their subject_timepoints
            idScan = dbtable.scan(
                FilterExpression=Attr('BatchIndex').eq(batchIndex),
                ConsistentRead=True,
                ProjectionExpression='subject_timepoint'
            )
            ids2run = [d['subject_timepoint'] for d in idScan['Items']]
            # Keep running the scan until we've received all the subject_timepoints
            while 'LastEvaluatedKey' in idScan:
                idScan = dbtable.scan(
                    FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('Segmented').eq(1),
                    ConsistentRead=True,
                    ProjectionExpression='subject_timepoint',
                    ExclusiveStartKey=idScan['LastEvaluatedKey']
                )
                # Extend the running list with the additional subject_timepoints
                ids2run.extend([d['subject_timepoint'] for d in idScan['Items']])
    # If we're excluding scans that are 'in processing' or already finished...
    else:
        if runParc:
            print('Retrieving pre-segmented subject IDs...')
            # Scan the table for keys with the specified batchIndex number that ARE segmented (and no longer in processing), then return their subject_timepoints
            # NOTE: Need to add back the filter for the inProcessing flag
            idScan = dbtable.scan(
                FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('Segmented').eq(1),
                ConsistentRead=True,
                ProjectionExpression='subject_timepoint'
            )
            ids2run = [d['subject_timepoint'] for d in idScan['Items']]
            # Keep running the scan until we've received all the subject_timepoints
            while 'LastEvaluatedKey' in idScan:
                idScan = dbtable.scan(
                    FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('Segmented').eq(1),
                    ConsistentRead=True,
                    ProjectionExpression='subject_timepoint',
                    ExclusiveStartKey=idScan['LastEvaluatedKey']
                )
                # Extend the running list with the additional subject_timepoints
                ids2run.extend([d['subject_timepoint'] for d in idScan['Items']])
        else:
            print('Retrieving unprocessed subject IDs...')
            # Scan the table for keys with the specified batchIndex number that are NOT in processing and NOT yet segmented, then return their subject_timepoints
            idScan = dbtable.scan(
                FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('InProcessing').eq(0) & Attr('Segmented').eq(0),
                ConsistentRead=True,
                ProjectionExpression='subject_timepoint'
            )
            ids2run = [d['subject_timepoint'] for d in idScan['Items']]
            # Keep running the scan until we've received all the subject_timepoints
            while 'LastEvaluatedKey' in idScan:
                idScan = dbtable.scan(
                    FilterExpression=Attr('BatchIndex').eq(batchIndex) & Attr('InProcessing').eq(0) & Attr('Segmented').eq(0),
                    ConsistentRead=True,
                    ProjectionExpression='subject_timepoint',
                    ExclusiveStartKey=idScan['LastEvaluatedKey']
                )
                # Extend the running list with the additional subject_timepoints
                ids2run.extend([d['subject_timepoint'] for d in idScan['Items']])

    return ids2run


@dataclass
class FastPipe:
    rawsubjses_str: str
    batchindex: str
    runParc: bool = False
    nThreads: int = 4

    def __post_init__(self):
        print(f'Starting FastPipe for {self.rawsubjses_str}')
        setup_logger(self.rawsubjses_str)
        logTitle(f"BRC ABCD FastSurfer Pipeline", level=1)
        startTime = datetime.now()
        logTitle(f"Pipeline started {startTime.strftime('%A, %B %d, %Y, %H:%M:%S')}", level=2)

        try:
            if self.runParc:
                self.parcellation_run()
            else:
                self.segmentation_run()
        except Exception as exc:
            sys.exit(1)

        stopTime = datetime.now()
        # https://stackoverflow.com/questions/538666/format-timedelta-to-string/539360#539360
        runTime = stopTime - startTime
        totalSeconds = runTime.total_seconds()
        hours, remainder = divmod(totalSeconds, 3600)
        minutes, seconds = divmod(remainder, 60)
        logTitle(f"Pipeline finished {stopTime.strftime('%A, %B %d, %Y, %H:%M:%S')} \
                    Total Run Time: {'{:02}:{:02}:{:02}'.format(int(hours), int(minutes), int(seconds))}")

    # Need to clean this up so we're not passing the same batch of fxn arguments multiple times.
    def segmentation_run(self):
        try:
            setProcessingFlag(dbtable, self.batchindex, self.rawsubjses_str, 1)
            Path('/work').mkdir(parents=True, exist_ok=True)
            ndaDownload.Downloader(self.rawsubjses_str, nThreads)
            FastSurfer(self.rawsubjses_str)
            xzPack(self.rawsubjses_str, 'seg')
            s3Uploader(self.rawsubjses_str, 'seg')
        except Exception as exc:
            raise exc
        else:
            setProcessingFlag(dbtable, self.batchindex, self.rawsubjses_str, 0)
            cleanup()

    def parcellation_run(self):
        try:
            setProcessingFlag(dbtable, self.batchindex, self.rawsubjses_str, 1)
            Path('/work').mkdir(parents=True, exist_ok=True)
            s3Downloader(self.rawsubjses_str, 'seg')
            FastSurfer(self.rawsubjses_str, nThreads, self.runParc)
            xzPack(self.rawsubjses_str)
            s3Uploader(self.rawsubjses_str)
        except Exception as exc:
            setProcessingFlag(dbtable, self.batchindex, self.rawsubjses_str, 0)
            raise exc
        else:
            setProcessingFlag(dbtable, self.batchindex, self.rawsubjses_str, 0)
            cleanup()


if __name__ == '__main__':

    args = make_parser().parse_args()
    print("Creating AWS session....")
    session = boto3.Session(
        aws_access_key_id=config.aws_access_key_id,
        aws_secret_access_key=config.aws_secret_access_key,
        region_name=config.aws_region
    )
    print(f"Batch index called was: {args.batchindex}")
    dynamodb = session.resource('dynamodb')
    dbtable = dynamodb.Table('FastBatchTracking')
    ids2run = getIDs(dbtable, args.batchindex, args.getAll, args.runParc)
    if len(ids2run) < 1:
        print("No IDs received from tracking table.")
    for rawsubjses_str in ids2run:
        try:
            f = FastPipe(rawsubjses_str, args.batchindex, args.runParc)
        except Exception as exc:
            print(exc)
            next
        else:
            setProcessingFlag(dbtable, args.batchindex, rawsubjses_str, 0)
            setSegmentedFlag(dbtable, args.batchindex, rawsubjses_str, 1)
