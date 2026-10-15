#!/usr/bin/env python3
"""Bootstrap HarvestLink on an Autonomous AI Database.

Steps (each can be skipped):
  1. As ADMIN: create the HARVESTLINK schema user.
  2. As ADMIN: create the HARVESTLINK APEX workspace, a developer login, a
     judge login (HL_DEMO_USER) and buyer/farmer/ops demo logins
     (HL_ROLE_DEMO_PASSWORD).
  3. As HARVESTLINK: install db/01..15 (12 only where APEX is installed) (optionally dropping existing objects).
     --reset keeps registered accounts with their farmer and buyer records,
     harvests and demands, the email settings and Select AI's on/off switch.
  4. Sets the passwords of the judge, demo and developer logins (HL_ACCOUNT_API).

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
             "10_alloc.sql", "11_routes.sql", "13_farmer_api.sql", "14_ai.sql", "15_accounts.sql",
             "12_apex_error.sql"]  # 12 only where APEX is installed
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
        grant_crypto(cur)
        return
    # Password is quoted as an identifier; bind variables are not allowed in DDL
    cur.execute(f'create user {SCHEMA} identified by "{env("HL_SCHEMA_PASSWORD")}" '
                f"quota unlimited on data")
    cur.execute(f"grant create session, create table, create view, create sequence, "
                f"create procedure, create trigger, create type, create synonym, "
                f"create job to {SCHEMA}")
    print(f"Created user {SCHEMA}")
    grant_crypto(cur)


def grant_crypto(cur):
    """Password hashing and sign-in tokens (db/15_accounts.sql) use DBMS_CRYPTO."""
    cur.execute(f"grant execute on sys.dbms_crypto to {SCHEMA}")


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


def set_login_passwords(conn):
    """The app signs in with HL_ACCOUNT_API, so the judge, demo and developer
    logins get the passwords their APEX accounts have (each only when its
    variables are set). These predate the password rules, so they skip them."""
    logins = []
    if os.environ.get("HL_DEMO_USER") and os.environ.get("HL_DEMO_PASSWORD"):
        logins.append((env("HL_DEMO_USER"), env("HL_DEMO_PASSWORD")))
    if os.environ.get("HL_ROLE_DEMO_PASSWORD"):
        logins += [(u, env("HL_ROLE_DEMO_PASSWORD")) for u in ROLE_DEMO_USERS]
    if os.environ.get("HL_APEX_USER") and os.environ.get("HL_APEX_PASSWORD"):
        logins.append((env("HL_APEX_USER"), env("HL_APEX_PASSWORD")))
    cur = conn.cursor()
    for user, password in logins:
        cur.execute("begin hl_account_api.set_password(:u, :p, p_check => false); end;", u=user, p=password)
    conn.commit()
    if logins:
        print(f"Set sign-in passwords for {', '.join(u.upper() for u, _ in logins)}")


def register_developer(conn):
    """The workspace developer signs in to the app as operations."""
    if not os.environ.get("HL_APEX_USER"):
        return
    cur = conn.cursor()
    cur.execute("begin hl_auth.register_user(:u, 'OPS'); commit; end;", u=env("HL_APEX_USER"))


def ai_enabled(cur):
    """AI_ENABLED before a reset, or None when HarvestLink isn't installed."""
    try:
        cur.execute("select max(setting_value) from hl_settings where setting_key = 'AI_ENABLED'")
        return cur.fetchone()[0]
    except oracledb.DatabaseError:
        return None


def ai_setup_exists(cur):
    """True when the Select AI profile and credential survive a reset.

    enable_select_ai.py creates them with DBMS_CLOUD and DBMS_CLOUD_AI, outside
    the objects uninstall.sql drops. Databases without Select AI (Oracle
    Database Free) have neither view, which counts as not set up.
    """
    try:
        cur.execute("select count(*) from user_cloud_ai_profiles where profile_name = 'HL_EXPLAIN'")
        profiles = cur.fetchone()[0]
        cur.execute("select count(*) from user_credentials where credential_name = 'HL_AI_CRED'")
        return profiles > 0 and cur.fetchone()[0] > 0
    except oracledb.DatabaseError:
        return False


def columns(cur, table):
    cur.execute("select column_name from user_tab_columns where table_name = :t order by column_id", t=table)
    return [r[0] for r in cur]


def select_rows(cur, table, where=""):
    cols = columns(cur, table)
    if not cols:
        return None
    cur.execute(f"select {', '.join(cols)} from {table} {where}")
    return {"cols": cols, "rows": [dict(zip(cols, r)) for r in cur]}


def snapshot(cur):
    """What --reset keeps: accounts, registered parties and their harvests and
    demands, and the email settings. Matches, routes and the ledger are not
    kept; registered demands are matched again after the restore."""
    snap = {}
    try:
        snap["users"] = select_rows(cur, "HL_APP_USERS")
    except oracledb.DatabaseError:
        return {}  # not installed yet
    # Before IS_DEMO existed, every farmer and buyer was demo data
    registered = "where is_demo = 'N'"
    snap["farmers"] = (select_rows(cur, "HL_FARMERS", registered)
                       if "IS_DEMO" in columns(cur, "HL_FARMERS") else None)
    snap["buyers"] = (select_rows(cur, "HL_BUYERS", registered)
                      if "IS_DEMO" in columns(cur, "HL_BUYERS") else None)
    if snap["farmers"]:
        snap["harvests"] = select_rows(cur, "HL_HARVESTS",
            "where farmer_id in (select farmer_id from hl_farmers where is_demo = 'N')")
    if snap["buyers"]:
        snap["demands"] = select_rows(cur, "HL_DEMANDS",
            "where buyer_id in (select buyer_id from hl_buyers where is_demo = 'N')")
    if columns(cur, "HL_TEXT_SETTINGS"):
        snap["text"] = select_rows(cur, "HL_TEXT_SETTINGS")
        cur.execute("select max(setting_value) from hl_settings where setting_key = 'MAIL_ENABLED'")
        snap["mail_enabled"] = cur.fetchone()[0]
    counts = {k: len(v["rows"]) for k, v in snap.items() if isinstance(v, dict)}
    print(f"Keeping across the reset: {counts}")
    return snap


