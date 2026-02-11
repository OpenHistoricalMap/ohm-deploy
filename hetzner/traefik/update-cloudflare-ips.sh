#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CF_IPS_FILE="$SCRIPT_DIR/cloudflare-ips.txt"
TEMPLATE_FILE="$SCRIPT_DIR/traefik.template.yml"
OUTPUT_FILE="$SCRIPT_DIR/traefik.yml"

# Download Cloudflare IPs
echo "Downloading Cloudflare IPs..."
IPV4_IPS=$(curl -s https://www.cloudflare.com/ips-v4)
IPV6_IPS=$(curl -s https://www.cloudflare.com/ips-v6)

# Save IPs to file
{
  echo "# Cloudflare IPs - Updated $(date +%Y-%m-%d)"
  echo "$IPV4_IPS"
  echo "$IPV6_IPS"
} > "$CF_IPS_FILE"

# Generate YAML block with IPs
gen_ips() {
  echo "        - \"172.16.0.0/12\""
  echo "        - \"192.168.0.0/16\""
  echo "        - \"10.0.0.0/8\""
  echo "$IPV4_IPS" | sed 's/^/        - "/;s/$/"/'
  echo "$IPV6_IPS" | sed 's/^/        - "/;s/$/"/'
}

# Replace trustedIPs block in template
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

# Load .env and substitute domain
source "$SCRIPT_DIR/../.env"
sed "s/{{OHM_DOMAIN}}/$OHM_DOMAIN/g" "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
rm -f "$OUTPUT_FILE.tmp"

echo "Configuration generated at $OUTPUT_FILE"
