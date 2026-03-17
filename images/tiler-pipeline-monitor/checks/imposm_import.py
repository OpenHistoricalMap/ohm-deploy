"""Pipeline check: changeset-centric verification.

For each changeset in the 1-2 hour window:
  1. Check if minute replication covers it (replication timestamp >= closed_at)
  2. Check if its way/relation elements exist in the tiler DB with the correct version
  3. For a random sample: verify materialized views + S3 tile cache
"""

import json
import os
import random
import xml.etree.ElementTree as ET
from datetime import datetime, timezone, timedelta

import psycopg2
import requests

from config import Config

# Load table/view mapping from JSON config
_config_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "tables_config.json")
with open(_config_path) as f:
    _tables_config = json.load(f)

OHM_BASE = None  # lazily computed


def _ohm_base():
    global OHM_BASE
    if OHM_BASE is None:
        OHM_BASE = Config.OHM_API_BASE.replace("/api/0.6", "")
    return OHM_BASE


def _parse_timestamp(ts_str):
    """Parse an ISO timestamp string to a timezone-aware datetime."""
    ts_str = ts_str.replace("Z", "+00:00")
    return datetime.fromisoformat(ts_str)


# ---------------------------------------------------------------------------
# Step 0: get changesets in the age window
# ---------------------------------------------------------------------------

def _get_changesets_in_window(min_age, max_age, limit=10):
    """Fetch closed changesets whose age is between min_age and max_age seconds.

    Fetches recent changesets and filters locally by age window.
    """
    now = datetime.now(timezone.utc)
    min_closed = now - timedelta(seconds=max_age)   # oldest allowed
    max_closed = now - timedelta(seconds=min_age)    # newest allowed

    # Fetch enough to find some in the window
    fetch_limit = 100
    url = f"{Config.OHM_API_BASE}/changesets"
    params = {"limit": fetch_limit, "closed": "true"}
    headers = {"User-Agent": "ohm-pipeline-monitor/1.0"}

    print(f"[pipeline] Fetching changesets: {url}?limit={fetch_limit}&closed=true")
    print(f"  Looking for changesets closed between "
          f"{min_closed.strftime('%Y-%m-%dT%H:%M:%SZ')} and "
          f"{max_closed.strftime('%Y-%m-%dT%H:%M:%SZ')} "
          f"(age {min_age//60}-{max_age//60} min)")

    resp = requests.get(url, params=params, headers=headers, timeout=30)
    resp.raise_for_status()

    root = ET.fromstring(resp.content)
    changesets = []
    skipped_young = 0
    skipped_old = 0

    for cs in root.findall("changeset"):
        cs_id = int(cs.attrib["id"])
        closed_at = cs.attrib.get("closed_at", "")
        if not closed_at:
            continue
        try:
            closed_dt = _parse_timestamp(closed_at)
        except (ValueError, TypeError):
            continue

        age_minutes = (now - closed_dt).total_seconds() / 60

        if closed_dt > max_closed:
            skipped_young += 1
            continue
        elif closed_dt < min_closed:
            skipped_old += 1
            # Changesets are ordered by newest first, so once we hit old ones, stop
            break
        else:
            changesets.append({
                "id": cs_id,
                "closed_at": closed_at,
                "closed_dt": closed_dt,
                "age_minutes": round(age_minutes, 1),
            })

        if len(changesets) >= limit:
            break

    print(f"  Fetched {len(root.findall('changeset'))} changesets from API")
    print(f"  Skipped: {skipped_young} too young (<{min_age//60}min), "
          f"{skipped_old} too old (>{max_age//60}min)")
    print(f"  Found {len(changesets)} changesets in window:")
    for cs in changesets:
        print(f"    changeset {cs['id']}: closed_at={cs['closed_at']} "
              f"(age={cs['age_minutes']}min)")

    return changesets


# ---------------------------------------------------------------------------
# Step 1: replication check
# ---------------------------------------------------------------------------

def _parse_replication_state(text):
    """Parse state.txt and return (sequence, timestamp)."""
    data = {}
    for line in text.strip().splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            data[key.strip()] = value.strip()
    seq = int(data.get("sequenceNumber", 0))
    ts_raw = data.get("timestamp", "").replace("\\:", ":")
    try:
        ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
    except ValueError:
        ts = None
    return seq, ts


