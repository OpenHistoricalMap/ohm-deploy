import os
import re
import argparse

# Argument parser setup
parser = argparse.ArgumentParser(description='Merge TOML files into a configuration file.')
parser.add_argument('--template', default='config/config.template.toml', help='Path to the configuration template file.')
parser.add_argument('--providers', default='config/providers', help='Directory containing provider TOML files.')
parser.add_argument('--languages', default='config/languages.sql', help='Path to the languages SQL file.')
parser.add_argument('--output', default='config/config.toml', help='Output configuration file path.')
args = parser.parse_args()

config_template_file = args.template
providers_dir = args.providers
languages_file = args.languages
output_file_path = args.output

def remove_comments_from_languages_content(content):
    # Remove comments (lines starting with '--')
    return '\n'.join(line for line in content.split('\n') if not line.strip().startswith('--'))

# Read the content of languages.sql and remove comments
with open(languages_file, "r") as file:
    languages_content = file.read().strip()
    languages_content = remove_comments_from_languages_content(languages_content)

toml_files = [file for file in os.listdir(providers_dir) if file.endswith(".toml")]

# Read TOML files
new_configs = {}
for toml_file in toml_files:
    dir_toml_file = os.path.join(providers_dir, toml_file)
    with open(dir_toml_file, "r") as file:
        provider_toml_content = file.read()
        
        if '{{LENGUAGES}}' in provider_toml_content:
            languages_content_fixed = languages_content.replace("\n", " ")
            provider_toml_content = provider_toml_content.replace('{{LENGUAGES}}', languages_content_fixed)

        if '{{LENGUAGES_RELATION}}' in provider_toml_content:
            languages_content_fixed = languages_content.replace("\n", " r.")
            languages_content_fixed = f"r.{languages_content_fixed}"
            provider_toml_content = provider_toml_content.replace('{{LENGUAGES_RELATION}}', languages_content_fixed)

        new_configs[dir_toml_file] = provider_toml_content

with open(config_template_file, "r") as main_file:
    content = main_file.read()

# Replace the content of main.toml with the content read from other TOML files
for toml_file, toml_file_content in new_configs.items():
    print(f"Copy {toml_file} to config.toml")
    section_header = "[['{}']]".format(toml_file.replace("config/", ""))
    indentation_level = content.find(section_header)
    if indentation_level != -1:
        # Find the appropriate number of tabs or spaces for indentation
        preceding_newline = content.rfind('\n', 0, indentation_level)
        indentation = content[preceding_newline + 1:indentation_level]
        toml_file_content = f"###### From {toml_file} \n" + toml_file_content
        new_values = toml_file_content.replace("\n", "\n" + indentation)
        content = content.replace(section_header, new_values)

with open(output_file_path, "w") as output_file:
    output_file.write(content)