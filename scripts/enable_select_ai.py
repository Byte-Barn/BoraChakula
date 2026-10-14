#!/usr/bin/env python3
"""Switch on Select AI match sentences (HL_AI) on an Autonomous AI Database.

Steps:
  1. As ADMIN: grant HARVESTLINK EXECUTE on DBMS_CLOUD and DBMS_CLOUD_AI, and
     open the network ACL to the AI provider's host.
  2. As HARVESTLINK: store the provider API key as credential HL_AI_CRED with
     DBMS_CLOUD.CREATE_CREDENTIAL (the key lives in the database, never in the
     repo), create the HL_EXPLAIN profile, set AI_ENABLED = 1 and explain the
     featured match in English and Kiswahili as a check.

--disable only sets AI_ENABLED = 0 (pages fall back to the rule-based reasons).

Secrets are read from the environment, never from arguments:
  HL_ADMIN_PASSWORD, HL_SCHEMA_PASSWORD, HL_WALLET_PASSWORD (with --wallet),
  HL_AI_API_KEY; optional HL_AI_PROVIDER (default openai) and HL_AI_MODEL.

Examples:
  python scripts/enable_select_ai.py --wallet infra/.wallet/wallet.zip
  python scripts/enable_select_ai.py --wallet infra/.wallet/wallet.zip --disable
"""
import argparse
import os
import re
import tempfile
import zipfile
from pathlib import Path

from bootstrap_db import SCHEMA, connect, env

CREDENTIAL = "HL_AI_CRED"
# Providers that authenticate with an API key, and the host Select AI calls
PROVIDER_HOSTS = {
    "openai": "api.openai.com",
    "cohere": "api.cohere.ai",
    "anthropic": "api.anthropic.com",
    "google": "generativelanguage.googleapis.com",
}


def grant_access(admin, provider):
    cur = admin.cursor()
    for pkg in ("DBMS_CLOUD", "DBMS_CLOUD_AI"):
        cur.execute(f"grant execute on {pkg} to {SCHEMA}")
    cur.execute("""
        begin
          dbms_network_acl_admin.append_host_ace(
            host => :host,
            ace  => xs$ace_type(privilege_list => xs$name_list('http'),
                                principal_name => :schema,
                                principal_type => xs_acl.ptype_db));
        end;""", host=PROVIDER_HOSTS[provider], schema=SCHEMA)
    print(f"Granted {SCHEMA} Select AI and HTTPS access to {PROVIDER_HOSTS[provider]}")


def create_profile(conn, provider):
    cur = conn.cursor()
    cur.execute("""
        declare
          l_found number;
        begin
          select count(*) into l_found from user_credentials where credential_name = :cred;
          if l_found > 0 then
            dbms_cloud.drop_credential(credential_name => :cred);
          end if;
          dbms_cloud.create_credential(
            credential_name => :cred,
            username        => :provider,
            password        => :api_key);
          hl_ai.create_profile(p_provider => :provider, p_credential_name => :cred, p_model => :model);
          hl_ai.set_enabled(true);
          commit;
        end;""", cred=CREDENTIAL, provider=provider, api_key=env("HL_AI_API_KEY"),
                model=os.environ.get("HL_AI_MODEL") or None)
    print(f"Stored credential {CREDENTIAL}, created profile HL_EXPLAIN ({provider}), AI_ENABLED = 1")


def check(conn):
    cur = conn.cursor()
    cur.execute("""
        select m.match_id from hl_match_v m
         where m.demand_id = hl_demo.featured_demand_id
         order by m.rank_no fetch first 1 row only""")
    row = cur.fetchone()
    if not row:
        print("No featured match to check")
        return
    for lang in ("en", "sw"):
        sentence = cur.callfunc("hl_ai.explain_match", str, [row[0], lang])
        source = cur.callfunc("hl_ai.explained_by", str, [row[0], lang])
        print(f"[{lang}] ({source}) {sentence}")
        if source != "AI":
            print(f"  Fell back to the rules: {cur.callfunc('hl_ai.last_error', str)}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    target = p.add_mutually_exclusive_group(required=True)
    target.add_argument("--wallet", help="Path to the ADB client wallet zip")
    target.add_argument("--dsn", help="Plain connect string")
    p.add_argument("--service", help="TNS alias in the wallet (default: the *_low alias)")
    p.add_argument("--disable", action="store_true", help="Set AI_ENABLED = 0 and stop")
    args = p.parse_args()

    provider = os.environ.get("HL_AI_PROVIDER", "openai").lower()
    if not args.disable and provider not in PROVIDER_HOSTS:
        raise SystemExit(f"HL_AI_PROVIDER must be one of {', '.join(PROVIDER_HOSTS)} "
                         "(for OCI Generative AI, create the profile by hand: see db/README.md)")

    with tempfile.TemporaryDirectory() as wallet_dir:
        if args.wallet:
            with zipfile.ZipFile(args.wallet) as z:
                z.extractall(wallet_dir)
            if not args.service:
                tns = (Path(wallet_dir) / "tnsnames.ora").read_text()
                args.service = re.search(r"^(\w+_low)\s*=", tns, re.M | re.I).group(1)

        if args.disable:
            with connect(SCHEMA, env("HL_SCHEMA_PASSWORD"), args, wallet_dir) as conn:
                conn.cursor().execute("begin hl_ai.set_enabled(false); commit; end;")
            print("AI_ENABLED = 0: pages show the rule-based reasons")
            return

        with connect("ADMIN", env("HL_ADMIN_PASSWORD"), args, wallet_dir) as admin:
            grant_access(admin, provider)
        with connect(SCHEMA, env("HL_SCHEMA_PASSWORD"), args, wallet_dir) as conn:
            create_profile(conn, provider)
            check(conn)


if __name__ == "__main__":
    main()
