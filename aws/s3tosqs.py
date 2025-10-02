import boto3
import sys
from pathlib import Path
from time import sleep

def send_s3_objects_to_sqs(input_bucket_name, input_prefix, completed_bucket_name, completed_prefix, queue_name, num_jobs):
    """
    Iterates over objects in an S3 bucket under a given prefix and sends
    the object names to an AWS SQS queue.

    Args:
        input_bucket_name (str): The name of the S3 bucket where the input NIFTi files are stored.
        input_prefix (str): The prefix (directory path) within the input S3 bucket to iterate over.
        completed_bucket_name (str): The name of the S3 bucket where preprocessed scans are stored.
        completed_prefix (str): The prefix (directory path) within the completed S3 bucket to iterate over.
        queue_name (str): The name of the AWS SQS queue.
        num_jobs (int, optional): The maximum number of object names to send.
                                     If None, all objects under the prefix will be processed.
                                     Defaults to None.
    """
    s3 = boto3.client('s3')
    sqs = boto3.client('sqs')
    paginator = s3.get_paginator('list_objects_v2')

    # Get the URL for the SQS queue
    try:
        queue_url = sqs.get_queue_url(QueueName=queue_name)['QueueUrl']
    except Exception as e:
        print(f"Could not locate SQS queue with name: {queue_name}")
        return

    # try:
    # Create a paginator to iterate over the contents of the input bucket
    input_pages = paginator.paginate(Bucket=input_bucket_name, Prefix=input_prefix)

    # If we don't already have a local csv file list, create a list of all the NDA GUIDs that have Y0 baseline anatomicals (T1w only)
    if not Path('input_nda_guids.csv').exists():
        # Get all the NDA GUIDS
        input_nda_guids = []
        print('Creating list of NDA GUIDs (local list not found). Please wait...')
        for page in input_pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    if 'baselineYear1Arm1_ABCD-MPROC-T1' in obj['Key']:
                        object_key = obj['Key']
                        # Extract the filename from the path
                        prefix_path = object_key.split('/')[-1]
                        # Extract the NDA GUID
                        input_nda_guid = prefix_path.split('_')[0]
                        input_nda_guids.append(input_nda_guid)

        with open('input_nda_guids.csv', 'w') as f:
            f.write("\n".join(input_nda_guids))

    # Else just read the list of NDA GUIDs from the existing file
    else:
        input_nda_guids = open('input_nda_guids.csv').read().splitlines()

    # if len(input_nda_guids) > 0:
    #     print('Found local list of NDA GUIDS...')
    # else:
    #     print("No GUIDS found on S3 storage...")

    # Create a paginator to iterate over the contents of the completed bucket
    completed_pages = paginator.paginate(Bucket=completed_bucket_name, Prefix=completed_prefix)
    completed_nda_guids = []

    for page in completed_pages:
        if 'Contents' in page:
            for obj in page['Contents']:
                if "long-template-complete" in obj['Key']:
                    completed_nda_guid = obj['Key'].split('/')[-2].split('sub-')[-1]
                    completed_nda_guids.append(completed_nda_guid)
                else:
                    continue

    input = set(input_nda_guids)
    completed = set(completed_nda_guids)
    todo = input.difference(completed)
    todo_nda_guids = list(todo)
    if num_jobs is None:
        num_jobs = len(todo_nda_guids)
    elif num_jobs == 0:
        print('Number of objects to send set to 0. Stopping...')
        sys.exit()
    elif num_jobs > len(todo_nda_guids):
        num_jobs = todo_nda_guids
    todo_nda_guids = todo_nda_guids[0:num_jobs]
    # Send the unprocessed GUIDs
    if len(todo_nda_guids) > 0:
        try:
            for i in range(0, len(todo_nda_guids), 10):
                batch = todo_nda_guids[i:i + 10]
                queue_entries = []
                for item_index, item in enumerate(batch):
                    queue_entries.append({'Id': str(item_index), 'MessageBody': item, 'MessageGroupId': 'ABCDsubjsesIDs'})
                    print(item)
                sqs.send_message_batch(QueueUrl=queue_url, Entries=queue_entries)
                # Slow down to avoid slamming the API server/Karpenter/Argo Workflows Controller
                print('Sleeping for 60 seconds...')
                sleep(60)

        except Exception as e:
            print(f"Error sending message: {e}")

    else:
        print(f"No objects found under the prefix '{input_prefix}' in bucket '{input_bucket_name}'.")
        return


if __name__ == '__main__':
    # Replace with your actual bucket name, prefix, and SQS queue URL
    input_bucket_name = 'abcd-v51'
    input_prefix = 'fmriresults01/abcd-mproc-release5/'  # Ensure this ends with a '/' if it's a directory
    completed_bucket_name = 'abcd-working'
    completed_prefix = 'derivatives/xcpd/'
    sqs_queue_name = 'cloudpipe-jobqueue.fifo'
    num_jobs = 1
    send_s3_objects_to_sqs(input_bucket_name, input_prefix, completed_bucket_name, completed_prefix, sqs_queue_name, num_jobs)
