import boto3


def delete_all_objects_from_s3_folder():
    """
    This function deletes all files in a folder from S3 bucket
    :return: None
    """
    bucket_name = "abcd-working"
    s3_client = boto3.client("s3")
    # First we list all files in folder
    response = s3_client.list_objects_v2(Bucket=bucket_name, Prefix="derivatives/fmriprep")
    files_in_folder = response["Contents"]
    files_to_delete = []
    # We will create Key array to pass to delete_objects function
    for f in files_in_folder:
        files_to_delete.append({"Key": f["Key"]})
    # This will delete all files in a folder
    response = s3_client.delete_objects(
        Bucket=bucket_name, Delete={"Objects": files_to_delete}
    )
    print(response)


delete_all_objects_from_s3_folder()
