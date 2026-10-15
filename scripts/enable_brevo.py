#!/usr/bin/env python3
"""Switch on account emails (HL_MAIL) through Brevo's transactional email API.

Steps:
  1. As ADMIN: open the network ACL to api.brevo.com (HTTPS) for the APEX
     engine, which makes the call for APEX_WEB_SERVICE, and for HARVESTLINK.
  2. As HARVESTLINK: store the API key as the APEX web credential BREVO_API
     (HTTP header api-key; the key lives in the database, never in the repo),
     set the sender and the page links in HL_TEXT_SETTINGS, set
     MAIL_ENABLED = 1 and send anything already queued.
  3. With --test-to: send a test email and report how it went.

--disable only sets MAIL_ENABLED = 0 (emails stay queued in HL_MAIL_OUTBOX).

The sender address must be a sender or domain verified in Brevo.

Secrets are read from the environment, never from arguments:
  HL_ADMIN_PASSWORD, HL_SCHEMA_PASSWORD, HL_WALLET_PASSWORD (with --wallet),
  HL_BREVO_API_KEY, HL_MAIL_SENDER_EMAIL; optional HL_MAIL_SENDER_NAME
  (default HarvestLink) and HL_APP_URL (default the live app).

Examples:
  python scripts/enable_brevo.py --wallet infra/.wallet/wallet.zip --test-to you@example.com
  python scripts/enable_brevo.py --wallet infra/.wallet/wallet.zip --disable
"""
import argparse
import os
import re
import tempfile
import zipfile
from pathlib import Path

from bootstrap_db import SCHEMA, connect, env

HOST = "api.brevo.com"
CREDENTIAL = "BREVO_API"   # static ID used by db/15_accounts.sql (HL_MAIL)
APP_URL = "https://gc0208e4d90b947-harvestlinkstrathmore.adb.eu-frankfurt-1.oraclecloudapps.com/ords/r/harvestlink/harvestlink/"
# Pages built for sign-up (apex/pages): verify email (9001) and reset password (9003)
LINKS = {
    "VERIFY_URL": "verify-email?p9001_token=#TOKEN#",
    "RESET_URL": "reset-password?p9003_token=#TOKEN#",
    "SIGN_IN_URL": "login",
}


def open_network(admin):
    cur = admin.cursor()
    cur.execute("select table_owner from dba_synonyms where owner = 'PUBLIC' and synonym_name = 'APEX_WEB_SERVICE'")
    apex_schema = cur.fetchone()[0]
    for principal in (apex_schema, SCHEMA):
        cur.execute("""
            begin
              dbms_network_acl_admin.append_host_ace(
                host       => :host,
                lower_port => 443,
                upper_port => 443,
                ace        => xs$ace_type(privilege_list => xs$name_list('http'),
                                          principal_name => :principal,
                                          principal_type => xs_acl.ptype_db));
            end;""", host=HOST, principal=principal)
    print(f"Opened HTTPS to {HOST} for {apex_schema} and {SCHEMA}")


def configure(conn):
    cur = conn.cursor()
    cur.execute("""
        declare
          l_found number;
        begin
          apex_util.set_workspace(p_workspace => :ws);
          select count(*) into l_found from apex_workspace_credentials where static_id = :cred;
          if l_found = 0 then
            apex_credential.create_credential(
              p_credential_name      => 'Brevo API',
              p_credential_static_id => :cred,
              p_authentication_type  => apex_credential.c_type_http_header,
              p_allowed_urls         => apex_t_varchar2('https://' || :host || '/'),
              p_prompt_on_install    => false);
          end if;
          apex_credential.set_persistent_credentials(
            p_credential_static_id => :cred,
            p_key                  => 'api-key',
            p_value                => :api_key);
          commit;
        end;""", ws=SCHEMA, cred=CREDENTIAL, host=HOST, api_key=env("HL_BREVO_API_KEY"))
    base = os.environ.get("HL_APP_URL") or APP_URL
    settings = {"MAIL_SENDER_EMAIL": env("HL_MAIL_SENDER_EMAIL"),
                "MAIL_SENDER_NAME": os.environ.get("HL_MAIL_SENDER_NAME") or "HarvestLink"}
    settings.update({k: base + v for k, v in LINKS.items()})
    for key, value in settings.items():
        cur.execute("update hl_text_settings set setting_value = :v where setting_key = :k", v=value, k=key)
    cur.execute("update hl_settings set setting_value = 1 where setting_key = 'MAIL_ENABLED'")
    conn.commit()
    cur.execute("begin hl_mail.send_pending; end;")
    conn.commit()
    print(f"Stored web credential {CREDENTIAL}, sender {settings['MAIL_SENDER_EMAIL']}, MAIL_ENABLED = 1")


def send_test(conn, to):
    cur = conn.cursor()
    mail_id = cur.callfunc("hl_mail.queue", int, [
        to, "HarvestLink email test",
        "<p>HarvestLink can send email through Brevo.</p>",
        "HarvestLink can send email through Brevo."])
    conn.commit()
    cur.execute("select status, last_error from hl_mail_outbox where mail_id = :i", i=mail_id)
    status, error = cur.fetchone()
    print(f"Test email to {to}: {status}" + (f" ({error})" if error else ""))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--wallet", help="Path to the ADB client wallet zip")
    target.add_argument("--dsn", help="Plain connect string")
    p.add_argument("--service", help="TNS alias in the wallet (default: the *_low alias)")
    p.add_argument("--test-to", help="Send a test email to this address")
    p.add_argument("--disable", action="store_true", help="Set MAIL_ENABLED = 0 and stop")
    args = p.parse_args()

    with tempfile.TemporaryDirectory() as wallet_dir:
        if args.wallet:
            with zipfile.ZipFile(args.wallet) as z:
                z.extractall(wallet_dir)
            if not args.service:
                tns = (Path(wallet_dir) / "tnsnames.ora").read_text()
                args.service = re.search(r"^(\w+_low)\s*=", tns, re.M | re.I).group(1)

        if args.disable:
            with connect(SCHEMA, env("HL_SCHEMA_PASSWORD"), args, wallet_dir) as conn:
                conn.cursor().execute("update hl_settings set setting_value = 0 where setting_key = 'MAIL_ENABLED'")
                conn.commit()
            print("MAIL_ENABLED = 0: account emails stay queued in HL_MAIL_OUTBOX")
            return

        with connect("ADMIN", env("HL_ADMIN_PASSWORD"), args, wallet_dir) as admin:
            open_network(admin)
        with connect(SCHEMA, env("HL_SCHEMA_PASSWORD"), args, wallet_dir) as conn:
            configure(conn)
            if args.test_to:
                send_test(conn, args.test_to)


if __name__ == "__main__":
    main()
