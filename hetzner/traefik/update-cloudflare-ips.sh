#!/bin/bash
set -e

# Script para actualizar IPs de Cloudflare automáticamente
# Descarga las IPs oficiales y regenera la configuración de Traefik

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CF_IPS_FILE="$SCRIPT_DIR/cloudflare-ips.txt"
TEMPLATE_FILE="$SCRIPT_DIR/traefik.template.yml"
OUTPUT_FILE="$SCRIPT_DIR/traefik.yml"

echo "🔄 Descargando IPs de Cloudflare..."

# Descargar IPs IPv4 e IPv6 de Cloudflare
IPV4_IPS=$(curl -s https://www.cloudflare.com/ips-v4)
IPV6_IPS=$(curl -s https://www.cloudflare.com/ips-v6)

if [ -z "$IPV4_IPS" ] || [ -z "$IPV6_IPS" ]; then
    echo "❌ Error: No se pudieron descargar las IPs de Cloudflare"
    exit 1
fi

# Guardar IPs en archivo temporal
{
    echo "# Cloudflare IPs - Actualizado $(date +%Y-%m-%d)"
    echo "# IPv4"
    echo "$IPV4_IPS"
    echo "# IPv6"
    echo "$IPV6_IPS"
} > "$CF_IPS_FILE"

echo "✅ IPs descargadas y guardadas en $CF_IPS_FILE"

# Generar el bloque de IPs en formato YAML
generate_ips_yaml() {
    echo "        # Redes privadas (Docker, red local)"
    echo "        - \"172.16.0.0/12\""
    echo "        - \"192.168.0.0/16\""
    echo "        - \"10.0.0.0/8\""
    echo "        # Cloudflare IPs - Actualizado $(date +%Y-%m-%d)"

    # IPv4
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        [[ "$ip" =~ ^#.* ]] && continue
        echo "        - \"$ip\""
    done <<< "$IPV4_IPS"

    echo "        # Cloudflare IPv6"
    # IPv6
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        [[ "$ip" =~ ^#.* ]] && continue
        echo "        - \"$ip\""
    done <<< "$IPV6_IPS"
}

# Leer el template y reemplazar las IPs
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "❌ Error: No se encontró el archivo template en $TEMPLATE_FILE"
    exit 1
fi

echo "🔧 Generando configuración desde template..."

# Crear el archivo de salida con las IPs actualizadas
{
    # Leer línea por línea hasta encontrar la sección de trustedIPs
    IN_TRUSTED_IPS=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*trustedIPs:[[:space:]]*$ ]]; then
            echo "$line"
            IN_TRUSTED_IPS=true
            # Saltar hasta el final de la lista de IPs existente
            while IFS= read -r line; do
                if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+ ]] || [[ "$line" =~ ^[[:space:]]*#.* ]]; then
                    continue
                else
                    # Insertar las nuevas IPs
                    generate_ips_yaml
                    echo "$line"
                    break
                fi
            done
        elif [ "$IN_TRUSTED_IPS" = false ]; then
            echo "$line"
        else
            IN_TRUSTED_IPS=false
            echo "$line"
        fi
    done < "$TEMPLATE_FILE"
} > "$OUTPUT_FILE.tmp"

# Reemplazar variables de entorno si existen
if [ -f "$SCRIPT_DIR/../.env" ]; then
    source "$SCRIPT_DIR/../.env"
fi

# Reemplazar {{OHM_DOMAIN}} si está definido
if [ -n "$OHM_DOMAIN" ]; then
    sed "s/{{OHM_DOMAIN}}/$OHM_DOMAIN/g" "$OUTPUT_FILE.tmp" > "$OUTPUT_FILE"
    rm "$OUTPUT_FILE.tmp"
else
    mv "$OUTPUT_FILE.tmp" "$OUTPUT_FILE"
fi

echo "✅ Configuración generada en $OUTPUT_FILE"

# Verificar si Traefik está corriendo y reiniciar si es necesario
if docker ps --format '{{.Names}}' | grep -q '^traefik$'; then
    echo "🔄 Reiniciando Traefik para aplicar cambios..."
    docker restart traefik
    echo "✅ Traefik reiniciado"
else
    echo "ℹ️  Traefik no está corriendo. Inicia los servicios para aplicar cambios."
fi

echo "🎉 ¡Actualización completada!"
