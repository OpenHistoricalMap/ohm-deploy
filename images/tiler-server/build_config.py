import os
import argparse

def remove_comments_from_languages_content(content: str) -> str:
    """
    Remove comment lines (those that start with '--') from the languages SQL content.
    """
    lines = content.split('\n')
    filtered_lines = [line for line in lines if not line.strip().startswith('--')]
    return '\n'.join(filtered_lines)

def indent_block(block: str, indent: str = "\t") -> str:
    """
    Indent every line of `block` with the given `indent` string.
    """
    lines = block.splitlines()
    return "\n".join(indent + line for line in lines)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Merge TOML files into a configuration file.')
    parser.add_argument('--template', default='config/config.template.toml',
                        help='Path to the configuration template file.')
    parser.add_argument('--providers', default='config/providers',
                        help='Directory containing provider TOML files.')
    parser.add_argument('--languages', default='config/languages.sql',
                        help='Path to the languages SQL file.')
    parser.add_argument('--output', default='config/config.osm.toml',
                        help='Output configuration file path.')
    # We have removed the "all" option and accept only a comma-separated list.
    parser.add_argument('--provider_names', required=True,
                        help='Comma-separated list of provider names (without the .toml extension).')

    args = parser.parse_args()

    template_file = args.template
    providers_dir = args.providers
    languages_file = args.languages
    output_file = args.output

    # Read the main template file
    with open(template_file, 'r') as f:
        template_content = f.read()

    # Read and clean up the languages.sql file (removing '--' comments)
    with open(languages_file, 'r') as f:
        languages_content = remove_comments_from_languages_content(f.read().strip())

    # Gather all TOML files in the providers directory
    all_toml_files = [f for f in os.listdir(providers_dir) if f.endswith('.toml')]

    # Parse the requested provider names in the exact order the user specified
    requested_providers = [p.strip() for p in args.provider_names.split(',')]

    # Build a list of matching TOML files in the same order
    selected_toml_files = []
    for rp in requested_providers:
        expected_name = rp if rp.endswith('.toml') else rp + '.toml'
        if expected_name in all_toml_files:
            selected_toml_files.append(expected_name)
        else:
            print(f"WARNING: {expected_name} not found in {providers_dir}. Skipping.")

    # Accumulators for ALL provider blocks and ALL map blocks
    providers_accumulator = []
    maps_accumulator = []

    # Read each selected TOML file (in the specified order) and split out providers vs maps
    for toml_filename in selected_toml_files:
        full_path = os.path.join(providers_dir, toml_filename)
        print("Importing ->", full_path)
        with open(full_path, 'r') as f:
            raw_content = f.read()

        # Replace language placeholders, if any
        if '{{LENGUAGES}}' in raw_content:
            # Flatten languages so it's inline
            raw_content = raw_content.replace('{{LENGUAGES}}', languages_content.replace("\n", " "))
        if '{{LENGUAGES_RELATION}}' in raw_content:
            # We prefix each line of languages with "r."
            replaced_lines = "r." + languages_content.replace("\n", " r.")
            raw_content = raw_content.replace('{{LENGUAGES_RELATION}}', replaced_lines)

        # Split on '---' (if present) to separate provider vs maps content
        if '---' in raw_content:
            provider_part, maps_part = raw_content.split('---', 1)
        else:
            provider_part, maps_part = raw_content, ""

        # Strip extra whitespace
        provider_part = provider_part.strip()
        maps_part = maps_part.strip()

        # Collect them
        if provider_part:
            providers_accumulator.append(provider_part)
        if maps_part:
            maps_accumulator.append(maps_part)

    # Combine all providers and maps into single blocks
    all_providers_content = "\n\n".join(providers_accumulator)
    all_maps_content = "\n\n".join(maps_accumulator)

    # Insert them into the template, replacing the placeholders
    # We indent each line with a tab for readability
    template_content = template_content.replace(
        "###### PROVIDERS",
        "###### PROVIDERS\n" + indent_block(all_providers_content, "\t")
    )

    template_content = template_content.replace(
        "###### MAPS",
        "###### MAPS\n" + indent_block(all_maps_content, "\t")
    )

    # Write the merged result to the specified output file
    with open(output_file, 'w') as f:
        f.write(template_content)

    print(f"Successfully created merged configuration at: {output_file}")
    