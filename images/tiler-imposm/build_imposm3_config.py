import json
import os

def load_json(file_path):
    """Load a JSON file."""
    with open(file_path, 'r', encoding='utf-8') as file:
        return json.load(file)

def merge_configs(template, configs):
    """Merge multiple JSON configs into the template."""
    merged = template.copy()
    
    for config in configs:
        if 'generalized_tables' in config:
            merged['generalized_tables'].update(config['generalized_tables'])
    
    for config in configs:
        if 'tables' in config:
            merged['tables'].update(config['tables'])
    
    return merged

def main(folder_path, template_path, output_path):
    """Main function to merge JSON configs."""
    template = load_json(template_path)
    
    import_layers = os.getenv("IMPOSM3_IMPORT_LAYERS", "all").strip()
    
    configs = []
    if  "all" in import_layers:
        print("Importing all layer files.")
        # Import all JSON files in the folder
        json_files = [f for f in os.listdir(folder_path) if f.endswith('.json')]
        for json_file in json_files:
            file_path = os.path.join(folder_path, json_file)
            try:
                print(f"Importing {file_path}")
                configs.append(load_json(file_path))
            except json.JSONDecodeError as e:
                print(f"Error reading {file_path}: {e}")
    else:
        # Import only specified layers
        layer_names = [layer.strip() for layer in import_layers.split(",") if layer.strip()]
        if not layer_names:
            print("No layers specified in IMPOSM3_IMPORT_LAYERS. Exiting.")
            return
        
        for layer_name in layer_names:
            file_path = os.path.join(folder_path, f"{layer_name}.json")
            if os.path.exists(file_path):
                try:
                    print(f"Importing {file_path}")
                    configs.append(load_json(file_path))
                except json.JSONDecodeError as e:
                    print(f"Error reading {file_path}: {e}")
            else:
                print(f"Layer config file {file_path} not found. Skipping.")

    if not configs:
        print("No valid layer configurations found. Exiting.")
        return
    
    merged_config = merge_configs(template, configs)
    with open(output_path, 'w', encoding='utf-8') as output_file:
        json.dump(merged_config, output_file, indent=2)
    
    print(f"Merged configuration saved to {output_path}")

if __name__ == "__main__":
    folder_path = "./config/layers"
    template_path = "./config/imposm3.template.json"
    output_path = "./config/imposm3.json"
    main(folder_path, template_path, output_path)
