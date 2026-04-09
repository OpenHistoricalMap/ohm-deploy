"""SQLite-backed retry store for missing pipeline elements.

Tracks elements that were not found in the tiler DB so they can be
rechecked on subsequent runs.  After MAX_RETRIES consecutive failures
the element is marked as "failed" and an alert can be triggered.

Uses a single shared connection with a threading lock to avoid
"database is locked" errors from concurrent access.
"""

import logging
import sqlite3
import os
import threading
from datetime import datetime, timezone

logger = logging.getLogger(__name__)

_DB_PATH = os.getenv("TILER_MONITORING_RETRY_DB", "/data/pipeline_retries.db")
_lock = threading.Lock()
_conn = None


def _get_conn():
    """Return the shared connection, creating it on first call."""
    global _conn
    if _conn is None:
        _conn = sqlite3.connect(_DB_PATH, check_same_thread=False)
        _conn.row_factory = sqlite3.Row
        _conn.execute("PRAGMA journal_mode=WAL")
        _conn.execute("PRAGMA busy_timeout=5000")
        _init_tables(_conn)
    return _conn


def _init_tables(conn):
    """Create all tables and indexes."""
    conn.execute("""
        CREATE TABLE IF NOT EXISTS pending_retries (
            changeset_id  INTEGER NOT NULL,
            element_type  TEXT    NOT NULL,
            osm_id        INTEGER NOT NULL,
            version       INTEGER NOT NULL DEFAULT 0,
            action        TEXT    NOT NULL DEFAULT '',
            retry_count   INTEGER NOT NULL DEFAULT 0,
            max_retries   INTEGER NOT NULL,
            first_seen    TEXT    NOT NULL,
            last_checked  TEXT    NOT NULL,
            status        TEXT    NOT NULL DEFAULT 'pending',
            closed_at     TEXT    NOT NULL DEFAULT '',
            PRIMARY KEY (changeset_id, element_type, osm_id)
        )
    """)
    # Migrate: add columns if missing (for existing DBs)
    for col, typedef in [("version", "INTEGER NOT NULL DEFAULT 0"),
                         ("action", "TEXT NOT NULL DEFAULT ''"),
                         ("closed_at", "TEXT NOT NULL DEFAULT ''")]:
        try:
            conn.execute(f"ALTER TABLE pending_retries ADD COLUMN {col} {typedef}")
        except sqlite3.OperationalError:
            pass

    conn.execute("""
        CREATE TABLE IF NOT EXISTS changeset_history (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            changeset_id    INTEGER NOT NULL,
            created_at      TEXT    NOT NULL DEFAULT '',
            closed_at       TEXT    NOT NULL DEFAULT '',
            checked_at      TEXT    NOT NULL,
            status          TEXT    NOT NULL,
            total_elements  INTEGER NOT NULL DEFAULT 0,
            missing_count   INTEGER NOT NULL DEFAULT 0,
            ok_count        INTEGER NOT NULL DEFAULT 0,
            message         TEXT    NOT NULL DEFAULT ''
        )
    """)
    for hist_col, hist_typedef in [("closed_at", "TEXT NOT NULL DEFAULT ''"),
                                    ("created_at", "TEXT NOT NULL DEFAULT ''")]:
        try:
            conn.execute(f"ALTER TABLE changeset_history ADD COLUMN {hist_col} {hist_typedef}")
        except sqlite3.OperationalError:
            pass
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_history_checked_at
        ON changeset_history(checked_at DESC)
    """)

    conn.execute("""
        CREATE TABLE IF NOT EXISTS element_history (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            history_id      INTEGER NOT NULL,
            changeset_id    INTEGER NOT NULL,
            element_type    TEXT    NOT NULL,
            osm_id          INTEGER NOT NULL,
            version         INTEGER NOT NULL DEFAULT 0,
            action          TEXT    NOT NULL DEFAULT '',
            status          TEXT    NOT NULL,
            found_in_tables TEXT    NOT NULL DEFAULT '',
            found_in_views  TEXT    NOT NULL DEFAULT '',
            checked_at      TEXT    NOT NULL,
            FOREIGN KEY (history_id) REFERENCES changeset_history(id)
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_element_history_id
        ON element_history(history_id)
    """)

    # Feed events: persistent log of alerts (failed elements, recoveries)
    # for the RSS feed. Items are never deleted, only added.
    conn.execute("""
        CREATE TABLE IF NOT EXISTS feed_events (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type      TEXT    NOT NULL,
            element_type    TEXT    NOT NULL DEFAULT '',
            osm_id          INTEGER NOT NULL DEFAULT 0,
            version         INTEGER NOT NULL DEFAULT 0,
            changeset_id    INTEGER NOT NULL DEFAULT 0,
            action          TEXT    NOT NULL DEFAULT '',
            title           TEXT    NOT NULL,
            description     TEXT    NOT NULL DEFAULT '',
            link            TEXT    NOT NULL DEFAULT '',
            created_at      TEXT    NOT NULL
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_feed_events_created
        ON feed_events(created_at DESC)
    """)

    # Comment drafts: elements with tiler-relevant tags that imposm rejected.
    # Stored for review before posting actual changeset comments.
    conn.execute("""
        CREATE TABLE IF NOT EXISTS comment_drafts (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            changeset_id    INTEGER NOT NULL,
            element_type    TEXT    NOT NULL,
            osm_id          INTEGER NOT NULL,
            version         INTEGER NOT NULL DEFAULT 0,
            action          TEXT    NOT NULL DEFAULT '',
            skip_reason     TEXT    NOT NULL,
            tags            TEXT    NOT NULL DEFAULT '',
            created_at      TEXT    NOT NULL,
            UNIQUE(changeset_id, element_type, osm_id)
        )
    """)
    conn.execute("""
        CREATE INDEX IF NOT EXISTS idx_comment_drafts_created
        ON comment_drafts(created_at DESC)
    """)

    conn.commit()


# ---------------------------------------------------------------------------
# Pending retries
# ---------------------------------------------------------------------------

def add_missing(changeset_id: int, element_type: str, osm_id: int,
                max_retries: int, version: int = 0, action: str = "",
                closed_at: str = ""):
    """Register a missing element for future retry. If it already exists, do nothing."""
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute("""
            INSERT OR IGNORE INTO pending_retries
                (changeset_id, element_type, osm_id, version, action,
                 retry_count, max_retries, first_seen, last_checked, status, closed_at)
            VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, 'pending', ?)
        """, (changeset_id, element_type, osm_id, version, action, max_retries, now, now, closed_at or ""))
        conn.commit()


def get_pending():
    """Return all elements with status='pending' that still need to be rechecked."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT * FROM pending_retries WHERE status = 'pending'"
        ).fetchall()
        return [dict(r) for r in rows]


