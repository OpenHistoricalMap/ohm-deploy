import os
import re
import requests
import psycopg2
from psycopg2.extras import execute_values
import time
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s - %(levelname)s - %(message)s")
logger = logging.getLogger(__name__)

TAGINFO_URL = "https://taginfo.openhistoricalmap.org/api/4/keys/all"
KEY_REGEX = r"^name:[a-z]{2,3}(-[A-Z][a-z]{3})?((-[a-z]{2,}|x-[a-z]{2,})(-[a-z]{2,})?)?(-([A-Z]{2}|\d{3}))?$"
LANGUAGE_TAG_MIN_USAGE = int(os.getenv("LANGUAGE_TAG_MIN_USAGE", 10))

def get_pg_conn():
    logger.info("Connecting to PostgreSQL...")
    return psycopg2.connect(
        host=os.getenv("POSTGRES_HOST"),
        dbname=os.getenv("POSTGRES_DB"),
        user=os.getenv("POSTGRES_USER"),
        password=os.getenv("POSTGRES_PASSWORD"),
        port=os.getenv("POSTGRES_PORT", 5432)
    )

def ensure_tables(conn):
    logger.info("Ensuring tables exist...")
    with conn.cursor() as cur:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS languages (
                alias TEXT PRIMARY KEY,
                key_name TEXT NOT NULL,
                count INTEGER,
                date_added TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
            CREATE TABLE IF NOT EXISTS languages_hash (
                id SERIAL PRIMARY KEY,
                hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            );
        """)
    conn.commit()
    logger.info("Tables are ready.")

def fetch_languages():
    logger.info("Fetching languages from Taginfo...")
    page = 1
    results = []
    params = {
        "include": "prevalent_values", "sortname": "count_all",
        "sortorder": "desc", "rp": 500, "query": "name:"
    }

    while True:
        logger.info(f"Requesting page {page}...")
        params["page"] = page
        resp = requests.get(TAGINFO_URL, params=params)
        if resp.status_code != 200:
            logger.error(f"Taginfo request failed with status {resp.status_code}")
            break

        data = resp.json().get("data", [])
        if not data:
            logger.info("No more data from Taginfo.")
            break

        for item in data:
            if re.match(KEY_REGEX, item["key"]) and item["count_all"] > LANGUAGE_TAG_MIN_USAGE:
                alias = item["key"].replace(":", "_").replace("-", "_").lower()
                results.append((alias, item["key"], item["count_all"]))

        page += 1

    logger.info(f"Fetched {len(results)} valid language tags.")
    return results

def insert_languages(conn, languages):
    logger.info("Clearing old languages and inserting new ones...")
    with conn.cursor() as cur:
        cur.execute("DELETE FROM languages;")
        query = """
            INSERT INTO languages (alias, key_name, count)
            VALUES %s
            ON CONFLICT (alias) DO UPDATE
            SET count = EXCLUDED.count,
                date_added = CURRENT_TIMESTAMP;
        """
        execute_values(cur, query, languages)
    conn.commit()
    logger.info(f"Replaced with {len(languages)} fresh language entries.")


def insert_languages_hash(conn):
    logger.info("Generating hash of language aliases...")
    start = time.time()

    with conn.cursor() as cur:
        cur.execute("SELECT md5(string_agg(alias, ',' ORDER BY alias)) FROM languages;")
        (lang_hash,) = cur.fetchone()

        logger.info(f"Hash generated: {lang_hash}")
        cur.execute("INSERT INTO languages_hash (hash) VALUES (%s);", (lang_hash,))
        conn.commit()

    end = time.time()
    logger.info(f"Inserted new hash in {end - start:.2f} seconds")

def main():
    try:
        logger.info("Starting language update process")
        conn = get_pg_conn()
        ensure_tables(conn)

        start_fetch = time.time()
        langs = fetch_languages()
        end_fetch = time.time()
        logger.info(f"Language fetch took {end_fetch - start_fetch:.2f} seconds")

        start_insert = time.time()
        insert_languages(conn, langs)
        end_insert = time.time()
        logger.info(f"Language insert/update took {end_insert - start_insert:.2f} seconds")

        insert_languages_hash(conn)
        conn.close()
        logger.info("Process completed successfully.")
    except Exception as e:
        logger.exception(f"Error occurred: {e}")

if __name__ == "__main__":
    main()