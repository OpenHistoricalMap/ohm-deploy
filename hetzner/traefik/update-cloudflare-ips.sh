#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CF_IPS_FILE="$SCRIPT_DIR/cloudflare-ips.txt"
TEMPLATE_FILE="$SCRIPT_DIR/traefik.template.yml"
OUTPUT_FILE="$SCRIPT_DIR/traefik.yml"

echo "🔄 Descargando IPs de Cloudflare..."
IPV4_IPS=$(curl -s https://www.cloudflare.com/ips-v4)
IPV6_IPS=$(curl -s https://www.cloudflare.com/ips-v6)
[ -z "$IPV4_IPS" ] || [ -z "$IPV6_IPS" ] && { echo "❌ No se pudieron descargar las IPs"; exit 1; }

{
  echo "# Cloudflare IPs - Actualizado $(date +%Y-%m-%d)"
  echo "$IPV4_IPS"
  echo "$IPV6_IPS"
} > "$CF_IPS_FILE"
echo "✅ IPs guardadas en $CF_IPS_FILE"

[ ! -f "$TEMPLATE_FILE" ] && { echo "❌ No se encontró $TEMPLATE_FILE"; exit 1; }

# Generar bloque YAML de IPs
gen_ips() {
  echo "        - \"172.16.0.0/12\""
  echo "        - \"192.168.0.0/16\""
  echo "        - \"10.0.0.0/8\""
  echo "$IPV4_IPS" | sed 's/^/        - "/;s/$/"/'
  echo "$IPV6_IPS" | sed 's/^/        - "/;s/$/"/'
}

# Reemplazar bloque trustedIPs en el template
awk '
  NR==FNR { block = block $0 "\n"; next }
  /^[[:space:]]*trustedIPs:[[:space:]]*$/ {
    print; printf "%s", block
    while ((getline line) > 0) {
      if (line !~ /^[[:space:]]+(-|#)/) { print line; break }
    }
    next
  }
  { print }
' <(gen_ips) "$TEMPLATE_FILE" > "$OUTPUT_FILE.tmp"

# Sustituir dominio si existe .env
[ -f "$SCRIPT_DIR/../.env" ] && source "$SCRIPT_DIR/../.env"
[ -n "$OHM_DOMAIN" ] && sed "s/{{OHM_DOMAIN}}/$OHM_DOMAIN/g" "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE" || mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
[ -f "$OUTPUT_FILE.tmp" ] && rm -f "$OUTPUT_FILE.tmp"

echo "✅ Configuración en $OUTPUT_FILE"
echo "🎉 ¡Listo!"
