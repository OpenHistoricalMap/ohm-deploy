import json
import os
import shutil

SERVER_URL = os.getenv("SERVER_URL", "www.openhistoricalmap.org")
environment = "staging" if "staging" in SERVER_URL else "production"
files = {
    "ohmVectorStyles.Original = ": {
        "map-styles": "map-styles/main/main.json",
        "ohm-website": "app/assets/javascripts/ohm.style.original.js",
        "spritesheet_dir": "map-styles/main",
    },
    "ohmVectorStyles.Railway = ": {
        "map-styles": "map-styles/rail/rail.json",
        "ohm-website": "app/assets/javascripts/ohm.style.railway.js",
        "spritesheet_dir": "map-styles/rail",
    },
    "ohmVectorStyles.Woodblock = ": {
        "map-styles": "map-styles/woodblock/woodblock.json",
        "ohm-website": "app/assets/javascripts/ohm.style.woodblock.js",
        "spritesheet_dir": "map-styles/woodblock",
    },
    "ohmVectorStyles.JapaneseScroll = ": {
        "map-styles": "map-styles/japanese_scroll/ohm-japanese-scroll-map.json",
        "ohm-website": "app/assets/javascripts/ohm.style.japanese.js",
        "spritesheet_dir": "map-styles/japanese_scroll",
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


# Copy directory to public/styles/
def copy_directory(src_dir, dest_dir):
    try:
        if os.path.exists(dest_dir):
            shutil.rmtree(dest_dir)
        shutil.copytree(src_dir, dest_dir)
    except Exception as e:
        print(f"Error copying directory {src_dir} to {dest_dir}: {e}")


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
                        "openhistoricalmap.github.io/map-styles/ohm_timeslider_tegola/ohm_spritezero_spritesheet",
                        "openhistoricalmap.github.io/map-styles/ohm_timeslider_tegola/ohm_spritezero_spritesheet-production",
                    )
                    .replace(
                        "openhistoricalmap.github.io/map-styles",
                        "www.openhistoricalmap.org/styles",
                    )
                )
            else:
                json_str = json_str.replace(
                    "openhistoricalmap.github.io/map-styles",
                    "staging.openhistoricalmap.org/styles",
                )

            json_data = json.loads(json_str)

            ohm_website_path = value["ohm-website"]
            # Overwrite style file
            write_json_file(ohm_website_path, key, json_data)
            
            # Copy spritesheet to public dir
            spritesheet_src_dir = value["spritesheet_dir"]
            spritesheet_dest_dir = os.path.join(
                "public", "styles", os.path.basename(spritesheet_src_dir)
            )
            copy_directory(spritesheet_src_dir, spritesheet_dest_dir)
            print(f"Updated map-style: {ohm_website_path}")
