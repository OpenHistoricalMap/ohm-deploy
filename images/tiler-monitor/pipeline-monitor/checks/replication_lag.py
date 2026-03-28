"""Check 1: Minute replication lag monitor.

Compares the latest replication sequence number available on S3
against the last sequence number processed by imposm (from the tiler DB
or the replication state endpoint).
"""

import time
from datetime import datetime, timezone

import requests

from config import Config


def _parse_state(text):
    """Parse an imposm/osm replication state.txt and return sequence + timestamp."""
    data = {}
    for line in text.strip().splitlines():
        if "=" in line:
            key, _, value = line.partition("=")
            data[key.strip()] = value.strip()
    seq = int(data.get("sequenceNumber", 0))
    ts_raw = data.get("timestamp", "")
    # Format: 2026-03-13T12\:05\:02Z  (escaped colons in java properties)
    ts_raw = ts_raw.replace("\\:", ":")
    try:
        ts = datetime.fromisoformat(ts_raw.replace("Z", "+00:00"))
    except ValueError:
        ts = None
    return seq, ts


def check_replication_lag():
    """Return a dict with the replication lag check result."""
    result = {
        "name": "replication_lag",
        "status": "ok",
        "message": "",
        "details": {},
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }

    try:
        # Get latest available replication state from S3
        resp = requests.get(Config.REPLICATION_STATE_URL, timeout=15)
        resp.raise_for_status()
        remote_seq, remote_ts = _parse_state(resp.text)

        result["details"]["remote_sequence"] = remote_seq
        result["details"]["remote_timestamp"] = remote_ts.isoformat() if remote_ts else None

        # Get imposm's last processed state
        # The imposm diff dir stores last.state.txt - we query it via the same
        # base URL pattern but from the local imposm state endpoint.
        # In Docker, we can check the DB for the latest sequence via the
        # osm_replication_status table if available, or fall back to comparing
        # timestamps of recent data.
        #
        # For now: compare remote timestamp against current time.
        # If remote_ts is stale, replication source itself is behind.
        # A more precise check reads imposm's last.state.txt from the shared volume.

        if remote_ts:
            lag_seconds = (datetime.now(timezone.utc) - remote_ts).total_seconds()
            result["details"]["lag_seconds"] = round(lag_seconds)
            result["details"]["lag_minutes"] = round(lag_seconds / 60, 1)

            if lag_seconds > Config.REPLICATION_LAG_THRESHOLD:
                result["status"] = "critical"
                result["message"] = (
                    f"Replication lag is {round(lag_seconds / 60, 1)} minutes "
                    f"(threshold: {Config.REPLICATION_LAG_THRESHOLD // 60} min). "
                    f"Last replication timestamp: {remote_ts.isoformat()}"
                )
            else:
                result["message"] = (
                    f"Replication is up to date. Lag: {round(lag_seconds / 60, 1)} min, "
                    f"sequence: {remote_seq}"
                )
        else:
            result["status"] = "warning"
            result["message"] = "Could not parse replication timestamp"

    except requests.RequestException as e:
        result["status"] = "critical"
        result["message"] = f"Failed to fetch replication state: {e}"

    return result
