import json
import os
import shutil

SERVER_URL = os.getenv("SERVER_URL", "www.openhistoricalmap.org")
environment = "staging" if "staging" in SERVER_URL else "production"
files = {
    "ohmVectorStyles.Original = ": {
        "map-styles": "/var/www/public/map-styles/main/main.json",
        "ohm-website": "/var/www/app/assets/javascripts/ohm.style.original.js",
    },
    "ohmVectorStyles.Railway = ": {
        "map-styles": "/var/www/public/map-styles/rail/rail.json",
        "ohm-website": "/var/www/app/assets/javascripts/ohm.style.railway.js",
    },
    "ohmVectorStyles.Woodblock = ": {
        "map-styles": "/var/www/public/map-styles/woodblock/woodblock.json",
        "ohm-website": "/var/www/app/assets/javascripts/ohm.style.woodblock.js",
    },
    "ohmVectorStyles.JapaneseScroll = ": {
        "map-styles": "/var/www/public/map-styles/japanese_scroll/ohm-japanese-scroll-map.json",
        "ohm-website": "/var/www/app/assets/javascripts/ohm.style.japanese.js",
    },
}

# Read json data from map-styles
def read_json_file(file_path):
    try:
        with open(file_path, "r") as file:
            return json.load(file)
    except Exception as e:
        print(f"Error reading {file_path}: {e}")
        return None


# Write json data to ohm-website
def write_json_file(js_file_path, key, json_data):
    try:
        with open(js_file_path, "w") as file:
            file.write(f"{key}{json.dumps(json_data, indent=4)};")
    except Exception as e:
        print(f"Error updating {js_file_path}: {e}")


# Loop through files
for key, value in files.items():
    if "map-styles" in value:
        file_path = value["map-styles"]
        json_data = read_json_file(file_path)

        if json_data:
            json_str = json.dumps(json_data, indent=4)
            # Replace in case of production
            if environment == "production":
                json_str = (
                    json_str.replace(
                        "vtiles.staging.openhistoricalmap.org",
                        "vtiles.openhistoricalmap.org",
                    )
                    .replace(
                        "openhistoricalmap.github.io",
                        "www.openhistoricalmap.org",
                    )
                )
            else:
                json_str = json_str.replace(
                    "openhistoricalmap.github.io",
                    "staging.openhistoricalmap.org",
                )

            json_data = json.loads(json_str)

            ohm_website_path = value["ohm-website"]
            # Overwrite style file
            write_json_file(ohm_website_path, key, json_data)
            print(f"Updated map-style: {ohm_website_path}")
