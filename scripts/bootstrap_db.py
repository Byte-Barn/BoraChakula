#!/usr/bin/env python3
"""Bootstrap HarvestLink on an Autonomous AI Database.

Steps (each can be skipped):
  1. As ADMIN: create the HARVESTLINK schema user.
  2. As ADMIN: create the HARVESTLINK APEX workspace, a developer login, a
     judge login (HL_DEMO_USER) and buyer/farmer/ops demo logins
     (HL_ROLE_DEMO_PASSWORD).
  3. As HARVESTLINK: install db/01..12 (12 only where APEX is installed) (optionally dropping existing objects).

Secrets are read from the environment, never from arguments:
  HL_ADMIN_PASSWORD, HL_WALLET_PASSWORD, HL_SCHEMA_PASSWORD,
  HL_APEX_USER, HL_APEX_PASSWORD, HL_APEX_EMAIL, optional HL_DEMO_USER, HL_DEMO_PASSWORD,
  optional HL_ROLE_DEMO_PASSWORD (BUYER_DEMO, FARMER_DEMO, OPS_DEMO logins)

Examples:
  # Cloud (after terraform apply)
  python scripts/bootstrap_db.py --wallet infra/.wallet/wallet.zip
  # Local Oracle Free container (no APEX), schema user already exists
  python scripts/bootstrap_db.py --dsn localhost/FREEPDB1 --skip-user --skip-apex --reset
"""
import argparse
import os
import re
import sys
import tempfile
import zipfile
from pathlib import Path

import oracledb

REPO = Path(__file__).resolve().parent.parent
SQL_FILES = ["01_schema.sql", "02_match_pkg.sql", "03_views.sql", "04_seed.sql", "05_auto_match.sql",
             "06_agreements.sql", "07_api.sql",
             "08_demo.sql", "09_auth.sql",
             "10_alloc.sql", "11_routes.sql",
             "12_apex_error.sql"]  # last one only where APEX is installed
SCHEMA = "HARVESTLINK"
PLSQL_START = re.compile(
    r"^\s*(create\s+or\s+replace\s+(package|trigger|procedure|function|type)|begin|declare)\b", re.I)


def env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing environment variable {name}")
    return value


def split_sql(text):
    """Split a SQL*Plus-style script into statements.

    PL/SQL units run until a line containing only '/'; plain SQL ends at a
    line whose last character is ';'. Comment-only lines between statements
    are dropped.
    """
    statements, buf, plsql = [], [], False
    for line in text.splitlines():
        stripped = line.strip()
        if not buf:
            if not stripped or stripped.startswith("--"):
                continue
            plsql = bool(PLSQL_START.match(line))
        if plsql:
            if stripped == "/":
                statements.append("\n".join(buf))
                buf = []
            else:
                buf.append(line)
        else:
            buf.append(line)
            if stripped.endswith(";"):
                statements.append("\n".join(buf).rstrip().rstrip(";"))
                buf = []
    if "".join(buf).strip():
        raise ValueError("Unterminated statement at end of script")
    return statements


def connect(user, password, args, wallet_dir):
    if args.wallet:
        return oracledb.connect(
            user=user, password=password, dsn=args.service,
            config_dir=wallet_dir, wallet_location=wallet_dir,
            wallet_password=env("HL_WALLET_PASSWORD"), tcp_connect_timeout=30, retry_count=3,
        )
    return oracledb.connect(user=user, password=password, dsn=args.dsn, tcp_connect_timeout=30)


def create_schema_user(conn):
    cur = conn.cursor()
    cur.execute("select count(*) from dba_users where username = :u", u=SCHEMA)
    if cur.fetchone()[0]:
        print(f"User {SCHEMA} exists, skipping")
        return
    # Password is quoted as an identifier; bind variables are not allowed in DDL
    cur.execute(f'create user {SCHEMA} identified by "{env("HL_SCHEMA_PASSWORD")}" '
                f"quota unlimited on data")
    cur.execute(f"grant create session, create table, create view, create sequence, "
                f"create procedure, create trigger, create type, create synonym, "
                f"create job to {SCHEMA}")
    print(f"Created user {SCHEMA}")


def create_workspace(conn):
    cur = conn.cursor()
    cur.execute("select count(*) from apex_workspaces where workspace = :w", w=SCHEMA)
    if cur.fetchone()[0]:
        print(f"Workspace {SCHEMA} exists, skipping")
        return
    cur.execute("""
        begin
          apex_instance_admin.add_workspace(
            p_workspace      => :ws,
            p_primary_schema => :ws);
          apex_util.set_workspace(p_workspace => :ws);
          apex_util.create_user(
            p_user_name                    => :usr,
            p_web_password                 => :pwd,
            p_email_address                => :email,
            p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
            p_change_password_on_first_use => 'N');
          commit;
        end;""",
        ws=SCHEMA, usr=env("HL_APEX_USER").upper(), pwd=env("HL_APEX_PASSWORD"),
        email=env("HL_APEX_EMAIL"))
    print(f"Created APEX workspace {SCHEMA} with developer {env('HL_APEX_USER').upper()}")