def mark_resolved(changeset_id: int, element_type: str, osm_id: int):
    """Element was found in a retry — remove it from pending."""
    with _lock:
        conn = _get_conn()
        conn.execute("""
            DELETE FROM pending_retries
            WHERE changeset_id = ? AND element_type = ? AND osm_id = ?
        """, (changeset_id, element_type, osm_id))
        conn.commit()


def increment_retry(changeset_id: int, element_type: str, osm_id: int,
                     final_status: str = "failed"):
    """Bump retry_count. If it reaches max_retries, flip status to *final_status*.

    *final_status* is normally 'failed', but callers may pass 'warning' when
    the missing percentage is below the alerting threshold.

    Returns the new status ('pending', 'warning', or 'failed').
    """
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute("""
            UPDATE pending_retries
            SET retry_count = retry_count + 1, last_checked = ?
            WHERE changeset_id = ? AND element_type = ? AND osm_id = ?
        """, (now, changeset_id, element_type, osm_id))

        row = conn.execute("""
            SELECT retry_count, max_retries FROM pending_retries
            WHERE changeset_id = ? AND element_type = ? AND osm_id = ?
        """, (changeset_id, element_type, osm_id)).fetchone()

        if row and row["retry_count"] >= row["max_retries"]:
            conn.execute("""
                UPDATE pending_retries SET status = ?
                WHERE changeset_id = ? AND element_type = ? AND osm_id = ?
            """, (final_status, changeset_id, element_type, osm_id))
            conn.commit()
            return final_status

        conn.commit()
        return "pending"


