#!/usr/bin/env python3
"""Best-effort SQLite snapshots to an S3-compatible bucket (including R2)."""

import os
import shutil
import signal
import sqlite3
import tempfile
import time
from pathlib import Path


DB_PATH = Path(os.environ.get("DATABASE_FILE", "/data/omnigent.db"))
INTERVAL = max(60, int(os.environ.get("STATE_BACKUP_INTERVAL_SEC", "300")))


def configured() -> bool:
    return all(
        os.environ.get(name)
        for name in (
            "STATE_BACKUP_S3_ENDPOINT",
            "STATE_BACKUP_S3_BUCKET",
            "STATE_BACKUP_ACCESS_KEY_ID",
            "STATE_BACKUP_SECRET_ACCESS_KEY",
        )
    )


def client():
    import boto3

    return boto3.client(
        "s3",
        endpoint_url=os.environ["STATE_BACKUP_S3_ENDPOINT"],
        region_name=os.environ.get("STATE_BACKUP_S3_REGION", "auto"),
        aws_access_key_id=os.environ["STATE_BACKUP_ACCESS_KEY_ID"],
        aws_secret_access_key=os.environ["STATE_BACKUP_SECRET_ACCESS_KEY"],
    )


def key() -> str:
    return os.environ.get("STATE_BACKUP_S3_KEY", "omnigent/omnigent.db")


def restore(s3) -> None:
    if DB_PATH.exists() or not configured():
        return
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=DB_PATH.parent, suffix=".restore", delete=False) as f:
        temp = Path(f.name)
    try:
        s3.download_file(os.environ["STATE_BACKUP_S3_BUCKET"], key(), str(temp))
        with sqlite3.connect(temp) as db:
            db.execute("PRAGMA integrity_check").fetchone()
        shutil.move(temp, DB_PATH)
        print(f"Restored SQLite state from {key()}", flush=True)
    except Exception as exc:
        temp.unlink(missing_ok=True)
        if getattr(exc, "response", {}).get("Error", {}).get("Code") not in {"404", "NoSuchKey"}:
            print(f"SQLite restore skipped: {exc}", flush=True)


def snapshot(s3) -> None:
    if not DB_PATH.exists():
        return
    with tempfile.NamedTemporaryFile(dir=DB_PATH.parent, suffix=".snapshot", delete=False) as f:
        temp = Path(f.name)
    try:
        with sqlite3.connect(DB_PATH) as source, sqlite3.connect(temp) as target:
            source.backup(target)
        s3.upload_file(str(temp), os.environ["STATE_BACKUP_S3_BUCKET"], key())
        print(f"Backed up SQLite state to {key()}", flush=True)
    except Exception as exc:
        print(f"SQLite backup failed: {exc}", flush=True)
    finally:
        temp.unlink(missing_ok=True)


def main() -> None:
    if not configured():
        print("SQLite state backup disabled; configure STATE_BACKUP_S3_* to enable", flush=True)
        return
    s3 = client()
    restore(s3)
    stop = False

    def request_stop(_signum, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    while not stop:
        snapshot(s3)
        for _ in range(INTERVAL):
            if stop:
                break
            time.sleep(1)


if __name__ == "__main__":
    main()
