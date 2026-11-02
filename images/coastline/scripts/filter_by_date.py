"""Keep only the coastline ways that exist on a given date.

osmcoastline does not read start_date/end_date, so coastlines from different
periods overlap and break the polygons. This writes all nodes and only the ways
where start_date <= DATE < end_date. A missing start_date or end_date means open.
Ways with a date we can not parse are kept and counted.

Usage: python3 -I filter_by_date.py IN.pbf OUT.pbf YYYY-MM-DD
"""
import re
import sys

import osmium

DATE_RE = re.compile(r"^\s*(-?\d{1,4})(?:-(\d{2}))?(?:-(\d{2}))?")


def parse(value):
    """'1850', '1850-05', '-0500-01-01' -> (year, month, day). None if not a date."""
    m = DATE_RE.match(value)
    if not m:
        return None
    return (int(m.group(1)), int(m.group(2) or 1), int(m.group(3) or 1))


def main():
    src, dst, date = sys.argv[1], sys.argv[2], parse(sys.argv[3])
    if date is None:
        sys.exit(f"bad date: {sys.argv[3]}")

    kept = dropped = bad = 0
    writer = osmium.SimpleWriter(dst, overwrite=True)
    try:
        for obj in osmium.FileProcessor(src):
            if obj.is_node():
                writer.add_node(obj)
                continue
            if not obj.is_way():
                continue
            start = obj.tags.get("start_date")
            end = obj.tags.get("end_date")
            start_d = parse(start) if start else None
            end_d = parse(end) if end else None
            if (start and start_d is None) or (end and end_d is None):
                bad += 1
            if (start_d and start_d > date) or (end_d and end_d <= date):
                dropped += 1
                continue
            kept += 1
            writer.add_way(obj)
    finally:
        writer.close()

    print(f"coastline ways kept={kept} dropped={dropped} unparsed_dates={bad}")


if __name__ == "__main__":
    main()
