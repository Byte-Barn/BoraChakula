#!/usr/bin/env python3
"""Build and install the HarvestLink APEX app from its blueprint.

Pipeline (all through the database, no App Builder session needed):
  apex/harvestlink-blueprint.md
    -> APEX_GENDEV.PROCESS_BLUEPRINT        (validates, generates APEXlang)
    -> apex/apexlang/                        (generated source, kept in git)
    -> SQLcl "apex validate" + "apex import"  (installs into the workspace)

APEX 26.1 cannot import APEXlang through APEX_APPLICATION_INSTALL, so the
import step uses SQLcl 26.x (set SQLCL or install it at ~/.local/opt/sqlcl).

Secrets come from the environment: HL_SCHEMA_PASSWORD, HL_WALLET_PASSWORD.

Examples:
  python scripts/install_app.py --wallet infra/.wallet/wallet.zip --check-only
  python scripts/install_app.py --wallet infra/.wallet/wallet.zip --app-id 100
"""
import argparse
import io
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import oracledb

REPO = Path(__file__).resolve().parent.parent
BLUEPRINT = REPO / "apex" / "harvestlink-blueprint.md"
APEXLANG_DIR = REPO / "apex" / "apexlang"
WORKSPACE = "HARVESTLINK"

GENERATE = """
begin
  apex_gendev.process_blueprint(
    p_blueprint    => :blueprint,
    p_parsing_log  => :parsing_log,
    p_apexlang_zip => :apexlang_zip);
end;"""

SQLCL = Path(os.environ.get("SQLCL", Path.home() / ".local/opt/sqlcl/bin/sql"))


def env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing environment variable {name}")
    return value


def service_name(wallet):
    with zipfile.ZipFile(wallet) as z:
        tns = z.read("tnsnames.ora").decode()
    return re.search(r"^(\w+_low)\s*=", tns, re.M | re.I).group(1)


def connect(wallet, wallet_dir):
    with zipfile.ZipFile(wallet) as z:
        z.extractall(wallet_dir)
    return oracledb.connect(
        user=WORKSPACE, password=env("HL_SCHEMA_PASSWORD"), dsn=service_name(wallet),
        config_dir=wallet_dir, wallet_location=wallet_dir,
        wallet_password=env("HL_WALLET_PASSWORD"), tcp_connect_timeout=30, retry_count=3,
    )


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--wallet", required=True, help="Path to the ADB client wallet zip")
    p.add_argument("--app-id", type=int, default=100)
    p.add_argument("--check-only", action="store_true", help="Validate and generate, do not install")
    args = p.parse_args()

    oracledb.defaults.fetch_lobs = False
    with tempfile.TemporaryDirectory() as wallet_dir, connect(args.wallet, wallet_dir) as conn:
        cur = conn.cursor()
        log = cur.var(oracledb.DB_TYPE_CLOB)
        apexlang = cur.var(oracledb.DB_TYPE_BLOB)
        cur.execute(GENERATE, blueprint=BLUEPRINT.read_text(), parsing_log=log, apexlang_zip=apexlang)

        log_text = log.getvalue().read() if log.getvalue() else None
        if log_text:
            print(log_text)
            sys.exit("Blueprint rejected; see parsing log above")

        zip_bytes = apexlang.getvalue().read()
        shutil.rmtree(APEXLANG_DIR, ignore_errors=True)
        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as z:
            z.extractall(APEXLANG_DIR)
            print(f"Generated {len(z.namelist())} APEXlang files in {APEXLANG_DIR.relative_to(REPO)}")

    if args.check_only:
        return

    # The password is sent on stdin so it never appears in the process list
    script = "\n".join([
        f"set cloudconfig {Path(args.wallet).resolve()}",
        f'connect {WORKSPACE}/"{env("HL_SCHEMA_PASSWORD")}"@{service_name(args.wallet)}',
        "whenever sqlerror exit failure",
        f"apex validate -input {APEXLANG_DIR} -workspace {WORKSPACE}",
        f"apex import -input {APEXLANG_DIR} -workspace {WORKSPACE} -schema {WORKSPACE} -id {args.app_id}",
        "exit",
    ])
    result = subprocess.run([str(SQLCL), "-S", "/nolog"], input=script, text=True,
                            capture_output=True)
    output = re.sub(r"\x1b\[[0-9;]*m", "", result.stdout + result.stderr).strip()
    print(output)
    if result.returncode != 0 or "Import successful" not in output:
        sys.exit("SQLcl import failed")

    with tempfile.TemporaryDirectory() as wallet_dir, connect(args.wallet, wallet_dir) as conn:
        cur = conn.cursor()
        cur.execute("""select application_name, pages from apex_applications
                        where workspace = :w and application_id = :a""", w=WORKSPACE, a=args.app_id)
        name, pages = cur.fetchone()
        print(f"Installed app {args.app_id} '{name}' with {pages} pages")


if __name__ == "__main__":
    main()
