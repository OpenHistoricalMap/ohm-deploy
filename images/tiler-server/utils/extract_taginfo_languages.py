"""
This script lists all valid languages from Taginfo to enable rendering those languages in the vector tiles (vtile).
"""

import requests
import re
import argparse

KEY_REGEX = (
    r"^name:[a-z]{2,3}(-[A-Z][a-z]{3})?((-[a-z]{2,}|x-[a-z]{2,})(-[a-z]{2,})?)?(-([A-Z]{2}|\d{3}))?$"
)
MIN_NUM_OBJECTS = 50

def fetch_and_process_data(base_url):
    page = 1
    matching_keys = []
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
                formatted_key = f"tags -> '{key}' AS {key.replace(':', '_').replace('-', '_').lower()}"
                matching_keys.append(formatted_key)

        print(f"Processed page {page}")
        page += 1
        if page > data.get("total", 0) // query_params["rp"] + 1:
            break

    return matching_keys

def write_to_file(keys, filename):
    with open(filename, "w") as file:
        file.write(",\n".join(keys) + "\n")
    print(f"Matching keys saved to {filename}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Fetch and save language tag keys.")
    parser.add_argument("--url", default="https://taginfo.openhistoricalmap.org/api/4/keys/all", help="Input Taginfo API URL")
    parser.add_argument("--output", default="/opt/config/languages.sql", help="Output SQL file path")
    args = parser.parse_args()

    results = fetch_and_process_data(args.url)
    print(f"Found {len(results)} matching keys.")
    write_to_file(results, args.output)
