vcl 4.1;

backend martin {
    .host = "martin";
    .port = "3001";
    .connect_timeout = 10s;
    .first_byte_timeout = 120s;
    .between_bytes_timeout = 30s;
}

acl purgers {
    "localhost";
    "127.0.0.1";
    "172.16.0.0/12";
    "10.0.0.0/8";
    "192.168.0.0/16";
}

sub vcl_recv {
    if (req.method == "BAN") {
        if (!client.ip ~ purgers) {
            return (synth(403, "Forbidden"));
        }
        if (!req.http.X-Ban-Regex) {
            return (synth(400, "Missing X-Ban-Regex header"));
        }
        ban("req.url ~ " + req.http.X-Ban-Regex);
        return (synth(200, "Banned: " + req.http.X-Ban-Regex));
    }

    # fresh_tiles=1: fuerza MISS pero SÍ cachea la respuesta fresh
    # (reemplaza la entrada vieja, mismo comportamiento que nginx hoy)
    if (req.url ~ "[?&]fresh_tiles=1") {
        set req.hash_always_miss = true;
        # Stripear el param para que comparta cache con la URL sin query
        set req.url = regsub(req.url, "[?&]fresh_tiles=1", "");
    }

    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    unset req.http.Cookie;
    unset req.http.Authorization;
}

sub vcl_backend_response {
    # TTL largo como safety net (7d); BAN invalida antes si hay edits
    set beresp.ttl = 7d;
    set beresp.grace = 1h;
    set beresp.keep = 1d;

    unset beresp.http.Set-Cookie;

    # No cachear errores de backend
    if (beresp.status >= 500) {
        set beresp.uncacheable = true;
        set beresp.ttl = 0s;
    }
}

sub vcl_deliver {
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
}
