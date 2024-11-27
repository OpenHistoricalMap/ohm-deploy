# Tiler Seed CronJob

This chart’s CronJob is designed to execute scheduled tasks for seeding cache. It runs the script image/tiler-cache/seed.py, primarily targeting zoom levels 7 to 10. Additionally, the job seeds tiles for zoom levels 0 to 6 every 24 hours to ensure that lower zoom levels remain updated, minimizing latency for users navigating the map.
