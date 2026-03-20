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
            PRIMARY KEY (changeset_id, element_type, osm_id)
        )
    """)
    # Migrate: add columns if missing (for existing DBs)
    for col, typedef in [("version", "INTEGER NOT NULL DEFAULT 0"),
                         ("action", "TEXT NOT NULL DEFAULT ''")]:
        try:
            conn.execute(f"ALTER TABLE pending_retries ADD COLUMN {col} {typedef}")
        except sqlite3.OperationalError:
            pass

    conn.execute("""
        CREATE TABLE IF NOT EXISTS changeset_history (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            changeset_id    INTEGER NOT NULL,
            closed_at       TEXT    NOT NULL DEFAULT '',
            checked_at      TEXT    NOT NULL,
            status          TEXT    NOT NULL,
            total_elements  INTEGER NOT NULL DEFAULT 0,
            missing_count   INTEGER NOT NULL DEFAULT 0,
            ok_count        INTEGER NOT NULL DEFAULT 0,
            message         TEXT    NOT NULL DEFAULT ''
        )
    """)
    try:
        conn.execute("ALTER TABLE changeset_history ADD COLUMN closed_at TEXT NOT NULL DEFAULT ''")
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

    conn.commit()


# ---------------------------------------------------------------------------
# Pending retries
# ---------------------------------------------------------------------------

def add_missing(changeset_id: int, element_type: str, osm_id: int,
                max_retries: int, version: int = 0, action: str = ""):
    """Register a missing element for future retry. If it already exists, do nothing."""
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        conn.execute("""
            INSERT OR IGNORE INTO pending_retries
                (changeset_id, element_type, osm_id, version, action,
                 retry_count, max_retries, first_seen, last_checked, status)
            VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, 'pending')
        """, (changeset_id, element_type, osm_id, version, action, max_retries, now, now))
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


def increment_retry(changeset_id: int, element_type: str, osm_id: int):
    """Bump retry_count. If it reaches max_retries, flip status to 'failed'.

    Returns the new status ('pending' or 'failed').
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
                UPDATE pending_retries SET status = 'failed'
                WHERE changeset_id = ? AND element_type = ? AND osm_id = ?
            """, (changeset_id, element_type, osm_id))
            conn.commit()
            return "failed"

        conn.commit()
        return "pending"


def get_failed():
    """Return all elements that exhausted their retries."""
    with _lock:
        conn = _get_conn()
        rows = conn.execute(
            "SELECT * FROM pending_retries WHERE status = 'failed'"
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

    now = datetime.now(timezone.utc)
    results = []
    for r in rows:
        entry = dict(r)
        entry["changeset_url"] = f"{ohm_base}/changeset/{r['changeset_id']}"
        entry["element_url"] = f"{ohm_base}/{r['element_type']}/{r['osm_id']}"
        if r["version"]:
            entry["element_url"] += f"/history/{r['version']}"
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
        entry["retries_remaining"] = max(0, r["max_retries"] - r["retry_count"])
        results.append(entry)
    return results


# ---------------------------------------------------------------------------
# Changeset history
# ---------------------------------------------------------------------------

def log_changeset_check(changeset_id: int, status: str,
                        total_elements: int, missing_count: int,
                        ok_count: int, message: str,
                        closed_at: str = "", elements: list = None):
    """Record a changeset check and its elements in the history tables."""
    now = datetime.now(timezone.utc).isoformat()
    with _lock:
        conn = _get_conn()
        cur = conn.execute("""
            INSERT INTO changeset_history
                (changeset_id, closed_at, checked_at, status, total_elements, missing_count, ok_count, message)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """, (changeset_id, closed_at or "", now, status, total_elements, missing_count, ok_count, message))
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
        if r["version"]:
            entry["element_url"] += f"/history/{r['version']}"
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
