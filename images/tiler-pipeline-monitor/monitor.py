"""Vtile pipeline monitor.

Runs periodic changeset-centric checks and exposes results via a FastAPI HTTP
server.  Optionally sends Slack alerts when checks fail.
"""

import logging
import threading
import time
from datetime import datetime, timezone

import requests
import uvicorn
from fastapi import FastAPI
from fastapi.responses import JSONResponse

from checks.imposm_import import check_pipeline, check_single_changeset
from config import Config

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
    text = f"{emoji} *{check_result['name']}* — {check_result['status'].upper()}\n{check_result['message']}"
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

        # Alert on state transitions to non-ok
        if result["status"] != "ok":
            if prev is None or prev["status"] == "ok":
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


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Start background scheduler
    t = threading.Thread(target=_scheduler, daemon=True)
    t.start()

    # Start HTTP server
    uvicorn.run(app, host="0.0.0.0", port=Config.MONITOR_PORT)
