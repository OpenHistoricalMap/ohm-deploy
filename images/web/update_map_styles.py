import json
import os
import shutil
import re

SERVER_URL = os.getenv('SERVER_URL', 'www.openhistoricalmap.org')
environment = 'staging' if 'staging' in SERVER_URL else 'production'
file_path = os.path.join($workdir, 'node_modules', '@openhistoricalmap', 'map-styles', 'dist', 'ohm.styles.js')

try:
    with open(file_path, 'r+') as file:
        styles_js = file.read()
        # regex removes the opening comment & 'ohmVectorStyles = ' in order to JSONify the styles object
        styles_py = json.loads(re.sub(r'\A.* = {', '{', styles_js, count=1, flags=re.DOTALL))
        # If this is a deploy to staging, set the tile, sprite, & glyph domains accordingly
        # Assumption: the npm module, map-styles, is delivered with production values
        if environment == 'staging':
            for style in styles_py:
                for source in styles_py[style]['sources']:
                    styles_py[style]['sources'][source]['tiles'][0] = styles_py[style]['sources'][source]['tiles'][0].replace('vtiles.openhistoricalmap.org', 'vtiles.staging.openhistoricalmap.org')
                for asset in ['glyphs', 'sprite']:
                    styles_py[style][asset] = styles_py[style][asset].replace('www.openhistoricalmap.org', 'www.staging.openhistoricalmap.org')
                    styles_py[style][asset] = styles_py[style][asset].replace('openhistoricalmap.github.io', 'www.staging.openhistoricalmap.org')

        # Rewind and restore the style file used by the Rails app
        file.seek(0)
        file.write('/* extends ohmVectorStyles defined in ohm.style.js */\n\nohmVectorStyles = ')
        file.write(json.dumps(styles_py, indent=2))
        file.truncate()

        # Write the separately-hosted styles
        for style in styles_py:
            style_snake_case = re.sub(r'(?<!^)(?=[A-Z])', '_', style).lower()
            file_path = os.path.join(os.sep, 'var', 'www', 'public', 'map-styles', style_snake_case, style_snake_case+'.json')
            with open(file_path, 'w') as file:
                file.write(json.dumps(styles_py[style], indent=2))

except Exception as e:
    print(f"Error: {e}")
