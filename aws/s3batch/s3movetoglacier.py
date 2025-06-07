import boto3
import csv
import io
import time

# --- Configuration ---
SOURCE_BUCKET_NAME = 'abcd-v51'
INVENTORY_REPORT_BUCKET = 'brave-abcd'  # Where S3 Inventory delivers reports
INVENTORY_REPORT_PREFIX = 'abcd-v51/abcd-v51/abcd-v51-inventory/2025-06-01T01-00Z'  # e.g., 'inventory-reports/my-source-bucket/'
MANIFEST_BUCKET = 'brave-abcd'  # Where the filtered manifest will be stored
BATCH_OPERATIONS_REPORT_BUCKET = 'brave-abcd'  # Where the batch job report will be stored
IAM_ROLE_ARN_FOR_BATCH_OPERATIONS = 'arn:aws:iam::123456789012:role/S3BatchOperationsRole'  # Replace with your IAM role ARN
REGION = 'us-east-2'  # e.g., 'us-east-1'

TARGET_STORAGE_CLASS = 'GLACIER'
EXCLUDE_STORAGE_CLASS = 'GLACIER'  # Objects already in this class will be excluded

s3_client = boto3.client('s3', region_name=REGION)
s3control_client = boto3.client('s3control', region_name=REGION)
account_id = boto3.client('sts').get_caller_identity().get('Account')

def get_latest_inventory_manifest(inventory_bucket, inventory_prefix):
    """
    Finds the latest S3 Inventory manifest.json file.
    Assumes inventory reports are stored in a time-partitioned manner.
    """
    paginator = s3_client.get_paginator('list_objects_v2')
    pages = paginator.paginate(Bucket=inventory_bucket, Prefix=inventory_prefix, Delimiter='/')
    latest_timestamp_prefix = None

    for page in pages:
        for prefix in page.get('CommonPrefixes', []):
            current_prefix = prefix.get('Prefix')
            # Extract timestamp from prefix (assuming YYYY-MM-DDTHH-MMZ format)
            try:
                timestamp_str = current_prefix.split('/')[-2]  # Assumes last part before trailing / is the timestamp
                if latest_timestamp_prefix is None or timestamp_str > latest_timestamp_prefix.split('/')[-2]:
                    latest_timestamp_prefix = current_prefix
            except IndexError:
                continue  # Skip if prefix format is not as expected

    if latest_timestamp_prefix:
        manifest_key = f"{latest_timestamp_prefix}manifest.json"
        try:
            manifest_obj = s3_client.get_object(Bucket=inventory_bucket, Key=manifest_key)
            manifest_content = manifest_obj['Body'].read().decode('utf-8')
            return manifest_content
        except s3_client.exceptions.NoSuchKey:
            print(f"Warning: Manifest file {manifest_key} not found. Ensure inventory report is generated.")
            return None
    return None

def filter_inventory_report(manifest_content, exclude_storage_class):
    """
    Reads the inventory report from the manifest, filters objects, and creates a new manifest.
    """
    manifest_json = json.loads(manifest_content)
    inventory_file_path = manifest_json['files'][0]['key']  # Get the key of the inventory CSV.GZ file

    print(f"Downloading and processing inventory file: s3://{INVENTORY_REPORT_BUCKET}/{inventory_file_path}")
    inventory_obj = s3_client.get_object(Bucket=INVENTORY_REPORT_BUCKET, Key=inventory_file_path)

    # Decompress gzipped content
    with gzip.open(io.BytesIO(inventory_obj['Body'].read()), 'rt') as f:
        reader = csv.reader(f)
        header = next(reader)  # Skip header if present, or adapt if your report includes it

        # Determine column indices dynamically
        try:
            bucket_idx = header.index('Bucket') if 'Bucket' in header else 0
            key_idx = header.index('Key') if 'Key' in header else 1
            storage_class_idx = header.index('StorageClass') if 'StorageClass' in header else 3  # Default based on common inventory format
            print(storage_class_idx)
            version_id_idx = header.index('VersionId') if 'VersionId' in header else -1  # Optional for versioned buckets
        except ValueError as e:
            print(f"Error: Required column not found in inventory report header: {e}. Please check your inventory configuration.")
            return None

        filtered_objects = []
        for row in reader:
            if len(row) > max(bucket_idx, key_idx, storage_class_idx):  # Ensure row has enough columns
                bucket = row[bucket_idx]
                key = row[key_idx]
                storage_class = row[storage_class_idx]
                version_id = row[version_id_idx] if version_id_idx != -1 else None

                if bucket == SOURCE_BUCKET_NAME and storage_class != exclude_storage_class:
                    if version_id:
                        filtered_objects.append(f"{bucket},{key},{version_id}")
                    else:
                        filtered_objects.append(f"{bucket},{key}")

    return filtered_objects

