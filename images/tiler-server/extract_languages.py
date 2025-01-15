import requests
import re
BASE_URL = "https://taginfo.openhistoricalmap.org/api/4/keys/all"
QUERY_PARAMS = {
    "include": "prevalent_values",
    "sortname": "count_all",
    "sortorder": "desc",
    "rp": 500,
    "page": 1,
    "query": "name:",
}

KEY_REGEX = (
    r"^name:[a-z]{2,3}(-[A-Z][a-z]{3})?([-_](x-)?[a-z]{2,})?(-([A-Z]{2}|\d{3}))?$"
)
MIN_NUM_OBJECTS = 50


def fetch_and_process_data():
    page = 1
    matching_keys = []

    while True:
        QUERY_PARAMS["page"] = page
        response = requests.get(BASE_URL, params=QUERY_PARAMS)
        if response.status_code != 200:
            print(f"Error fetching data from API: {response.status_code}")
            break
        data = response.json()
        if not data.get("data"):
            print("No more data available.")
            break

        # Filter and process the data
        for item in data["data"]:
            key = item["key"]
            count_all = item["count_all"]
            if re.match(KEY_REGEX, key) and count_all > MIN_NUM_OBJECTS:
                # Format the key into SQL-like string
                formatted_key = f"tags -> '{key}' AS {key.replace(':', '_').replace('-', '_').lower()}"
                matching_keys.append(formatted_key)
        print(f"Processed page {page}")
        page += 1
        # Stop if we reach the last page
        if page > data.get("total", 0) // QUERY_PARAMS["rp"] + 1:
            break
    return matching_keys

def write_to_file(keys, filename="config/languages.sql"):
    with open(filename, "w") as file:
        file.write(",\n".join(keys) + "\n")
    print(f"Matching keys saved to {filename}")


if __name__ == "__main__":
    results = fetch_and_process_data()
    print(f"Found {len(results)} matching keys.")
    write_to_file(results)