def _check_replication_covers(changeset, repl_seq, repl_ts):
    """Check if the replication state covers this changeset."""
    if repl_ts is None:
        return {
            "status": "warning",
            "message": "Cannot parse replication timestamp",
        }

    closed_dt = changeset["closed_dt"]
    if repl_ts >= closed_dt:
        return {
            "status": "ok",
            "message": (f"Replication covers this changeset "
                        f"(repl_ts={repl_ts.isoformat()} >= closed_at={changeset['closed_at']})"),
            "replication_sequence": repl_seq,
            "replication_timestamp": repl_ts.isoformat(),
        }
    else:
        lag = (closed_dt - repl_ts).total_seconds()
        return {
            "status": "critical",
            "message": (f"Replication does NOT cover this changeset. "
                        f"Replication is {round(lag/60, 1)}min behind "
                        f"(repl_ts={repl_ts.isoformat()} < closed_at={changeset['closed_at']})"),
            "replication_sequence": repl_seq,
            "replication_timestamp": repl_ts.isoformat(),
        }


# ---------------------------------------------------------------------------
# Step 2: tiler DB check
# ---------------------------------------------------------------------------

def _get_changeset_elements(changeset_id):
    """Download changeset diff and extract way/relation elements with versions."""
    url = f"{Config.OHM_API_BASE}/changeset/{changeset_id}/download"
    headers = {"User-Agent": "ohm-pipeline-monitor/1.0"}
    resp = requests.get(url, headers=headers, timeout=30)
    resp.raise_for_status()

    root = ET.fromstring(resp.content)
    elements = []

    for action in root:  # create, modify, delete
        action_type = action.tag
        for elem in action:
            osm_id = elem.attrib.get("id")
            version = elem.attrib.get("version")
            elem_type = elem.tag
            if osm_id and elem_type in ("way", "relation"):
                # Extract tags to determine which imposm table this element belongs to
                tags = {}
                for tag in elem.findall("tag"):
                    k = tag.attrib.get("k")
                    v = tag.attrib.get("v")
                    if k and v:
                        tags[k] = v
                elements.append({
                    "type": elem_type,
                    "osm_id": int(osm_id),
                    "version": int(version) if version else None,
                    "action": action_type,
                    "tags": tags,
                })
    return elements



# Loaded from tables_config.json
RELATION_TABLES = _tables_config["relation_tables"]
WAY_TABLES = _tables_config["way_tables"]
TABLE_TO_VIEWS = _tables_config["table_to_views"]


def _build_union_query(tables, search_id):
    """Build a UNION ALL query to search osm_id across multiple tables in 1 round-trip."""
    parts = []
    for table in tables:
        parts.append(
            f"SELECT '{table}' AS tbl, tags->'version' AS version "
            f"FROM {table} WHERE osm_id = {int(search_id)} LIMIT 1"
        )
    return " UNION ALL ".join(parts)


def _check_element_in_tables(conn, elem):
    """Check if an element exists in tiler DB tables using a single UNION ALL query."""
    osm_id = elem["osm_id"]
    search_id = -osm_id if elem["type"] == "relation" else osm_id
    candidate_tables = RELATION_TABLES if elem["type"] == "relation" else WAY_TABLES

    cur = conn.cursor()

    # Get existing tables (cached per connection would be ideal, but simple first)
    cur.execute("""
        SELECT table_name FROM information_schema.tables
        WHERE table_schema = 'public' AND table_name LIKE 'osm_%%'
    """)
    existing_tables = {row[0] for row in cur.fetchall()}
    tables = [t for t in candidate_tables if t in existing_tables]

    if not tables:
        cur.close()
        return {
            "type": elem["type"],
            "osm_id": osm_id,
            "action": elem["action"],
            "expected_version": elem["version"],
            "found_in_tables": [],
            "found_in_views": [],
            "version_match": None,
            "url": f"{_ohm_base()}/{elem['type']}/{elem['osm_id']}",
        }

    # Single UNION ALL query across all candidate tables
    query = _build_union_query(tables, search_id)
    found_in_tables = []
    version_match = None

    try:
        cur.execute(query)
        for row in cur.fetchall():
            found_in_tables.append(row[0])
            db_version = row[1]
            if elem["version"] is not None and db_version is not None:
                try:
                    version_match = int(db_version) >= elem["version"]
                except (ValueError, TypeError):
                    version_match = None
    except Exception:
        conn.rollback()

    cur.close()

    return {
        "type": elem["type"],
        "osm_id": osm_id,
        "action": elem["action"],
        "expected_version": elem["version"],
        "found_in_tables": found_in_tables,
        "found_in_views": [],
        "version_match": version_match,
        "url": f"{_ohm_base()}/{elem['type']}/{elem['osm_id']}",
    }


