"""Post comments on OHM changesets when elements have tiler-incompatible tags.

This module collects commentable elements (elements with tiler-relevant tags
that imposm cannot import) and posts a single comment per changeset explaining
which elements won't appear in the tiler and why.

Comments are posted via the OHM API: POST /api/0.6/changeset/{id}/comment
Requires OHM_COMMENT_USER and OHM_COMMENT_PASSWORD in config.

Already-commented changesets are tracked in the retry store to avoid duplicates.
"""

import logging

import requests

from config import Config

logger = logging.getLogger(__name__)

OHM_BASE = "https://www.openhistoricalmap.org"


def _build_comment(changeset_id, commentable_elements):
    """Build a single changeset comment from all commentable elements.

    Groups issues by element and produces a readable comment for the mapper.
    """
    lines = [
        "Hi! The OHM tiler monitor detected that some elements in this changeset "
        "won't appear on the map because they don't match the tiler's import rules. "
        "Here's a summary:\n"
    ]

    for elem in commentable_elements:
        etype = elem.get("type", "?")
        oid = elem.get("osm_id", "?")
        reason = elem.get("skip_reason", "unknown reason")
        url = f"{OHM_BASE}/{etype}/{oid}"
        lines.append(f"- {etype} {oid} ({url}): {reason}")

    lines.append(
        "\nThese elements have tags the tiler recognizes (e.g. highway, building, natural) "
        "but couldn't be imported due to geometry or tagging issues. "
        "If you'd like them to appear on the map, please check the details above."
    )

    return "\n".join(lines)


def _get_auth_session():
    """Create an authenticated session for the OHM API using basic auth."""
    user = Config.OHM_COMMENT_USER
    password = Config.OHM_COMMENT_PASSWORD
    if not user or not password:
        return None

    session = requests.Session()
    session.auth = (user, password)
    session.headers.update({"Content-Type": "application/x-www-form-urlencoded"})
    return session


def post_changeset_comment(changeset_id, commentable_elements, commented_store=None):
    """Post a comment on a changeset listing elements that won't appear in the tiler.

    Args:
        changeset_id: The OHM changeset ID
        commentable_elements: List of element dicts with skip_reason and commentable=True
        commented_store: Optional set of already-commented changeset IDs (to avoid duplicates)

    Returns:
        True if comment was posted, False otherwise.
    """
    if not commentable_elements:
        return False

    # Skip if already commented
    if commented_store is not None and changeset_id in commented_store:
        logger.debug("Changeset %s already commented, skipping", changeset_id)
        return False

    session = _get_auth_session()
    if not session:
        logger.warning(
            "Cannot comment on changeset %s: OHM_COMMENT_USER/OHM_COMMENT_PASSWORD not configured",
            changeset_id,
        )
        return False

    comment_text = _build_comment(changeset_id, commentable_elements)

    try:
        url = f"{Config.OHM_API_BASE}/changeset/{changeset_id}/comment"
        resp = session.post(url, data={"text": comment_text}, timeout=30)

        if resp.status_code == 200:
            logger.info(
                "Posted comment on changeset %s (%d elements with issues)",
                changeset_id,
                len(commentable_elements),
            )
            if commented_store is not None:
                commented_store.add(changeset_id)
            return True
        else:
            logger.error(
                "Failed to comment on changeset %s: HTTP %d — %s",
                changeset_id,
                resp.status_code,
                resp.text[:200],
            )
            return False

    except requests.RequestException as e:
        logger.error("Error posting comment on changeset %s: %s", changeset_id, e)
        return False


def process_changeset_comments(changeset_results, commented_store=None):
    """Process pipeline check results and comment on changesets with issues.

    Args:
        changeset_results: List of changeset result dicts from check_pipeline(),
            each containing "changeset_id" and "db_check" with "commentable_elements".
        commented_store: Set of already-commented changeset IDs.

    Returns:
        Number of changesets commented on.
    """
    if not Config.OHM_COMMENT_USER:
        return 0

    commented_count = 0
    for cs_result in changeset_results:
        cs_id = cs_result.get("changeset_id")
        db_check = cs_result.get("db_check", {})
        commentable = db_check.get("commentable_elements", [])

        if commentable and cs_id:
            if post_changeset_comment(cs_id, commentable, commented_store):
                commented_count += 1

    return commented_count
