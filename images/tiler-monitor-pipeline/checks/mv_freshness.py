"""Check 3: Materialized view freshness monitor.

Queries pg_stat_user_tables to check when materialized views were last
auto-analyzed/auto-vacuumed (proxy for last refresh), and also checks
if the views exist and have rows.
"""

from datetime import datetime, timezone

import psycopg2

from config import Config

# Key materialized views grouped by expected refresh interval.
# group_name -> (max_stale_seconds, [view_names])
MV_GROUPS = {
    "admin_boundaries_lines": (
        300,  # expect refresh every ~60s + buffer
        [
            "mv_admin_boundaries_lines_z4_5",
            "mv_admin_boundaries_lines_z6_7",
            "mv_admin_boundaries_lines_z8_9",
            "mv_admin_boundaries_lines_z10_11",
            "mv_admin_boundaries_lines_z12_13",
            "mv_admin_boundaries_lines_z14_15",
            "mv_admin_boundaries_lines_z16_20",
        ],
    ),
    "water": (
        600,  # expect refresh every ~180s + buffer
        [
            "mv_water_lines_z10_11",
            "mv_water_lines_z12_13",
            "mv_water_lines_z14_15",
            "mv_water_lines_z16_20",
            "mv_water_areas_z6_7",
            "mv_water_areas_z8_9",
            "mv_water_areas_z10_11",
            "mv_water_areas_z12_13",
            "mv_water_areas_z14_15",
            "mv_water_areas_z16_20",
        ],
    ),
    "transport": (
        600,
        [
            "mv_transport_lines_z8_9",
            "mv_transport_lines_z10_11",
            "mv_transport_lines_z12_13",
            "mv_transport_lines_z14_15",
            "mv_transport_lines_z16_20",
        ],
    ),
}


def check_mv_freshness():
    """Check that key materialized views exist and are being refreshed."""
    result = {
        "name": "mv_freshness",
        "status": "ok",
        "message": "",
        "details": {"groups": {}},
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }

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
        return result

    cur = conn.cursor()

    # Get list of existing materialized views
    cur.execute("SELECT matviewname FROM pg_matviews WHERE schemaname = 'public'")
    existing_mvs = {row[0] for row in cur.fetchall()}

    # Check row counts and last analyze times for MVs via pg_stat_user_tables.
    # REFRESH MATERIALIZED VIEW triggers auto-analyze, so last_autoanalyze
    # is a good proxy for "last refreshed".
    cur.execute("""
        SELECT relname, n_live_tup, last_autoanalyze, last_analyze
        FROM pg_stat_user_tables
        WHERE schemaname = 'public'
          AND relname LIKE 'mv_%%'
    """)
    mv_stats = {}
    for row in cur.fetchall():
        name, n_rows, last_autoanalyze, last_analyze = row
        # Use whichever is more recent
        last_refreshed = max(
            filter(None, [last_autoanalyze, last_analyze]),
            default=None,
        )
        mv_stats[name] = {
            "n_rows": n_rows,
            "last_refreshed": last_refreshed,
        }

    cur.close()
    conn.close()

    missing_views = []
    stale_views = []
    empty_views = []
    now = datetime.now(timezone.utc)

    for group_name, (max_stale, views) in MV_GROUPS.items():
        group_result = {"views": [], "status": "ok"}

        for view_name in views:
            view_info = {"name": view_name, "status": "ok"}

            if view_name not in existing_mvs:
                view_info["status"] = "critical"
                view_info["message"] = "View does not exist"
                missing_views.append(view_name)
            elif view_name in mv_stats:
                stats = mv_stats[view_name]
                view_info["n_rows"] = stats["n_rows"]

                if stats["n_rows"] == 0:
                    view_info["status"] = "warning"
                    view_info["message"] = "View is empty (0 rows)"
                    empty_views.append(view_name)

                if stats["last_refreshed"]:
                    last_ref = stats["last_refreshed"]
                    if last_ref.tzinfo is None:
                        last_ref = last_ref.replace(tzinfo=timezone.utc)
                    age_seconds = (now - last_ref).total_seconds()
                    view_info["last_refreshed"] = last_ref.isoformat()
                    view_info["age_seconds"] = round(age_seconds)

                    if age_seconds > max_stale:
                        view_info["status"] = "warning"
                        view_info["message"] = (
                            f"Stale: last refreshed {round(age_seconds / 60, 1)} min ago "
                            f"(threshold: {max_stale // 60} min)"
                        )
                        stale_views.append(view_name)
                else:
                    view_info["last_refreshed"] = None
                    view_info["message"] = "No analyze timestamp available"
            else:
                view_info["message"] = "No stats available"

            group_result["views"].append(view_info)

        if any(v["status"] == "critical" for v in group_result["views"]):
            group_result["status"] = "critical"
        elif any(v["status"] == "warning" for v in group_result["views"]):
            group_result["status"] = "warning"

        result["details"]["groups"][group_name] = group_result

    # Overall status
    if missing_views:
        result["status"] = "critical"
        result["message"] = f"Missing views: {', '.join(missing_views[:5])}"
    elif stale_views:
        result["status"] = "warning"
        result["message"] = f"Stale views: {', '.join(stale_views[:5])}"
    elif empty_views:
        result["status"] = "warning"
        result["message"] = f"Empty views: {', '.join(empty_views[:5])}"
    else:
        total = sum(len(v) for _, v in MV_GROUPS.values())
        result["message"] = f"All {total} monitored materialized views are healthy"

    return result