def _check_element_in_views(conn, check):
    """Check if an element exists in materialized views using a single UNION ALL query."""
    osm_id = check["osm_id"]
    search_id = -osm_id if check["type"] == "relation" else osm_id

    # Collect all candidate views from the tables where the element was found
    found_tables = check["found_in_tables"]
    candidate_views = set()
    for table in found_tables:
        for v in TABLE_TO_VIEWS.get(table, []):
            candidate_views.add(v)

    if not candidate_views:
        return check

    cur = conn.cursor()

    # Filter to existing views
    cur.execute("""
        SELECT matviewname FROM pg_matviews
        WHERE schemaname = 'public' AND matviewname LIKE 'mv_%%'
    """)
    existing_views = {row[0] for row in cur.fetchall()}
    views = sorted(v for v in candidate_views if v in existing_views)

    if not views:
        cur.close()
        return check

    # Single UNION ALL query across all candidate views
    parts = []
    for view in views:
        parts.append(
            f"SELECT '{view}' AS vw FROM {view} "
            f"WHERE osm_id = {int(search_id)} LIMIT 1"
        )
    query = " UNION ALL ".join(parts)

    found_in_views = []
    try:
        cur.execute(query)
        for row in cur.fetchall():
            found_in_views.append(row[0])
    except Exception:
        conn.rollback()

    cur.close()
    check["found_in_views"] = found_in_views
    return check


def _is_element_deleted(elem):
    """Check if an element has been deleted in OHM (visible=false or 410 Gone)."""
    url = f"{Config.OHM_API_BASE}/{elem['type']}/{elem['osm_id']}"
    headers = {"User-Agent": "ohm-pipeline-monitor/1.0"}
    try:
        resp = requests.get(url, headers=headers, timeout=15)
        if resp.status_code == 410:
            return True
        if resp.status_code == 200:
            root = ET.fromstring(resp.content)
            el = root.find(elem["type"])
            if el is not None and el.attrib.get("visible") == "false":
                return True
        return False
    except Exception:
        return False