def get_failed():
    """Return all elements that exhausted their retries with status='failed'."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT * FROM pending_retries WHERE status = 'failed'"
        ).fetchall()
        return [dict(r) for r in rows]


def get_warnings():
    """Return all elements that exhausted retries but are below the missing threshold."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT * FROM pending_retries WHERE status = 'warning'"
        ).fetchall()
        return [dict(r) for r in rows]


def clear_failed():
    """Remove all failed entries (call after alerting)."""
    with _lock:
        conn = _get_conn()
        conn.execute("DELETE FROM pending_retries WHERE status = 'failed'")
        conn.commit()


def get_all_details(ohm_base="https://www.openhistoricalmap.org"):
    """Return all entries enriched with URLs and human-readable times."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT * FROM pending_retries ORDER BY status, first_seen DESC"
        ).fetchall()

        # Get changeset object counts from history (latest check per changeset)
        cs_ids = list(set(r["changeset_id"] for r in rows))
        cs_stats = {}
        if cs_ids:
            placeholders = ",".join("?" * len(cs_ids))
            stats_rows = conn.execute(f"""
                SELECT changeset_id, total_elements, missing_count, ok_count
                FROM changeset_history
                WHERE id IN (
                    SELECT MAX(id) FROM changeset_history
                    WHERE changeset_id IN ({placeholders})
                    GROUP BY changeset_id
                )
            """, cs_ids).fetchall()
            for sr in stats_rows:
                cs_stats[sr["changeset_id"]] = {
                    "total_elements": sr["total_elements"],
                    "missing_count": sr["missing_count"],
                    "ok_count": sr["ok_count"],
                }

    now = datetime.now(timezone.utc)
    results = []
    for r in rows:
        entry = dict(r)
        entry["changeset_url"] = f"{ohm_base}/changeset/{r['changeset_id']}"
        entry["element_url"] = f"{ohm_base}/{r['element_type']}/{r['osm_id']}"
        try:
            first = datetime.fromisoformat(r["first_seen"])
            entry["age"] = _human_duration((now - first).total_seconds())
        except Exception:
            entry["age"] = ""
        try:
            last = datetime.fromisoformat(r["last_checked"])
            entry["last_checked_ago"] = _human_duration((now - last).total_seconds())
        except Exception:
            entry["last_checked_ago"] = ""
        # Changeset closed_at (close time as formatted date)
        closed_at_val = r["closed_at"] if "closed_at" in r.keys() else ""
        if closed_at_val:
            try:
                closed = datetime.fromisoformat(closed_at_val.replace("Z", "+00:00"))
                entry["closed_at_fmt"] = closed.strftime("%Y-%m-%d %H:%M UTC")
            except Exception:
                entry["closed_at_fmt"] = ""
        else:
            entry["closed_at_fmt"] = ""
        # Changeset object counts
        stats = cs_stats.get(r["changeset_id"], {})
        entry["cs_total_elements"] = stats.get("total_elements", 0)
        entry["cs_ok_count"] = stats.get("ok_count", 0)
        entry["cs_missing_count"] = stats.get("missing_count", 0)
        entry["retries_remaining"] = max(0, r["max_retries"] - r["retry_count"])
        results.append(entry)
    return results


# ---------------------------------------------------------------------------
# Changeset stats helpers
# ---------------------------------------------------------------------------

def get_changeset_stats(changeset_id: int):
    """Return the latest total_elements, missing_count, ok_count for a changeset.

    Returns a dict with those keys, or None if no history exists.
    """
    with _lock:
        conn = _get_conn()
        row = conn.execute("""
            SELECT total_elements, missing_count, ok_count
            FROM changeset_history
            WHERE changeset_id = ?
            ORDER BY id DESC LIMIT 1
        """, (changeset_id,)).fetchone()
    if row:
        return {
            "total_elements": row["total_elements"],
            "missing_count": row["missing_count"],
            "ok_count": row["ok_count"],
        }
    return None


# ---------------------------------------------------------------------------
# Changeset history
# ---------------------------------------------------------------------------

def log_changeset_check(changeset_id: int, status: str,
                        total_elements: int, missing_count: int,
                        ok_count: int, message: str,
                        created_at: str = "", closed_at: str = "",
                        elements: list = None):
    """Record a changeset check and its elements in the history tables."""
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        cur = conn.execute("""
            INSERT INTO changeset_history
                (changeset_id, created_at, closed_at, checked_at, status, total_elements, missing_count, ok_count, message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (changeset_id, created_at or "", closed_at or "", now, status, total_elements, missing_count, ok_count, message))
        history_id = cur.lastrowid

        if elements:
            for elem in elements:
                tables = ", ".join(elem.get("found_in_tables", []))
                views = ", ".join(elem.get("found_in_views", []))
                found = bool(elem.get("found_in_tables"))
                deleted = elem.get("deleted", False)
                if deleted:
                    elem_status = "skipped"
                elif elem.get("action") == "delete":
                    elem_status = "ok" if not found else "not_deleted"
                elif found:
                    elem_status = "ok"
                else:
                    elem_status = "missing"
                conn.execute("""
                    INSERT INTO element_history
                        (history_id, changeset_id, element_type, osm_id, version,
                         action, status, found_in_tables, found_in_views, checked_at)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (history_id, changeset_id, elem.get("type", ""),
                      elem.get("osm_id", 0), elem.get("version", 0),
                      elem.get("action", ""), elem_status, tables, views, now))
        conn.commit()


def get_changeset_history(page: int = 1, per_page: int = 20,
                          ohm_base: str = "https://www.openhistoricalmap.org"):
    """Return paginated changeset check history with details."""
    with _lock:
        conn = _get_conn()
        total = conn.execute("SELECT COUNT(*) FROM changeset_history").fetchone()[0]
        total_pages = max(1, (total + per_page - 1) // per_page)
        offset = (page - 1) * per_page

        rows = conn.execute("""
            SELECT * FROM changeset_history
            ORDER BY checked_at DESC
            LIMIT ? OFFSET ?
        """, (per_page, offset)).fetchall()

    now = datetime.now(timezone.utc)
    results = []
    for r in rows:
        entry = dict(r)
        entry["changeset_url"] = f"{ohm_base}/changeset/{r['changeset_id']}"
        try:
            checked = datetime.fromisoformat(r["checked_at"])
            entry["checked_ago"] = _human_duration((now - checked).total_seconds())
        except Exception:
            entry["checked_ago"] = ""
        if r["closed_at"]:
            try:
                closed = datetime.fromisoformat(r["closed_at"].replace("Z", "+00:00"))
                entry["closed_ago"] = _human_duration((now - closed).total_seconds())
            except Exception:
                entry["closed_ago"] = ""
        else:
            entry["closed_ago"] = ""
        created_at_val = r["created_at"] if "created_at" in r.keys() else ""
        if created_at_val:
            try:
                created = datetime.fromisoformat(created_at_val.replace("Z", "+00:00"))
                entry["created_fmt"] = created.strftime("%Y-%m-%d %H:%M UTC")
            except Exception:
                entry["created_fmt"] = ""
        else:
            entry["created_fmt"] = ""
        results.append(entry)

    return {
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": total_pages,
        "changesets": results,
    }


def get_changeset_elements(history_id: int,
                           ohm_base: str = "https://www.openhistoricalmap.org"):
    """Return all elements checked for a specific history entry."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute("""
            SELECT * FROM element_history
            WHERE history_id = ?
            ORDER BY status DESC, element_type, osm_id
        """, (history_id,)).fetchall()

    results = []
    for r in rows:
        entry = dict(r)
        entry["element_url"] = f"{ohm_base}/{r['element_type']}/{r['osm_id']}"
        entry["found_in_tables"] = r["found_in_tables"].split(", ") if r["found_in_tables"] else []
        entry["found_in_views"] = r["found_in_views"].split(", ") if r["found_in_views"] else []
        results.append(entry)
    return results


def is_changeset_passed(changeset_id: int) -> bool:
    """Return True if this changeset was already checked with status 'ok'."""
    with _lock:
        conn = _get_conn()
        row = conn.execute("""
            SELECT 1 FROM changeset_history
            WHERE changeset_id = ? AND status = 'ok'
            LIMIT 1
        """, (changeset_id,)).fetchone()
        return row is not None


def summary():
    """Return counts by status for logging."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT status, COUNT(*) as cnt FROM pending_retries GROUP BY status"
        ).fetchall()
        return {r["status"]: r["cnt"] for r in rows}


