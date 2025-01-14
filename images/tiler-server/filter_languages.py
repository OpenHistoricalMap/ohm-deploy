"""
This script processes a SQL template file (`languages.template.sql`) to filter out specific lines 
based on the popularity of language tags using the OpenHistoricalMap TagInfo API.
"""

import re
import requests


def main():
    input_file = "config/languages.template.sql"
    output_file = "config/languages.sql"

    # Initialize an array to store valid lines
    valid_lines = []

    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            # Match lines in the format: tags -> 'name:aaq' AS name_aaq,
            match = re.search(
                r"tags\s*->\s*'name:([^']+)'\s*AS\s*name_[^,]+,", line.strip()
            )
            if not match:
                continue

            lang_code = match.group(1)
            url = (
                "https://taginfo.openhistoricalmap.org/api/4/tags/"
                "popular?sortname=count_all&sortorder=desc&rp=26&page=1&query=name%3A"
                + lang_code
            )

            try:
                response = requests.get(url)
                response.raise_for_status()
                response_json = response.json()
                if "data" in response_json and len(response_json["data"]) > 1:
                    print("Adding: " + line.strip())
                    valid_lines.append(line.strip())  # Add line to array
            except requests.exceptions.RequestException as e:
                print(f"Request failed for language '{lang_code}': {e}")

    # Write all valid lines to the output file, ensuring no trailing comma
    if valid_lines:
        with open(output_file, "w", encoding="utf-8") as out_f:
            for idx, line in enumerate(valid_lines):
                line = line.replace(",", "")
                if idx < len(valid_lines) - 1:
                    out_f.write(line + ",\n")
                else:
                    out_f.write(line + "\n")

    print(f"Processed {len(valid_lines)} lines and saved to {output_file}")


if __name__ == "__main__":
    main()