def _check_elements_in_db(conn, changeset_id, changeset_closed_at=None):
    """Check all elements of a changeset in the tiler DB.

    - ALL elements: verified in osm_* tables (fast, tag-filtered)
    - SAMPLE elements: full check → tables + views + S3 tile cache
    """
    from checks.tile_cache import check_tile_cache_for_element

    try:
        elements = _get_changeset_elements(changeset_id)
    except requests.RequestException as e:
        return {
            "status": "critical",
            "message": f"Failed to download changeset diff: {e}",
            "elements": [],
        }

    if not elements:
        return {
            "status": "ok",
            "message": "No way/relation elements in this changeset",
            "elements": [],
        }

    # Filter out deletes
    active_elements = []
    for elem in elements:
        if elem["action"] == "delete":
            print(f"    SKIP {elem['type']}/{elem['osm_id']} (action=delete)")
        else:
            active_elements.append(elem)

    if not active_elements:
        return {
            "status": "ok",
            "message": "All elements in this changeset are deletes",
            "elements": [],
        }

    # Select random sample for full pipeline check (tables + views + S3)
    sample_size = min(Config.FULL_CHECK_SAMPLE_SIZE, len(active_elements))
    sample_indices = set(random.sample(range(len(active_elements)), sample_size))

    print(f"  [tiler_db] Checking {len(active_elements)} elements "
          f"(full pipeline check on {sample_size} sampled)")

    missing = []
    mismatches = []
    checked = []
    tile_cache_results = []

    for idx, elem in enumerate(active_elements):
        is_sample = idx in sample_indices
        sample_label = " [SAMPLE]" if is_sample else ""

        # Step 1: Check tables — single UNION ALL query (ALL elements)
        check = _check_element_in_tables(conn, elem)

        # Step 2: Check views — single UNION ALL query (SAMPLE only)
        if is_sample and check["found_in_tables"]:
            check = _check_element_in_views(conn, check)

        checked.append(check)

        tables = check["found_in_tables"]
        views = check["found_in_views"]

        if tables:
            icon = "OK" if check["version_match"] is not False else "VERSION_MISMATCH"
            print(f"    {icon}{sample_label} {elem['type']}/{elem['osm_id']} v{elem['version']} "
                  f"({elem['action']}) version_match={check['version_match']}")
            print(f"         tables: {tables}")
            if views:
                print(f"         views:  {views}")
            print(f"         {check['url']}")

            # Step 3: Check S3 tile cache (SAMPLE only)
            if is_sample and changeset_closed_at and Config.S3_BUCKET_CACHE_TILER:
                try:
                    tile_result = check_tile_cache_for_element(
                        conn, check, changeset_closed_at
                    )
                    tile_cache_results.append(tile_result)
                    cache_status = tile_result.get("cache", {}).get("status", "unknown")
                    tile_info = tile_result.get("tile", {})
                    if cache_status == "stale":
                        print(f"         [S3 CACHE] STALE tile z{tile_info.get('z')}/{tile_info.get('x')}/{tile_info.get('y')}")
                    elif cache_status == "ok":
                        print(f"         [S3 CACHE] OK tile z{tile_info.get('z')}/{tile_info.get('x')}/{tile_info.get('y')}")
                    elif cache_status == "skipped":
                        print(f"         [S3 CACHE] skipped: {tile_result.get('cache', {}).get('message', '')}")
                except Exception as e:
                    print(f"         [S3 CACHE] error: {e}")
        else:
            # Not found — check if deleted in a later changeset
            if _is_element_deleted(elem):
                print(f"    SKIP {elem['type']}/{elem['osm_id']} v{elem['version']} "
                      f"({elem['action']}) -> deleted in a later changeset")
                print(f"         {check['url']}")
                check["deleted"] = True
                continue

            print(f"    MISSING{sample_label} {elem['type']}/{elem['osm_id']} v{elem['version']} "
                  f"({elem['action']}) -> NOT in tables")
            print(f"         {check['url']}")

        if not tables and not check.get("deleted"):
            missing.append(f"{elem['type']}/{elem['osm_id']}")
        elif check["version_match"] is False:
            mismatches.append(f"{elem['type']}/{elem['osm_id']} expected v{elem['version']}")

    # Build status message
    stale_tiles = [r for r in tile_cache_results if r.get("cache", {}).get("status") == "stale"]

    if missing:
        status = "warning"
        msg = f"Missing from tiler DB: {', '.join(missing)}"
        if mismatches:
            msg += f". Version mismatches: {', '.join(mismatches)}"
    elif mismatches:
        status = "warning"
        msg = f"Version mismatches: {', '.join(mismatches)}"
    elif stale_tiles:
        status = "warning"
        stale_ids = [f"{r['type']}/{r['osm_id']}" for r in stale_tiles]
        msg = (f"All {len(checked)} elements in tables, "
               f"but S3 tile cache stale for: {', '.join(stale_ids)}")
    else:
        status = "ok"
        msg = f"All {len(checked)} elements verified in tiler DB"
        if tile_cache_results:
            msg += f" (S3 cache OK for {len(tile_cache_results)} sampled)"

    return {
        "status": status,
        "message": msg,
        "elements": checked,
        "tile_cache": tile_cache_results,
    }


# ---------------------------------------------------------------------------
# Main pipeline check (scheduled)
# ---------------------------------------------------------------------------

