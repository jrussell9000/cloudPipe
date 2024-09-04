import os


aws_access_key_id: str = os.environ['AWS_ACCESS_KEY_ID']
aws_secret_access_key: str = os.environ['AWS_SECRET_ACCESS_KEY']
aws_s3bucket: str = "brc-abcd"
aws_region: str = "us-east-1"
batch_size: int = 10
nda_username: str = os.environ['NDA_USERNAME']
nda_password: str = os.environ['NDA_PASSWORD']
miNDAR_packageID: str = '1228348'
miNDAR_password: str = os.environ['MINDAR_PASSWORD']
miNDAR_username: str = "_".join([nda_username, miNDAR_packageID])
miNDAR_host: str = os.environ['MINDAR_HOST']
# miNDAR_host = "mindarvpc.cqahbwk3l1mb.us-east-1.rds.amazonaws.com"
miNDAR_tablename = "fmriresults01"
trackingdb_tablename = "FastBatchTracking"
nThreads: str = "1"
