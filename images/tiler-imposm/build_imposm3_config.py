import json
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

def load_json(file_path):
    """Load a JSON file."""
    try:
        with open(file_path, 'r', encoding='utf-8') as file:
            return json.load(file)
    except FileNotFoundError:
        logger.error(f"File not found: {file_path}")
        raise
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing JSON in file {file_path}: {e}")
        raise

def merge_configs(template, configs):
    """Merge multiple JSON configs into the template."""
    merged = template.copy()
    for config in configs:
        if 'generalized_tables' in config:
            merged['generalized_tables'].update(config['generalized_tables'])
        if 'tables' in config:
            merged['tables'].update(config['tables'])
    return merged

def main(folder_path, template_path, output_path):
    """Main function to merge JSON configs."""
    logger.info("Loading template configuration...")
    template = load_json(template_path)

    import_layers = os.getenv("IMPOSM3_IMPORT_LAYERS", "all").strip()
    logger.info(f"IMPOSM3_IMPORT_LAYERS: {import_layers}")

    configs = []
    if "all" in import_layers:
        logger.info("Importing all layer files.")
        # Import all JSON files in the folder
        json_files = [f for f in os.listdir(folder_path) if f.endswith('.json')]
        for json_file in json_files:
            file_path = os.path.join(folder_path, json_file)
            try:
                logger.info(f"Importing {file_path}")
                configs.append(load_json(file_path))
            except Exception as e:
                logger.error(f"Error reading {file_path}: {e}")
    else:
        # Import only specified layers
        layer_names = [layer.strip() for layer in import_layers.split(",") if layer.strip()]
        if not layer_names:
            logger.error("No layers specified in IMPOSM3_IMPORT_LAYERS. Exiting.")
            return

        for layer_name in layer_names:
            file_path = os.path.join(folder_path, f"{layer_name}.json")
            if os.path.exists(file_path):
                try:
                    logger.info(f"Importing {file_path}")
                    configs.append(load_json(file_path))
                except Exception as e:
                    logger.error(f"Error reading {file_path}: {e}")
            else:
                logger.warning(f"Layer config file {file_path} not found. Skipping.")

    if not configs:
        logger.error("No valid layer configurations found. Exiting.")
        return

    logger.info("Merging configurations...")
    merged_config = merge_configs(template, configs)
    try:
        with open(output_path, 'w', encoding='utf-8') as output_file:
            json.dump(merged_config, output_file, indent=2)
        logger.info(f"Merged configuration saved to {output_path}")
    except Exception as e:
        logger.error(f"Error writing merged configuration to {output_path}: {e}")
        raise

if __name__ == "__main__":
    folder_path = "./config/layers"
    template_path = "./config/imposm3.template.json"
    output_path = "./config/imposm3.json"
    main(folder_path, template_path, output_path)
    