def check_pipeline():
    """Check the full pipeline for changesets in the 1-2 hour age window.

    For each changeset:
      1. Is it covered by minute replication?
      2. Are its elements in the tiler DB?
    """
    now = datetime.now(timezone.utc)
    min_age = Config.CHANGESET_MIN_AGE
    max_age = Config.CHANGESET_MAX_AGE

    result = {
        "name": "pipeline",
        "status": "ok",
        "message": "",
        "details": {
            "window": f"{min_age//60}-{max_age//60} minutes",
            "replication": {},
            "changesets": [],
        },
        "checked_at": now.isoformat(),
    }

    # --- Fetch replication state ---
    repl_seq, repl_ts = None, None
    try:
        resp = requests.get(Config.REPLICATION_STATE_URL, timeout=15)
        resp.raise_for_status()
        repl_seq, repl_ts = _parse_replication_state(resp.text)
        result["details"]["replication"] = {
            "status": "ok",
            "sequence": repl_seq,
            "timestamp": repl_ts.isoformat() if repl_ts else None,
        }
        if repl_ts:
            lag_min = (now - repl_ts).total_seconds() / 60
            result["details"]["replication"]["lag_minutes"] = round(lag_min, 1)
            print(f"\n[pipeline] Replication state: seq={repl_seq}, "
                  f"ts={repl_ts.isoformat()}, lag={lag_min:.1f}min")
    except requests.RequestException as e:
        result["details"]["replication"] = {
            "status": "critical",
            "message": f"Failed to fetch replication state: {e}",
        }
        print(f"\n[pipeline] WARNING: Cannot fetch replication state: {e}")

    # --- Get changesets in window ---
    try:
        changesets = _get_changesets_in_window(
            min_age=min_age,
            max_age=max_age,
            limit=Config.CHANGESET_LIMIT,
        )
    except requests.RequestException as e:
        result["status"] = "critical"
        result["message"] = f"Failed to fetch changesets from OHM API: {e}"
        return result

    if not changesets:
        result["message"] = (
            f"No changesets found in the {min_age//60}-{max_age//60} minute window"
        )
        print(f"[pipeline] {result['message']}")
        return result

    print(f"[pipeline] Found {len(changesets)} changesets in "
          f"{min_age//60}-{max_age//60}min window")

    # --- Connect to tiler DB ---
    conn = None
    try:
        conn = psycopg2.connect(
            host=Config.POSTGRES_HOST,
            port=Config.POSTGRES_PORT,
            dbname=Config.POSTGRES_DB,
            user=Config.POSTGRES_USER,
            password=Config.POSTGRES_PASSWORD,
        )
    except psycopg2.Error as e:
        result["status"] = "critical"
        result["message"] = f"Cannot connect to tiler DB: {e}"
        print(f"[pipeline] ERROR: Cannot connect to tiler DB: {e}")
        return result

    # --- Check each changeset through the pipeline ---
    problems = []

    for cs in changesets:
        print(f"\n[pipeline] === Changeset {cs['id']} === "
              f"(closed_at={cs['closed_at']}, age={cs['age_minutes']}min)")
        print(f"  URL: {_ohm_base()}/changeset/{cs['id']}")

        cs_result = {
            "changeset_id": cs["id"],
            "changeset_url": f"{_ohm_base()}/changeset/{cs['id']}",
            "closed_at": cs["closed_at"],
            "age_minutes": cs["age_minutes"],
            "replication": {},
            "tiler_db": {},
        }

        # Step 1: replication
        if repl_seq is not None:
            repl_check = _check_replication_covers(cs, repl_seq, repl_ts)
            cs_result["replication"] = repl_check
            print(f"  [replication] {repl_check['status'].upper()}: {repl_check['message']}")

            if repl_check["status"] != "ok":
                problems.append(
                    f"Changeset {cs['id']}: replication not covering"
                )
        else:
            cs_result["replication"] = {"status": "unknown", "message": "Replication state unavailable"}
            print(f"  [replication] UNKNOWN: Replication state unavailable")

        # Step 2: tiler DB
        db_check = _check_elements_in_db(conn, cs["id"], cs["closed_at"])
        cs_result["tiler_db"] = db_check
        print(f"  [tiler_db] {db_check['status'].upper()}: {db_check['message']}")

        if db_check["status"] != "ok":
            problems.append(f"Changeset {cs['id']}: {db_check['message']}")

        result["details"]["changesets"].append(cs_result)

    conn.close()

    # --- Overall status ---
    if any(cs.get("replication", {}).get("status") == "critical"
           or cs.get("tiler_db", {}).get("status") in ("warning", "critical")
           for cs in result["details"]["changesets"]):
        result["status"] = "warning"
        result["message"] = f"Issues found: {'; '.join(problems[:5])}"
    else:
        result["message"] = (
            f"All {len(changesets)} changesets in {min_age//60}-{max_age//60}min "
            f"window passed pipeline check"
        )

    print(f"\n[pipeline] Result: {result['status'].upper()} — {result['message']}")
    return result


