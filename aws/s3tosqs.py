import boto3

def send_s3_objects_to_sqs(bucket_name, prefix, queue_name, num_objects=None):
    """
    Iterates over objects in an S3 bucket under a given prefix and sends
    the object names to an AWS SQS queue.

    Args:
        bucket_name (str): The name of the S3 bucket.
        prefix (str): The prefix (directory path) within the S3 bucket to iterate over.
        queue_url (str): The URL of the AWS SQS queue.
        num_objects (int, optional): The maximum number of object names to send.
                                     If None, all objects under the prefix will be processed.
                                     Defaults to None.
    """
    s3 = boto3.client('s3')
    sqs = boto3.client('sqs')

    try:
        queue_url = sqs.get_queue_url(QueueName=queue_name)['QueueUrl']
    except Exception as e:
        print(f"Could not locate SQS queue with name: {queue_name}")
        return

    try:
        paginator = s3.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket_name, Prefix=prefix)

        nda_guids = []
        for page in pages:
            if 'Contents' in page:
                for obj in page['Contents']:
                    if 'baselineYear1Arm1_ABCD-MPROC-T1' in obj['Key']:
                        object_key = obj['Key']
                        # Extract the filename from the path
                        prefix_path = object_key.split('/')[-1]
                        # Extract the NDA GUID
                        nda_guid = prefix_path.split('_')[0]
                        nda_guids.append(nda_guid)
                    else:
                        continue
                    if num_objects is not None and len(nda_guids) >= num_objects:
                        print(f"Reached the specified limit of {num_objects} objects.")
                        break
                else:
                    continue
                break

        if len(nda_guids) > 0:
            try:
                for i in range(0, len(nda_guids), 10):
                    batch = nda_guids[i:i + 10]
                    queue_entries = []
                    for item_index, item in enumerate(batch):
                        queue_entries.append({'Id': str(item_index), 'MessageBody': item, 'MessageGroupId': 'ABCDsubjsesIDs'})
                        print(item)
                    sqs.send_message_batch(QueueUrl=queue_url, Entries=queue_entries)

            except Exception as e:
                print(f"Error sending message: {e}")

        else:
            print(f"No objects found under the prefix '{prefix}' in bucket '{bucket_name}'.")
            return
    except Exception as e:
        print(f"An error occurred: {e}")
        return


if __name__ == '__main__':
    # Replace with your actual bucket name, prefix, and SQS queue URL
    s3_bucket_name = 'abcd-v51'
    s3_prefix = 'fmriresults01/abcd-mproc-release5/'  # Ensure this ends with a '/' if it's a directory
    sqs_queue_name = 'cloudpipe-jobqueue.fifo'
    number_of_objects_to_send = 10  # Set to None to send all objects
    send_s3_objects_to_sqs(s3_bucket_name, s3_prefix, sqs_queue_name, number_of_objects_to_send)
