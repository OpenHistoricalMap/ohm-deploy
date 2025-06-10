import os
import psycopg2
import json
import os
import boto3


def get_db_connection():
    """
    Establish and return a connection to the PostgreSQL database using environment variables.
    Returns:
        psycopg2.connection: A PostgreSQL connection object.
    """
    return psycopg2.connect(
        dbname=os.getenv("POSTGRES_DB", "gis"),
        user=os.getenv("POSTGRES_USER", "postgres"),
        password=os.getenv("POSTGRES_PASSWORD", "password"),
        host=os.getenv("POSTGRES_HOST", "localhost"),
        port=os.getenv("POSTGRES_PORT", "5432"),
    )


def write_json_and_upload(json_data, json_path, s3_key):
    with open(json_path, "w") as file:
        json.dump(json_data, file, indent=2)
    print(f"JSON file saved to {json_path}")

    bucket = os.environ.get("AWS_S3_BUCKET", "").replace("s3://", "")
    s3_client = boto3.client(
        "s3",
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY"),
    )

    try:
        s3_client.upload_file(json_path, bucket, s3_key)
        print(f"Uploaded to s3://{bucket}/{s3_key}")
    except Exception as e:
        print(f"Failed to upload to S3: {str(e)}")