def create_manifest_file(filtered_objects):
    """
    Creates a CSV manifest file for S3 Batch Operations.
    """
    manifest_content = "\n".join(filtered_objects)
    manifest_key = f"batch-ops-manifests/{SOURCE_BUCKET_NAME}-move-to-glacier-{int(time.time())}.csv"

    s3_client.put_object(
        Bucket=MANIFEST_BUCKET,
        Key=manifest_key,
        Body=manifest_content,
        ContentType='text/csv'
    )
    print(f"Manifest file created: s3://{MANIFEST_BUCKET}/{manifest_key}")
    return f"arn:aws:s3:::{MANIFEST_BUCKET}/{manifest_key}"

def create_s3_batch_job(manifest_arn, job_description):
    """
    Creates an S3 Batch Operations job to change storage class.
    """
    response = s3control_client.create_job(
        AccountId=account_id,
        Operation={
            'S3PutObjectCopy': {
                'TargetResource': f"arn:aws:s3:::{SOURCE_BUCKET_NAME}",
                'StorageClass': TARGET_STORAGE_CLASS
            }
        },
        Report={
            'Bucket': f"arn:aws:s3:::{BATCH_OPERATIONS_REPORT_BUCKET}",
            'Format': 'Report_CSV_20180820',
            'Enabled': True,
            'Prefix': f"batch-ops-reports/{job_description}/",
            'ReportScope': 'AllTasks'
        },
        Manifest={
            'Spec': {
                'Format': 'S3BatchOperations_CSV_20180820',
                'Fields': ['Bucket', 'Key', 'VersionId'] if 'VersionId' in get_latest_inventory_manifest(INVENTORY_REPORT_BUCKET, INVENTORY_REPORT_PREFIX) else ['Bucket', 'Key']
            },
            'Location': {
                'ObjectArn': manifest_arn,
                'Etag': s3_client.head_object(Bucket=MANIFEST_BUCKET, Key=manifest_arn.split('/')[-1])['ETag'].strip('"')  # Get ETag of the manifest object
            }
        },
        Priority=10,
        RoleArn=IAM_ROLE_ARN_FOR_BATCH_OPERATIONS,
        Description=job_description,
        ConfirmationRequired=False
    )
    return response['JobId']


if __name__ == "__main__":
    import json
    import gzip

    print("Starting S3 Batch Operation to move objects to Glacier Flexible Retrieval...")

    # 1. Get the latest S3 Inventory manifest
    manifest_content = get_latest_inventory_manifest(INVENTORY_REPORT_BUCKET, INVENTORY_REPORT_PREFIX)
    if not manifest_content:
        print("Could not retrieve latest inventory manifest. Exiting.")
        exit()

    # 2. Filter the inventory report
    print(f"Filtering inventory report to exclude objects already in {EXCLUDE_STORAGE_CLASS}...")
    objects_to_process = filter_inventory_report(manifest_content, EXCLUDE_STORAGE_CLASS)

    if not objects_to_process:
        print("No objects found to move to Glacier Flexible Retrieval. Exiting.")
        exit()

    print(f"Found {len(objects_to_process)} objects to move.")

    # 3. Create the manifest file for S3 Batch Operations
    manifest_arn = create_manifest_file(objects_to_process)

    # # 4. Create the S3 Batch Operations job
    # job_description = f"Move-to-{TARGET_STORAGE_CLASS}-{time.strftime('%Y%m%d-%H%M%S')}"
    # job_id = create_s3_batch_job(manifest_arn, job_description)

    # print(f"S3 Batch Operations job created with ID: {job_id}")
    # print(f"Monitor the job status in the AWS S3 console: https://console.aws.amazon.com/s3/home?region={REGION}#jobs/{job_id}")

    # # Optional: Wait for job completion and check status
    # print("Waiting for job to complete (this may take a while)...")
    # while True:
    #     job_status = s3control_client.describe_job(AccountId=account_id, JobId=job_id)['Job']['Status']
    #     print(f"Job status: {job_status}")
    #     if job_status in ['Complete', 'Failed', 'Cancelled']:
    #         break
    #     time.sleep(30)  # Check every 30 seconds

    # print(f"Job {job_id} finished with status: {job_status}")
    # if job_status == 'Complete':
    #     print(f"Successfully moved objects to {TARGET_STORAGE_CLASS}.")
    # else:
    #     print(f"Batch job {job_id} did not complete successfully. Check the completion report in s3://{BATCH_OPERATIONS_REPORT_BUCKET}/batch-ops-reports/{job_description}/ for details.")
