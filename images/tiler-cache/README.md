# Tiler seed script

Tiler seeding is a group of scripts aimed at generating tile cache for a specific zoom level, for example, from 1 to 7. The script will receive a GeoJSON of all the areas where tile cache generation is required for OHM tiles. This approach aims to reduce latency when a user starts interacting with OHM tiles.


# Tiler purge script

Script that reads an AWS SQS queue and creates a container to purge and seed the tiler cache for specific imposm expired files.
