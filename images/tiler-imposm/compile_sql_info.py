#!/usr/bin/env python3
"""Script to compile  information  from SQL fileand upload to S3 for tiler-imposm"""

import json
import os
import re
import subprocess
from pathlib import Path


def parse_doc_block(content):
    pattern = r'/\*\*(.*?)\*\*/'
    matches = re.findall(pattern, content, re.DOTALL)
    results = []
    
    for match in matches:
        doc_block = match.strip()
        if not doc_block:
            continue
        
        layer_info = {'layers': [], 'tegola_config': None, 'filters_per_zoom_level': [], 'description': None, 'details': []}
        lines = doc_block.split('\n')
        current_section = None
        
        for line in lines:
            line = line.strip()
            if not line:
                continue
            
            if line.startswith('layers:'):
                layers_str = line.split(':', 1)[1].strip()
                layer_info['layers'] = [l.strip() for l in layers_str.split(',')]
                current_section = None
            elif line.startswith('tegola_config:'):
                layer_info['tegola_config'] = line.split(':', 1)[1].strip()
                current_section = None
            elif line.startswith('filters_per_zoom_level:'):
                current_section = 'filters'
            elif line.startswith('## description:'):
                # Description está en la siguiente línea
                current_section = 'description'
            elif line.startswith('## details:'):
                current_section = 'details'
            elif line.startswith('- '):
                item = line[2:].strip()
                if current_section == 'filters':
                    filter_info = parse_zoom_filter(item)
                    if filter_info:
                        layer_info['filters_per_zoom_level'].append(filter_info)
                elif current_section == 'details':
                    layer_info['details'].append(item)
            elif current_section == 'description':
                # Description en la siguiente línea después de ## description:
                layer_info['description'] = line
                current_section = None
        
        if layer_info['layers'] or layer_info['tegola_config']:
            results.append(layer_info)
    
    return results


def parse_zoom_filter(filter_line):
    parts = filter_line.split('|')
    if not parts or ':' not in parts[0]:
        return None
    
    zoom_part, view_name = parts[0].strip().split(':', 1)
    filter_info = {'zoom_level': zoom_part.strip(), 'view_name': view_name.strip(),
                   'tolerance': None, 'min_area': None, 'filter': None, 'source': None}
    
    for part in parts[1:]:
        part = part.strip()
        if '=' in part:
            key, value = part.split('=', 1)
            key = key.strip()
            value = value.strip()
            if key in filter_info:
                filter_info[key] = value
    
    return filter_info


def process_sql_file(file_path):
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
        layer_infos = parse_doc_block(content)
        for layer_info in layer_infos:
            layer_info['source_file'] = str(file_path)
            layer_info['source_file_name'] = file_path.name
        return layer_infos
    except Exception as e:
        print(f"Error procesando {file_path}: {e}")
        return []


def upload_to_s3(file_path, bucket, filename):
    """Sube el archivo JSON a S3 usando awscli"""
    if not bucket or not os.path.exists(file_path):
        return False
    
    s3_path = f"{bucket.rstrip('/')}/{filename}"
    env = os.environ.copy()
    if os.getenv('AWS_ACCESS_KEY_ID'):
        env['AWS_ACCESS_KEY_ID'] = os.getenv('AWS_ACCESS_KEY_ID')
    if os.getenv('AWS_SECRET_ACCESS_KEY'):
        env['AWS_SECRET_ACCESS_KEY'] = os.getenv('AWS_SECRET_ACCESS_KEY')
    
    try:
        subprocess.run(['aws', 's3', 'cp', file_path, s3_path], check=True, env=env)
        print(f"✓ Archivo subido a S3: {s3_path}")
        return True
    except Exception as e:
        print(f"Error subiendo a S3: {e}")
        return False


def main():
    filename = 'vtiles_layers_info.json'
    queries_dir = Path('./queries')
    output_file = Path(f'./{filename}')
    
    if not queries_dir.exists():
        print(f"Error: El directorio {queries_dir} no existe")
        return 1
    
    all_layers = []
    for root, dirs, files in os.walk(queries_dir):
        for file in files:
            if file.endswith('.sql'):
                sql_file = Path(root) / file
                all_layers.extend(process_sql_file(sql_file))
    
    organized_data = {
        'layers': all_layers,
        'by_layer_name': {}
    }
    
    for layer_info in all_layers:
        for layer_name in layer_info['layers']:
            if layer_name not in organized_data['by_layer_name']:
                organized_data['by_layer_name'][layer_name] = []
            organized_data['by_layer_name'][layer_name].append(layer_info)
    
    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(organized_data, f, indent=2, ensure_ascii=False)
    
    bucket = os.getenv('AWS_S3_BUCKET')
    if bucket:
        upload_to_s3(output_file, bucket, filename)
    
    return 0


if __name__ == "__main__":
    exit(main())