ROLE_DEMO_USERS = ["BUYER_DEMO", "FARMER_DEMO", "OPS_DEMO"]  # roles mapped in db/09_auth.sql


def create_end_user(conn, user, password):
    """APEX login with no builder access; skipped if it already exists."""
    cur = conn.cursor()
    cur.execute("""select count(*) from apex_workspace_apex_users
                    where workspace_name = :w and user_name = :u""", w=SCHEMA, u=user)
    if cur.fetchone()[0]:
        print(f"APEX user {user} exists, skipping")
        return
    cur.execute("""
        begin
          apex_util.set_workspace(p_workspace => :ws);
          apex_util.create_user(
            p_user_name                    => :usr,
            p_web_password                 => :pwd,
            p_developer_privs              => null,
            p_change_password_on_first_use => 'N');
          commit;
        end;""", ws=SCHEMA, usr=user, pwd=password)
    print(f"Created APEX end user {user}")


def create_end_users(conn):
    """Judge login (HL_DEMO_USER) and the buyer/farmer/ops demo logins
    (HL_ROLE_DEMO_PASSWORD); each is skipped when its variable is unset."""
    if os.environ.get("HL_DEMO_USER"):
        create_end_user(conn, env("HL_DEMO_USER").upper(), env("HL_DEMO_PASSWORD"))
    if os.environ.get("HL_ROLE_DEMO_PASSWORD"):
        for user in ROLE_DEMO_USERS:
            create_end_user(conn, user, env("HL_ROLE_DEMO_PASSWORD"))


def register_developer(conn):
    """The workspace developer signs in to the app as operations."""
    if not os.environ.get("HL_APEX_USER"):
        return
    cur = conn.cursor()
    cur.execute("begin hl_auth.register_user(:u, 'OPS'); commit; end;", u=env("HL_APEX_USER"))


def install(conn, reset):
    cur = conn.cursor()
    if reset:
        for stmt in split_sql((REPO / "db" / "uninstall.sql").read_text()):
            try:
                cur.execute(stmt)
            except oracledb.DatabaseError as e:
                # Already gone: not installed yet, or an earlier run stopped part-way
                if e.args[0].code not in (942, 2289, 4043, 4080):
                    raise
        print("Dropped existing objects")
    else:
        cur.execute("select count(*) from user_tables where table_name = 'HL_SETTINGS'")
        if cur.fetchone()[0]:
            print("HarvestLink objects already installed; use --reset to reinstall")
            return

    # Autonomous Database exposes APEX packages to schemas only as public synonyms
    cur.execute("select count(*) from all_objects where object_name = 'APEX_ERROR'")
    has_apex = cur.fetchone()[0] > 0
    for name in SQL_FILES:
        if name == "12_apex_error.sql" and not has_apex:
            print(f"Skipped {name} (no APEX in this database)")
            continue
        statements = split_sql((REPO / "db" / name).read_text())
        for stmt in statements:
            cur.execute(stmt)
        print(f"Ran {name} ({len(statements)} statements)")

    # The seed's ALTER TABLE statements leave dependent views needing recompilation
    cur.execute("begin dbms_utility.compile_schema(schema => user, compile_all => false); end;")
    cur.execute("select object_name from user_objects where status = 'INVALID'")
    invalid = [r[0] for r in cur]
    if invalid:
        sys.exit(f"Invalid objects after install: {', '.join(invalid)}")
    cur.execute("select total_matched_kg, farmers_matched, demands_served from hl_impact_v")
    kg, farmers, demands = cur.fetchone()
    print(f"Check: {kg} kg matched, {farmers} farmers, {demands} demands")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--wallet", help="Path to the ADB client wallet zip")
    target.add_argument("--dsn", help="Plain connect string, e.g. localhost/FREEPDB1")
    p.add_argument("--service", help="TNS alias in the wallet (default: the *_low alias)")
    p.add_argument("--skip-user", action="store_true")
    p.add_argument("--skip-apex", action="store_true")
    p.add_argument("--skip-install", action="store_true")
    p.add_argument("--reset", action="store_true", help="Drop and reinstall HarvestLink objects")
    args = p.parse_args()

    with tempfile.TemporaryDirectory() as wallet_dir:
        if args.wallet:
            with zipfile.ZipFile(args.wallet) as z:
                z.extractall(wallet_dir)
            if not args.service:
                tns = (Path(wallet_dir) / "tnsnames.ora").read_text()
                args.service = re.search(r"^(\w+_low)\s*=", tns, re.M | re.I).group(1)
            print(f"Connecting to {args.service}")

        if not (args.skip_user and args.skip_apex):
            with connect("ADMIN", env("HL_ADMIN_PASSWORD"), args, wallet_dir) as admin:
                if not args.skip_user:
                    create_schema_user(admin)
                if not args.skip_apex:
                    create_workspace(admin)
                    create_end_users(admin)

        if not args.skip_install:
            with connect(SCHEMA, env("HL_SCHEMA_PASSWORD"), args, wallet_dir) as conn:
                install(conn, args.reset)
                register_developer(conn)


if __name__ == "__main__":
    main()