# ---------------------------------------------------------------------------
# On-demand single changeset check
# ---------------------------------------------------------------------------

def check_single_changeset(changeset_id):
    """Evaluate a single changeset through the full pipeline (on-demand)."""
    now = datetime.now(timezone.utc)
    result = {
        "name": "pipeline",
        "changeset_id": changeset_id,
        "changeset_url": f"{_ohm_base()}/changeset/{changeset_id}",
        "status": "ok",
        "message": "",
        "details": {"replication": {}, "tiler_db": {}},
        "checked_at": now.isoformat(),
    }

    # Get changeset info
    try:
        url = f"{Config.OHM_API_BASE}/changeset/{changeset_id}"
        headers = {"User-Agent": "ohm-pipeline-monitor/1.0"}
        resp = requests.get(url, headers=headers, timeout=30)
        resp.raise_for_status()
        root = ET.fromstring(resp.content)
        cs_elem = root.find("changeset")
        closed_at = cs_elem.attrib.get("closed_at", "") if cs_elem is not None else ""
    except Exception:
        closed_at = ""

    print(f"\n[pipeline] === Changeset {changeset_id} (on-demand) ===")
    print(f"  URL: {_ohm_base()}/changeset/{changeset_id}")
    if closed_at:
        print(f"  closed_at: {closed_at}")

    # Step 1: replication
    try:
        resp = requests.get(Config.REPLICATION_STATE_URL, timeout=15)
        resp.raise_for_status()
        repl_seq, repl_ts = _parse_replication_state(resp.text)

        if closed_at and repl_ts:
            closed_dt = _parse_timestamp(closed_at)
            cs_data = {"closed_at": closed_at, "closed_dt": closed_dt}
            repl_check = _check_replication_covers(cs_data, repl_seq, repl_ts)
        else:
            repl_check = {
                "status": "ok" if repl_ts else "warning",
                "message": f"Replication seq={repl_seq}, ts={repl_ts.isoformat() if repl_ts else 'unknown'}",
                "replication_sequence": repl_seq,
                "replication_timestamp": repl_ts.isoformat() if repl_ts else None,
            }

        result["details"]["replication"] = repl_check
        print(f"  [replication] {repl_check['status'].upper()}: {repl_check['message']}")
    except requests.RequestException as e:
        result["details"]["replication"] = {
            "status": "critical",
            "message": f"Failed to fetch replication state: {e}",
        }
        print(f"  [replication] CRITICAL: Cannot fetch replication state: {e}")

    # Step 2: tiler DB
    try:
        conn = psycopg2.connect(
            host=Config.POSTGRES_HOST,
            port=Config.POSTGRES_PORT,
            dbname=Config.POSTGRES_DB,
            user=Config.POSTGRES_USER,
            password=Config.POSTGRES_PASSWORD,
        )
    except psycopg2.Error as e:
        result["status"] = "critical"
        result["message"] = f"Cannot connect to tiler DB: {e}"
        result["details"]["tiler_db"] = {"status": "critical", "message": str(e)}
        return result

    db_check = _check_elements_in_db(conn, changeset_id, closed_at or None)
    conn.close()
    result["details"]["tiler_db"] = db_check
    print(f"  [tiler_db] {db_check['status'].upper()}: {db_check['message']}")

    # Overall
    problems = []
    repl_status = result["details"]["replication"].get("status", "ok")
    if repl_status == "critical":
        problems.append("Replication not covering this changeset")
    if db_check["status"] != "ok":
        problems.append(db_check["message"])

    if problems:
        result["status"] = "warning"
        result["message"] = "; ".join(problems)
    else:
        result["message"] = (
            f"Changeset {changeset_id} passed full pipeline check "
            f"({len(db_check.get('elements', []))} elements verified)"
        )

    print(f"  [result] {result['status'].upper()}: {result['message']}")
    return result