# ---------------------------------------------------------------------------
# Feed events
# ---------------------------------------------------------------------------

def add_feed_event(event_type: str, title: str, description: str = "",
                   link: str = "", element_type: str = "", osm_id: int = 0,
                   version: int = 0, changeset_id: int = 0, action: str = ""):
    """Add a persistent event to the RSS feed."""
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute("""
            INSERT INTO feed_events
                (event_type, element_type, osm_id, version, changeset_id,
                 action, title, description, link, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (event_type, element_type, osm_id, version, changeset_id,
              action, title, description, link, now))
        conn.commit()


def get_feed_events(limit: int = 50):
    """Return the most recent feed events for the RSS feed."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute("""
            SELECT * FROM feed_events
            ORDER BY created_at DESC
            LIMIT ?
        """, (limit,)).fetchall()
        return [dict(r) for r in rows]


# ---------------------------------------------------------------------------
# Comment drafts
# ---------------------------------------------------------------------------

def add_comment_draft(changeset_id: int, element_type: str, osm_id: int,
                      skip_reason: str, version: int = 0, action: str = "",
                      tags: dict = None):
    """Store a commentable element for review in the dashboard."""
    import json
    now = datetime.now(timezone.utc).isoformat()
    tags_str = json.dumps(tags) if tags else "{}"
    with _lock:
        conn = _get_conn()
        conn.execute("""
            INSERT OR IGNORE INTO comment_drafts
                (changeset_id, element_type, osm_id, version, action,
                 skip_reason, tags, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (changeset_id, element_type, osm_id, version, action,
              skip_reason, tags_str, now))
        conn.commit()


def get_comment_drafts(page: int = 1, per_page: int = 50,
                       ohm_base: str = "https://www.openhistoricalmap.org"):
    """Return paginated comment drafts grouped by changeset."""
    import json
    with _lock:
        conn = _get_conn()
        total = conn.execute("SELECT COUNT(*) FROM comment_drafts").fetchone()[0]
        total_pages = max(1, (total + per_page - 1) // per_page)
        offset = (page - 1) * per_page

        rows = conn.execute("""
            SELECT * FROM comment_drafts
            ORDER BY created_at DESC
            LIMIT ? OFFSET ?
        """, (per_page, offset)).fetchall()

    now = datetime.now(timezone.utc)
    results = []
    for r in rows:
        entry = dict(r)
        entry["element_url"] = f"{ohm_base}/{r['element_type']}/{r['osm_id']}"
        entry["changeset_url"] = f"{ohm_base}/changeset/{r['changeset_id']}"
        try:
            entry["tags"] = json.loads(r["tags"]) if r["tags"] else {}
        except Exception:
            entry["tags"] = {}
        try:
            created = datetime.fromisoformat(r["created_at"])
            entry["created_ago"] = _human_duration((now - created).total_seconds())
        except Exception:
            entry["created_ago"] = ""
        results.append(entry)

    # Group by changeset for the preview
    changesets = {}
    for r in results:
        cs_id = r["changeset_id"]
        if cs_id not in changesets:
            changesets[cs_id] = {
                "changeset_id": cs_id,
                "changeset_url": r["changeset_url"],
                "elements": [],
                "created_ago": r["created_ago"],
            }
        changesets[cs_id]["elements"].append(r)

    return {
        "page": page,
        "per_page": per_page,
        "total": total,
        "total_pages": total_pages,
        "drafts": results,
        "by_changeset": list(changesets.values()),
    }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _human_duration(seconds):
    """Convert seconds to human-readable string like '2h 15m ago'."""
    seconds = int(seconds)
    if seconds < 60:
        return f"{seconds}s ago"
    minutes = seconds // 60
    if minutes < 60:
        return f"{minutes}m ago"
    hours = minutes // 60
    remaining_min = minutes % 60
    if hours < 24:
        return f"{hours}h {remaining_min}m ago" if remaining_min else f"{hours}h ago"
    days = hours // 24
    remaining_hours = hours % 24
    return f"{days}d {remaining_hours}h ago" if remaining_hours else f"{days}d ago"
