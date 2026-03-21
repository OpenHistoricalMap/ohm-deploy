"""Vtile pipeline monitor.

Runs periodic changeset-centric checks and exposes results via a FastAPI HTTP
server.  Optionally sends Slack alerts when checks fail.
"""

import logging
import os
import threading
import time
from datetime import datetime, timezone

import requests
import uvicorn
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse

from checks.imposm_import import check_pipeline, check_single_changeset, recheck_retries
from config import Config
import retry_store

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# Store latest check result
_latest_result = None
_lock = threading.Lock()

app = FastAPI(title="OHM Vtile Pipeline Monitor")


# ---------------------------------------------------------------------------
# Slack alerting
# ---------------------------------------------------------------------------

def _send_slack_alert(check_result):
    """Send a Slack notification when a check is not ok."""
    if not Config.SLACK_WEBHOOK_URL:
        return
    status_emoji = {"ok": ":white_check_mark:", "warning": ":warning:", "critical": ":rotating_light:"}
    emoji = status_emoji.get(check_result["status"], ":question:")
    ohm = "https://www.openhistoricalmap.org"

    lines = [f"{emoji} *OHM Tiler Pipeline Monitor* — {check_result['status'].upper()}"]
    lines.append(check_result["message"])

    # Add failed element details with links
    newly_failed = check_result.get("details", {}).get("newly_failed", [])
    if newly_failed:
        lines.append("")
        lines.append("*Elements missing after all retries:*")
        for f in newly_failed[:10]:
            cs_url = f"{ohm}/changeset/{f['changeset_id']}"
            elem_url = f"{ohm}/{f['type']}/{f['osm_id']}"
            lines.append(f"  • <{elem_url}|{f['type']}/{f['osm_id']}> in <{cs_url}|changeset {f['changeset_id']}>")

    # Add dashboard link
    if Config.MONITOR_BASE_URL:
        lines.append("")
        lines.append(f":mag: <{Config.MONITOR_BASE_URL}|Open Dashboard> · "
                     f"<{Config.MONITOR_BASE_URL}/retries|View Retries>")

    # Add changeset-level issues
    changesets = check_result.get("details", {}).get("changesets", [])
    cs_issues = [cs for cs in changesets
                 if cs.get("tiler_db", {}).get("status") not in ("ok", "retry_pending", None)]
    if cs_issues and not newly_failed:
        lines.append("")
        for cs in cs_issues[:5]:
            cs_url = f"{ohm}/changeset/{cs['changeset_id']}"
            msg = cs.get("tiler_db", {}).get("message", "")
            lines.append(f"  • <{cs_url}|Changeset {cs['changeset_id']}>: {msg}")

    text = "\n".join(lines)
    try:
        requests.post(
            Config.SLACK_WEBHOOK_URL,
            json={"text": text},
            timeout=10,
        )
    except requests.RequestException as e:
        logger.error(f"Failed to send Slack alert: {e}")


# ---------------------------------------------------------------------------
# Background scheduler
# ---------------------------------------------------------------------------

def _run_check():
    """Run the pipeline check and update stored result."""
    try:
        logger.info("=============> Running pipeline check")
        result = check_pipeline()
        logger.info(f"Pipeline check: {result['status']} — {result['message']}")

        with _lock:
            prev = _latest_result
            globals()["_latest_result"] = result

        # Alert on state changes or new failures
        newly_failed = result.get("details", {}).get("newly_failed", [])
        if newly_failed:
            # New elements just exhausted retries — always alert
            _send_slack_alert(result)
        elif result["status"] == "warning":
            if prev is None or prev["status"] == "ok":
                _send_slack_alert(result)
        elif result["status"] == "ok" and prev and prev["status"] in ("critical", "warning"):
            # Recovered — send ok notification
            _send_slack_alert(result)

    except Exception as e:
        logger.exception(f"Pipeline check raised an exception: {e}")
        with _lock:
            globals()["_latest_result"] = {
                "name": "pipeline",
                "status": "critical",
                "message": f"Check failed with exception: {e}",
                "details": {},
                "checked_at": datetime.now(timezone.utc).isoformat(),
            }


def _scheduler():
    """Background loop that runs checks at the configured interval."""
    logger.info(f"Pipeline monitor starting. Check interval: {Config.CHECK_INTERVAL}s")
    time.sleep(10)

    while True:
        _run_check()
        time.sleep(Config.CHECK_INTERVAL)


# ---------------------------------------------------------------------------
# HTTP endpoints
# ---------------------------------------------------------------------------

_STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")


@app.get("/", response_class=HTMLResponse)
def dashboard():
    """Serve the monitoring dashboard."""
    html_path = os.path.join(_STATIC_DIR, "dashboard.html")
    with open(html_path) as f:
        return HTMLResponse(content=f.read())


@app.get("/health")
def health():
    """Overall health: returns 200 if ok, 503 otherwise."""
    with _lock:
        result = _latest_result

    if result is None:
        return JSONResponse(
            content={"status": "starting", "message": "No checks have run yet"},
            status_code=200,
        )

    status_code = 200 if result["status"] == "ok" else 503
    return JSONResponse(
        content={
            "status": result["status"],
            "message": result["message"],
            "checked_at": result["checked_at"],
        },
        status_code=status_code,
    )


@app.get("/checks")
def all_checks():
    """Return full details for the latest pipeline check."""
    with _lock:
        result = _latest_result
    if result is None:
        return JSONResponse(content={"status": "starting"})
    return JSONResponse(content=result)


@app.get("/changeset/{changeset_id}")
def evaluate_changeset(changeset_id: int):
    """Evaluate a specific changeset through the full pipeline (on-demand)."""
    result = check_single_changeset(changeset_id)
    status_code = 200 if result["status"] == "ok" else 503
    return JSONResponse(content=result, status_code=status_code)


@app.post("/retries/recheck")
def retries_recheck():
    """Manually trigger a recheck of all pending and failed retries."""
    result = recheck_retries()
    return JSONResponse(content=result)


@app.post("/retries/recheck/{element_type}/{osm_id}")
def retries_recheck_single(element_type: str, osm_id: int):
    """Manually recheck a single element in the tiler DB."""
    from checks.imposm_import import recheck_single_element
    result = recheck_single_element(element_type, osm_id)
    return JSONResponse(content=result)


@app.get("/retries")
def retries():
    """Return current retry state with full details for debugging."""
    all_entries = retry_store.get_all_details()
    pending = [e for e in all_entries if e["status"] == "pending"]
    failed = [e for e in all_entries if e["status"] == "failed"]
    return JSONResponse(content={
        "summary": retry_store.summary(),
        "total": len(all_entries),
        "pending": pending,
        "failed": failed,
    })


@app.get("/history")
def history(page: int = 1, per_page: int = 20):
    """Paginated history of all changesets checked.

    Example: /history?page=1&per_page=10
    """
    data = retry_store.get_changeset_history(page=page, per_page=per_page)
    return JSONResponse(content=data)


@app.get("/history/{history_id}/elements")
def history_elements(history_id: int):
    """Return all elements checked for a specific history entry."""
    elements = retry_store.get_changeset_elements(history_id)
    return JSONResponse(content={"history_id": history_id, "elements": elements})


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Start background scheduler
    t = threading.Thread(target=_scheduler, daemon=True)
    t.start()

    # Start HTTP server
    uvicorn.run(app, host="0.0.0.0", port=Config.MONITOR_PORT)
