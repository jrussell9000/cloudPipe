import boto3
import mysql.connector
from mysql.connector import Error
import os

# --- Configuration - PLEASE FILL THESE IN ---
AWS_REGION = 'your-aws-region'  # e.g., 'us-east-1'
S3_BUCKET_NAME = 'your-s3-bucket-name'

DB_HOST = 'your-rds-endpoint'  # Your RDS MySQL instance endpoint
DB_NAME = 'your-database-name'
DB_USER = 'your-database-user'
DB_PASSWORD = 'your-database-password'  # Consider using environment variables or a secrets manager for passwords
TARGET_TABLE_NAME = 'your_target_table'  # The table where you want to add the column and S3 keys
NEW_COLUMN_NAME_FOR_S3_KEYS = 's3_object_key'  # The name for the new column
# --- End of Configuration ---

def list_s3_object_keys(bucket_name, region_name):
    """
    Lists all object keys in the specified S3 bucket.
    """
    s3_keys = []
    s3_client = boto3.client('s3', region_name=region_name)
    try:
        paginator = s3_client.get_paginator('list_objects_v2')
        page_iterator = paginator.paginate(Bucket=bucket_name)
        for page in page_iterator:
            if 'Contents' in page:
                for obj in page['Contents']:
                    s3_keys.append(obj['Key'])
        print(f"Successfully retrieved {len(s3_keys)} object keys from bucket '{bucket_name}'.")
    except Exception as e:
        print(f"Error listing S3 objects: {e}")
        raise
    return s3_keys

def main():
    print("Starting script...")

    # 1. Get S3 object keys
    try:
        s3_object_keys = list_s3_object_keys(S3_BUCKET_NAME, AWS_REGION)
    except Exception:
        print("Failed to retrieve S3 object keys. Exiting.")
        return

    if not s3_object_keys:
        print("No S3 object keys found or an error occurred. Exiting.")
        return

    # 2. Connect to RDS MySQL and process
    db_connection = None  # Initialize db_connection to None
    try:
        print(f"Connecting to MySQL database '{DB_NAME}' on host '{DB_HOST}'...")
        db_connection = mysql.connector.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )

        if db_connection.is_connected():
            cursor = db_connection.cursor()
            print("Successfully connected to MySQL database.")

            # Check if target table exists
            cursor.execute(f"SHOW TABLES LIKE '{TARGET_TABLE_NAME}';")
            if not cursor.fetchone():
                print(f"Error: Table '{TARGET_TABLE_NAME}' does not exist in database '{DB_NAME}'.")
                print("Please create the table first before running this script.")
