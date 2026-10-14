#!/usr/bin/env python3
"""Build and install the HarvestLink APEX app from its blueprint.

Pipeline (all through the database, no App Builder session needed):
  apex/harvestlink-blueprint.md
    -> APEX_GENDEV.PROCESS_BLUEPRINT        (validates, generates APEXlang)
    -> apex/apexlang/                        (generated source, kept in git)
    + apex/theme/harvestlink.css             (HarvestLink styling, added as a static file)
    + error handling function                (hl_apex_error.handle, db/12_apex_error.sql)
    + apex/pages/                            (canvas screens written in APEXlang)
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
THEME_CSS = REPO / "apex" / "theme" / "harvestlink.css"
THEME_ICONS = REPO / "apex" / "theme" / "icons"
PAGES_DIR = REPO / "apex" / "pages"
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


# Files below are written with newline="\n": the APEXlang parser rejects CRLF,
# which text mode writes on Windows.


def apply_theme():
    """Add the HarvestLink stylesheet and app icons to the generated app.

    Blueprints cannot carry CSS, so the file is added as a static application
    file and loaded after Universal Theme's own CSS. The generated icons keep
    their names and are replaced with the HarvestLink mark.
    """
    shared = APEXLANG_DIR / "shared-components"
    for icon in THEME_ICONS.glob("*.png"):
        shutil.copyfile(icon, shared / "static-files" / "icons" / icon.name)
    target = shared / "static-files" / "css" / THEME_CSS.name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(THEME_CSS, target)
    with open(shared / "static-files.apx", "a", newline="\n") as f:
        f.write(f'\nfile "css/{THEME_CSS.name}" (\n    mimeType: text/css\n    charSet: utf-8\n)\n')

    theme = shared / "themes" / "universal-theme" / "theme.apx"
    text = theme.read_text()
    core = "fileUrls: #THEME_FILES#css/Core#MIN#.css?v=#APEX_VERSION#"
    if core not in text:
        sys.exit(f"Unexpected theme CSS block in {theme}; cannot add {THEME_CSS.name}")
    theme.write_text(text.replace(core, (
        "fileUrls: [\n"
        "            #THEME_FILES#css/Core#MIN#.css?v=#APEX_VERSION#\n"
        f"            #APP_FILES#css/{THEME_CSS.name}\n"
        "        ]")), newline="\n")
    print(f"Added {THEME_CSS.relative_to(REPO)} and the HarvestLink icons to the app")


def apply_error_handling():
    """Use HL_APEX_ERROR.HANDLE (db/12_apex_error.sql) as the application's error
    handling function, so backend messages show without ORA- codes."""
    app = APEXLANG_DIR / "application.apx"
    text = app.read_text()
    anchor = "    authentication {"
    if anchor not in text:
        sys.exit(f"Unexpected application definition in {app}; cannot add error handling")
    app.write_text(text.replace(anchor, (
        "    errorHandling {\n"
        "        defaultDisplayLocation: inlineInNotification\n"
        "        errorHandlingFunctionName: hl_apex_error.handle\n"
        "    }\n" + anchor), 1), newline="\n")
    print("Set hl_apex_error.handle as the error handling function")


def apply_frontend_pages():
    """Add the canvas screens in apex/pages/ to the generated app.

    Blueprints only describe table forms and reports, so screens that call the
    backend API (docs/backend-api.md) are written in APEXlang and copied in on
    every build, with their navigation entries (navigation.apx) and lists of
    values (lovs.apx).
    """
    pages = sorted(PAGES_DIR.glob("p*.apx"))
    for page in pages:
        if any((APEXLANG_DIR / "pages").glob(page.name[:6] + "-*.apx")):
            sys.exit(f"{page.name} has the number of a blueprint page; renumber it")
        (APEXLANG_DIR / "pages" / page.name).write_text(
            page.read_text(encoding="utf-8"), encoding="utf-8", newline="\n")

    shared = APEXLANG_DIR / "shared-components"
    with open(shared / "lovs.apx", "a", encoding="utf-8", newline="\n") as f:
        f.write("\n" + (PAGES_DIR / "lovs.apx").read_text(encoding="utf-8"))

    lists = shared / "lists.apx"
    text = lists.read_text(encoding="utf-8")
    anchor = "list navigation-menu (\n    name: Navigation Menu\n"
    if anchor not in text:
        sys.exit(f"Unexpected navigation menu in {lists}; cannot add the canvas screens")
    entries = (PAGES_DIR / "navigation.apx").read_text(encoding="utf-8")
    lists.write_text(text.replace(anchor, anchor + "    \n" + entries, 1), encoding="utf-8", newline="\n")

    # APEX enforces an app-wide "must not be public user" scheme even on public
    # pages, which would block the public landing page. Every other page carries
    # the check itself (verified here), so the app-wide one is dropped.
    for page in (APEXLANG_DIR / "pages").glob("*.apx"):
        source = page.read_text(encoding="utf-8")
        if "authentication: public" not in source and "authorizationScheme:" not in source:
            sys.exit(f"{page.name} has no authorization scheme; cannot drop the app-wide one")
    app = APEXLANG_DIR / "application.apx"
    text = app.read_text(encoding="utf-8")
    block = "    authorization {\n        scheme: mustNotBePublicUser\n    }\n"
    if block not in text:
        sys.exit(f"Unexpected authorization block in {app}; cannot open the public landing page")
    text = text.replace(block, "", 1)

    # The public landing page (50) is the home page; it sends signed-in users
    # on to their own screen
    home = "        homeUrl: {\n            page: 1\n        }\n"
    if home not in text:
        sys.exit(f"Unexpected home URL in {app}; cannot make the landing page the home page")
    app.write_text(text.replace(home, home.replace("page: 1", "page: 50"), 1), encoding="utf-8", newline="\n")

    # Visitors on the landing page should not see a user menu for "nobody"
    user_entry = "    entry app-user (\n        label: &APP_USER.\n"
    text = lists.read_text(encoding="utf-8")
    if user_entry not in text:
        sys.exit(f"Unexpected navigation bar in {lists}; cannot hide it from visitors")
    lists.write_text(text.replace(user_entry, user_entry + (
        "        serverSideCondition {\n"
        "            type: userIsAuthenticated\n"
        "        }\n"), 1), encoding="utf-8", newline="\n")
    print(f"Added {len(pages)} canvas screens from {PAGES_DIR.relative_to(REPO)}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--wallet", required=True, help="Path to the ADB client wallet zip")
    p.add_argument("--app-id", type=int, default=100)
    p.add_argument("--check-only", action="store_true", help="Validate and generate, do not install")
    p.add_argument("--alias", help="App alias, for a second copy beside app 100 (aliases are unique)")
    p.add_argument("--name", help="App name, e.g. to label a preview copy")
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
        apply_theme()
        apply_error_handling()
        apply_frontend_pages()

    if args.check_only:
        return

    # The password is sent on stdin so it never appears in the process list
    script = "\n".join([
        f"set cloudconfig {Path(args.wallet).resolve()}",
        f'connect {WORKSPACE}/"{env("HL_SCHEMA_PASSWORD")}"@{service_name(args.wallet)}',
        "whenever sqlerror exit failure",
        f"apex validate -input {APEXLANG_DIR} -workspace {WORKSPACE}",
        f"apex import -input {APEXLANG_DIR} -workspace {WORKSPACE} -schema {WORKSPACE} -id {args.app_id}"
        + (f" -alias {args.alias}" if args.alias else "")
        + (f' -name "{args.name}"' if args.name else ""),
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