def insert_row(cur, table, row, cols, id_col=None):
    """Inserts the columns the new table still has; returns the new ID."""
    names = [c for c in cols if c in row and c != id_col]
    sql = (f"insert into {table} ({', '.join(names)}) values ({', '.join(':' + str(i + 1) for i in range(len(names)))})")
    values = [row[c] for c in names]
    if id_col:
        new_id = cur.var(oracledb.NUMBER)
        cur.execute(sql + f" returning {id_col} into :{len(names) + 1}", values + [new_id])
        return int(new_id.getvalue()[0])
    cur.execute(sql, values)
    return None


def restore(cur, snap):
    if not snap:
        return
    cur.execute("begin hl_match_pkg.g_auto_match := false; end;")
    farmer_ids, buyer_ids, demand_ids = {}, {}, []
    for key, table, id_col, ids in (("farmers", "HL_FARMERS", "FARMER_ID", farmer_ids),
                                    ("buyers", "HL_BUYERS", "BUYER_ID", buyer_ids)):
        data = snap.get(key)
        if data:
            cols = columns(cur, table)
            for row in data["rows"]:
                ids[row[id_col]] = insert_row(cur, table, row, cols, id_col)
    # Their matches are gone, so promised supply and part-filled demand start open again
    if snap.get("harvests"):
        cols = columns(cur, "HL_HARVESTS")
        for row in snap["harvests"]["rows"]:
            row["FARMER_ID"] = farmer_ids[row["FARMER_ID"]]
            if row.get("STATUS") in ("PARTIAL", "COMMITTED"):
                row["STATUS"] = "OPEN"
            insert_row(cur, "HL_HARVESTS", row, cols, "HARVEST_ID")
    if snap.get("demands"):
        cols = columns(cur, "HL_DEMANDS")
        for row in snap["demands"]["rows"]:
            row["BUYER_ID"] = buyer_ids[row["BUYER_ID"]]
            if row.get("STATUS") in ("PARTIAL", "FILLED"):
                row["STATUS"] = "OPEN"
            new_id = insert_row(cur, "HL_DEMANDS", row, cols, "DEMAND_ID")
            if row.get("STATUS") == "OPEN":
                demand_ids.append(new_id)
    if snap.get("users"):
        cols = columns(cur, "HL_APP_USERS")
        for row in snap["users"]["rows"]:
            # Demo logins are linked by name; registered ones follow their records' new IDs
            if row.get("FARMER_ID") is not None:
                row["FARMER_ID"] = farmer_ids.get(row["FARMER_ID"])
            if row.get("BUYER_ID") is not None:
                row["BUYER_ID"] = buyer_ids.get(row["BUYER_ID"])
            cur.execute("delete from hl_app_users where user_name = :u", u=row["USER_NAME"])
            insert_row(cur, "HL_APP_USERS", row, cols)
    if snap.get("text"):
        for row in snap["text"]["rows"]:
            cur.execute("update hl_text_settings set setting_value = :v where setting_key = :k",
                        v=row["SETTING_VALUE"], k=row["SETTING_KEY"])
    if snap.get("mail_enabled") is not None:
        cur.execute("update hl_settings set setting_value = :v where setting_key = 'MAIL_ENABLED'",
                    v=snap["mail_enabled"])
    cur.execute("begin hl_match_pkg.g_auto_match := true; end;")
    for demand_id in demand_ids:
        cur.execute("begin hl_match_pkg.run_matching(:d); end;", d=demand_id)
    cur.connection.commit()
    print(f"Restored {len(farmer_ids)} farmers, {len(buyer_ids)} buyers, "
          f"{len(snap['users']['rows']) if snap.get('users') else 0} accounts")


def install(conn, reset):
    cur = conn.cursor()
    ai_before = ai_enabled(cur) if reset else None
    kept = snapshot(cur) if reset else {}
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
    restore(cur, kept)
    cur.execute("select total_matched_kg, farmers_matched, demands_served from hl_impact_v")
    kg, farmers, demands = cur.fetchone()
    print(f"Check: {kg} kg matched, {farmers} farmers, {demands} demands")

    # 14_ai.sql installs AI_ENABLED = 0; keep Select AI on across a reset when it
    # was on and its profile and credential are still there (issue #28)
    if ai_before == 1:
        if ai_setup_exists(cur):
            cur.execute("begin hl_ai.set_enabled(true); commit; end;")
            print("Select AI kept on (HL_EXPLAIN profile and HL_AI_CRED credential still present)")
        else:
            print("Select AI was on but its profile or credential is gone; run scripts/enable_select_ai.py")


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
                set_login_passwords(conn)


if __name__ == "__main__":
    main()
