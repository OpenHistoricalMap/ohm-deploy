"""
This script processes a SQL template file (`languages.template.sql`) to filter out specific lines 
based on the popularity of language tags using the OpenHistoricalMap TagInfo API.
"""
import re
import requests

def main():
    input_file = "config/languages.template.sql"
    output_file = "config/languages.sql"
    out_f = open(output_file, "w", encoding="utf-8")
    
    with open(input_file, "r", encoding="utf-8") as f:
        for line in f:
            # tags -> 'name:aaq' AS name_aaq,
            match = re.search(r"tags\s*->\s*'name:([^']+)'\s*AS\s*name_[^,]+,", line.strip())
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
                    print("Adding.."+ line, end="")
                    out_f.write(line)
            except requests.exceptions.RequestException as e:
                print(f"Request failed for language '{lang_code}': {e}")
    out_f.close()

if __name__ == "__main__":
    main()