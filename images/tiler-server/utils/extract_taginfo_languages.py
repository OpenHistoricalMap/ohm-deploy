#!/usr/bin/env python3
"""
This script lists all valid languages from Taginfo to enable rendering those languages in the vector tiles (vtile).
"""

import requests
import re
import argparse
import json
import os
import boto3

KEY_REGEX = (
    r"^name:[a-z]{2,3}(-[A-Z][a-z]{3})?((-[a-z]{2,}|x-[a-z]{2,})(-[a-z]{2,})?)?(-([A-Z]{2}|\d{3}))?$"
)
MIN_NUM_OBJECTS = 50

def fetch_and_process_data(base_url):
    page = 1
    json_keys = []
    sql_lines = []
    query_params = {
        "include": "prevalent_values",
        "sortname": "count_all",
        "sortorder": "desc",
        "rp": 500,
        "page": 1,
        "query": "name:",
    }

    while True:
        query_params["page"] = page
        response = requests.get(base_url, params=query_params)
        if response.status_code != 200:
            print(f"Error fetching data from API: {response.status_code}")
            break
        data = response.json()
        if not data.get("data"):
            print("No more data available.")
            break

        for item in data["data"]:
            key = item["key"]
            count_all = item["count_all"]
            if re.match(KEY_REGEX, key) and count_all > MIN_NUM_OBJECTS:
                alias = key.replace(":", "_").replace("-", "_").lower()
                sql_line = f"tags -> '{key}' AS {alias}"
                sql_lines.append(sql_line)
                json_keys.append({
                    "key": alias,
                    "value": key,
                    "count": count_all
                })

        print(f"Processed page {page}")
        page += 1
        if page > data.get("total", 0) // query_params["rp"] + 1:
            break

    return json_keys, sql_lines

def write_sql_file(sql_lines, filename_sql):
    with open(filename_sql, "w") as file:
        file.write(",\n".join(sql_lines) + "\n")
    print(f"Matching keys saved to {filename_sql}")

def write_json_and_upload(json_data, json_path):
    with open(json_path, "w") as file:
        json.dump(json_data, file, indent=2)
    print(f"JSON file saved to {json_path}")
    bucket = os.environ.get("AWS_S3_BUCKET", "").replace("s3://", "")
    s3_key = "vtiles_languages.json"

    s3_client = boto3.client(
        "s3",
        aws_access_key_id=os.environ.get("AWS_ACCESS_KEY_ID"),
        aws_secret_access_key=os.environ.get("AWS_SECRET_ACCESS_KEY")
    )

    try:
        s3_client.upload_file(json_path, bucket, s3_key)
        print(f"vtiles_languages.json uploaded to s3://{bucket}/{s3_key}")
    except Exception as e:
        print(f"Failed to upload to S3: {str(e)}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch and save language tag keys.")
    parser.add_argument("--url", default="https://taginfo.openhistoricalmap.org/api/4/keys/all", help="Input Taginfo API URL")
    parser.add_argument("--output", default="/opt/config/languages.sql", help="Output SQL file path")
    parser.add_argument("--json-output", default="/opt/config/vtiles_languages.json", help="Output JSON file path")
    args = parser.parse_args()

    json_data, sql_lines = fetch_and_process_data(args.url)
    print(f"Found {len(json_data)} matching keys.")
    write_sql_file(sql_lines, args.output)
    write_json_and_upload(json_data, args.json_output)
