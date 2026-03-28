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
from fastapi.responses import HTMLResponse, JSONResponse, Response

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
            # Log each failed element as a feed event
            ohm = "https://www.openhistoricalmap.org"
            for f in newly_failed:
                retry_store.add_feed_event(
                    event_type="failed",
                    title=f"FAILED: {f['type']}/{f['osm_id']} not found in tiler DB after all retries",
                    description=(
                        f"Element {f['type']}/{f['osm_id']} from changeset {f['changeset_id']} "
                        f"was not found in the tiler database after all retries."
                    ),
                    link=f"{ohm}/{f['type']}/{f['osm_id']}",
                    element_type=f["type"],
                    osm_id=f["osm_id"],
                    changeset_id=f["changeset_id"],
                )
        elif result["status"] == "warning":
            if prev is None or prev["status"] == "ok":
                _send_slack_alert(result)
        elif result["status"] == "ok" and prev and prev["status"] in ("critical", "warning"):
            # Recovered — send ok notification
            _send_slack_alert(result)
            retry_store.add_feed_event(
                event_type="recovered",
                title="RECOVERED: All pipeline elements verified OK",
                description=result["message"],
            )

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

    # Update cached status if all retries are now resolved
    remaining = retry_store.summary()
    if remaining.get("failed", 0) == 0 and remaining.get("pending", 0) == 0:
        with _lock:
            prev = _latest_result
            if prev and prev.get("status") == "critical":
                updated = dict(prev)
                updated["status"] = "ok"
                updated["message"] = "All retries resolved"
                updated["details"] = dict(prev.get("details", {}))
                updated["details"]["retries"] = remaining
                updated["details"]["total_failed"] = 0
                updated["details"]["newly_failed"] = []
                globals()["_latest_result"] = updated

    return JSONResponse(content=result)


@app.post("/retries/recheck/{element_type}/{osm_id}")
def retries_recheck_single(element_type: str, osm_id: int):
    """Manually recheck a single element in the tiler DB."""
    try:
        from checks.imposm_import import recheck_single_element
        result = recheck_single_element(element_type, osm_id)

        # Update cached status if no more failed retries
        remaining = retry_store.summary()
        if remaining.get("failed", 0) == 0 and remaining.get("pending", 0) == 0:
            with _lock:
                prev = _latest_result
                if prev and prev.get("status") == "critical":
                    updated = dict(prev)
                    updated["status"] = "ok"
                    updated["message"] = "All retries resolved"
                    updated["details"] = dict(prev.get("details", {}))
                    updated["details"]["retries"] = remaining
                    updated["details"]["total_failed"] = 0
                    updated["details"]["newly_failed"] = []
                    globals()["_latest_result"] = updated

        return JSONResponse(content=result)
    except Exception as e:
        logger.exception(f"Recheck failed for {element_type}/{osm_id}")
        return JSONResponse(
            content={"status": "error", "message": f"Recheck failed: {e}"},
            status_code=500,
        )


@app.get("/retries")
def retries():
    """Return current retry state with full details for debugging."""
    all_entries = retry_store.get_all_details()
    pending = [e for e in all_entries if e["status"] == "pending"]
    failed = [e for e in all_entries if e["status"] == "failed"]
    warnings = [e for e in all_entries if e["status"] == "warning"]
    return JSONResponse(content={
        "summary": retry_store.summary(),
        "total": len(all_entries),
        "pending": pending,
        "failed": failed,
        "warnings": warnings,
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
# RSS / Atom feed
# ---------------------------------------------------------------------------

def _xml_escape(text):
    """Escape XML special characters."""
    return (str(text)
            .replace("&", "&amp;")
            .replace("<", "&lt;")
            .replace(">", "&gt;")
            .replace('"', "&quot;")
            .replace("'", "&apos;"))


def _to_rfc822(iso_str):
    """Convert ISO timestamp to RFC 822 format for RSS."""
    try:
        dt = datetime.fromisoformat(iso_str.replace("Z", "+00:00"))
        return dt.strftime("%a, %d %b %Y %H:%M:%S +0000")
    except Exception:
        return datetime.now(timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")


def _build_rss_feed():
    """Build an RSS 2.0 feed from persistent feed events.

    Each event is a unique item with a stable guid (based on DB id),
    so Slack's /feed command detects new items as they appear.
    """
    base_url = Config.MONITOR_BASE_URL or "https://tiler-monitoring.openhistoricalmap.org"
    now = datetime.now(timezone.utc)
    rfc822_now = now.strftime("%a, %d %b %Y %H:%M:%S +0000")

    events = retry_store.get_feed_events(limit=50)

    items_xml = []
    for ev in events:
        title = ev["title"]
        link = ev["link"] or base_url
        guid = f"ohm-tiler-feed-{ev['id']}"
        pub_date = _to_rfc822(ev["created_at"])
        desc = ev["description"]

        # Add element/changeset links in description if available
        if ev["osm_id"] and ev["element_type"]:
            ohm = "https://www.openhistoricalmap.org"
            elem_link = f"{ohm}/{ev['element_type']}/{ev['osm_id']}"
            cs_link = f"{ohm}/changeset/{ev['changeset_id']}" if ev["changeset_id"] else ""
            desc_parts = [desc]
            desc_parts.append(f"Element: {elem_link}")
            if cs_link:
                desc_parts.append(f"Changeset: {cs_link}")
            desc_parts.append(f"Dashboard: {base_url}")
            desc = " | ".join(desc_parts)

        items_xml.append(f"""    <item>
      <title>{_xml_escape(title)}</title>
      <link>{_xml_escape(link)}</link>
      <guid isPermaLink="false">{_xml_escape(guid)}</guid>
      <pubDate>{pub_date}</pubDate>
      <description>{_xml_escape(desc)}</description>
    </item>""")

    items_str = "\n".join(items_xml) if items_xml else ""

    feed = f"""<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
  <channel>
    <title>OHM Tiler Pipeline Monitor - Alerts</title>
    <link>{_xml_escape(base_url)}</link>
    <description>Alerts from the OHM tiler pipeline monitor: failed elements not found in the tiler DB after retries.</description>
    <language>en</language>
    <lastBuildDate>{rfc822_now}</lastBuildDate>
    <atom:link href="{_xml_escape(base_url)}/feed.rss" rel="self" type="application/rss+xml"/>
{items_str}
  </channel>
</rss>"""
    return feed


@app.get("/feed.rss")
def rss_feed():
    """RSS 2.0 feed of pipeline alerts for Slack integration."""
    xml = _build_rss_feed()
    return Response(content=xml, media_type="application/rss+xml")


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Start background scheduler
    t = threading.Thread(target=_scheduler, daemon=True)
    t.start()

    # Start HTTP server
    uvicorn.run(app, host="0.0.0.0", port=Config.MONITOR_PORT)
