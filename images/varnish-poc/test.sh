#!/usr/bin/env bash
set -euo pipefail

VARNISH="${VARNISH:-http://localhost:6081}"
TILE="${TILE:-/maps/ohm/10/512/340.pbf}"

hr() { printf '%*s\n' 60 '' | tr ' ' '='; }
req_headers() { curl -sI "$1" | grep -iE "^(HTTP|x-cache|x-cache-hits|content-type|content-length)" || true; }

hr
echo "1. Primera request (esperado: MISS)"
hr
req_headers "$VARNISH$TILE"

hr
echo "2. Segunda request (esperado: HIT)"
hr
req_headers "$VARNISH$TILE"

hr
echo "3. fresh_tiles=1 (esperado: MISS, y cachea la respuesta fresh)"
hr
req_headers "$VARNISH$TILE?fresh_tiles=1"

hr
echo "4. Request normal post-fresh (esperado: HIT con la versión fresh)"
hr
req_headers "$VARNISH$TILE"

hr
echo "5. Benchmark de latencia (10 requests en HIT)"
hr
for i in $(seq 1 10); do
  curl -s -o /dev/null -w "  req $i: %{time_total}s\n" "$VARNISH$TILE"
done

hr
echo "6. BAN del tile específico"
hr
curl -sI -X BAN "$VARNISH/" \
  -H "X-Ban-Regex: ^/maps/ohm/10/512/340\\.pbf$" | head -3

hr
echo "7. Request post-BAN (esperado: MISS)"
hr
req_headers "$VARNISH$TILE"

hr
echo "8. BAN con regex: invalidar todos los z=10 x=512"
hr
curl -sI -X BAN "$VARNISH/" \
  -H "X-Ban-Regex: ^/maps/ohm/10/512/.*\\.pbf$" | head -3

hr
echo "9. Stats del cache"
hr
docker exec varnish-poc varnishstat -1 -f MAIN.cache_hit,MAIN.cache_miss,MAIN.n_object,MAIN.bans,MAIN.n_lru_moved 2>/dev/null || \
  echo "(no se pudo ejecutar varnishstat; el contenedor 'varnish-poc' debe estar corriendo)"

hr
echo "10. Tamaño del storage en disco"
hr
docker exec varnish-poc du -h /var/lib/varnish/storage.bin 2>/dev/null || true

echo
echo "✓ Test completado"
