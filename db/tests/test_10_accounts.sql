-- Sign-up, email verification, sign-in, lockout, password reset, buyer approval
declare
  c_farmer  constant varchar2(100) := 'Njeri.Kamau@example.com';
  c_buyer   constant varchar2(100) := 'orders@freshmart.example';
  l_user    varchar2(255);
  l_token   varchar2(64);
  l_status  varchar2(30);
  l_count   number;
  l_mails   number;
  l_farmers number;

  function last_token (p_to in varchar2) return varchar2 is
    l_text clob;
  begin
    select body_text into l_text
      from hl_mail_outbox where lower(to_email) = lower(p_to)
     order by mail_id desc fetch first 1 row only;
    return regexp_substr(l_text, '[0-9a-f]{64}');
  end last_token;

  function mails (p_to in varchar2) return number is
    l_n number;
  begin
    select count(*) into l_n from hl_mail_outbox where lower(to_email) = lower(p_to);
    return l_n;
  end mails;
begin
  update hl_text_settings set setting_value = 'https://example.test/verify?t=#TOKEN#' where setting_key = 'VERIFY_URL';
  update hl_text_settings set setting_value = 'https://example.test/reset?t=#TOKEN#' where setting_key = 'RESET_URL';

  -- Farmer sign-up
  l_user := hl_account_api.register(c_farmer, 'mavuno-2026!', 'farmer', 'Njeri Kamau', '+254711000999',
                                    'Kirinyaga', 'Kutus', -0.57, 37.32, p_consent => 'Y');
  commit;  -- sign-in bookkeeping runs in its own transaction
  hlt.eq(l_user, upper(c_farmer), 'sign-up: user name is the email');
  select status into l_status from hl_app_users where user_name = l_user;
  hlt.eq(l_status, 'PENDING_EMAIL', 'sign-up: waits for the email');
  select count(*) into l_count from hl_farmers where full_name = 'Njeri Kamau' and is_demo = 'N' and consent_given = 'Y';
  hlt.eq(l_count, 1, 'sign-up: farmer record with consent');
  hlt.eq(mails(c_farmer), 1, 'sign-up: verification email queued');
  select count(*) into l_count from hl_app_users where user_name = l_user and password_hash like 'pbkdf2-sha256$10000$%';
  hlt.eq(l_count, 1, 'password stored as a PBKDF2 hash');
  l_token := last_token(c_farmer);
  select count(*) into l_count from hl_account_tokens where user_name = l_user
     and token_hash = l_token;
  hlt.eq(l_count, 0, 'only the token hash is stored');

  hlt.ok(not hl_account_api.authenticate(c_farmer, 'mavuno-2026!'), 'unverified: cannot sign in');
  hlt.eq(hl_account_api.login_status, 'PENDING_EMAIL', 'unverified: says why');

  -- Verify
  l_token := last_token(c_farmer);
  hlt.eq(hl_account_api.verify_email(l_token), 'ACTIVE', 'farmer active after verifying');
  commit;
  hlt.raises('declare s varchar2(30); begin s := hl_account_api.verify_email(''' || l_token || '''); end;',
             -20708, 'verification link works once');
  hlt.raises('declare s varchar2(30); begin s := hl_account_api.verify_email(''nonsense''); end;',
             -20708, 'malformed link refused');

  -- Sign in
  hlt.ok(not hl_account_api.authenticate(c_farmer, 'wrong-password'), 'wrong password refused');
  hlt.eq(hl_account_api.login_status, 'INVALID', 'wrong password: INVALID');
  hlt.ok(hl_account_api.authenticate(upper(c_farmer), 'mavuno-2026!'), 'signs in, email in any case');
  hlt.eq(hl_account_api.login_user, upper(c_farmer), 'signs in as the account user name');
  hlt.ok(not hl_account_api.authenticate('nobody@example.com', 'mavuno-2026!'), 'unknown email refused');
  hl_auth.set_user(c_farmer);
  select count(*) into l_count from hl_farmers where farmer_id = hl_auth.farmer_id and full_name = 'Njeri Kamau';
  hlt.eq(l_count, 1, 'signed-in farmer maps to their record');
  hl_auth.set_user(null);

  -- Validation
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''njeri.kamau@example.com'', ''another-pass1'', ''FARMER'', ''N K'', ''+254700000001'', ''Kirinyaga'', null, -0.5, 37.3, p_consent => ''Y''); end;', -20703, 'duplicate email refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''short'', ''FARMER'', ''A'', ''+254700000002'', ''Kirinyaga'', null, -0.5, 37.3, p_consent => ''Y''); end;', -20704, 'short password refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''1234567890123'', ''FARMER'', ''A'', ''+254700000002'', ''Kirinyaga'', null, -0.5, 37.3, p_consent => ''Y''); end;', -20704, 'digits-only password refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''long-enough-1'', ''OPS'', ''A'', null, ''Nairobi'', null, -1.2, 36.8); end;', -20701, 'cannot sign up as admin');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''not-an-email'', ''long-enough-1'', ''FARMER'', ''A'', ''+254700000002'', ''Kirinyaga'', null, -0.5, 37.3, p_consent => ''Y''); end;', -20702, 'invalid email refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''long-enough-1'', ''FARMER'', ''A'', ''+254700000002'', ''Kirinyaga'', null, -0.5, 37.3); end;', -20707, 'farmer must consent');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''long-enough-1'', ''FARMER'', ''A'', ''+254711000999'', ''Kirinyaga'', null, -0.5, 37.3, p_consent => ''Y''); end;', -20709, 'duplicate farmer phone refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''a@example.com'', ''long-enough-1'', ''FARMER'', ''A'', ''+254700000002'', ''Kirinyaga'', null, 51.5, -0.1, p_consent => ''Y''); end;', -20706, 'location outside Kenya refused');
  hlt.raises('declare u varchar2(255); begin u := hl_account_api.register(''b@example.com'', ''long-enough-1'', ''BUYER'', ''B Ltd'', null, ''Nairobi'', null, -1.2, 36.8); end;', -20710, 'buyer type required');

  -- Buyer: verify, then approval by the team
  l_user := hl_account_api.register(c_buyer, 'fresh-mart-orders', 'BUYER', 'FreshMart Ltd', '+254720000111',
                                    'Nairobi', 'Westlands', -1.2676, 36.8108, p_buyer_type => 'retailer');
  commit;
  hlt.eq(hl_account_api.verify_email(last_token(c_buyer)), 'PENDING_APPROVAL', 'buyer waits for approval after verifying');
  commit;
  hlt.ok(not hl_account_api.authenticate(c_buyer, 'fresh-mart-orders'), 'buyer cannot sign in before approval');
  hlt.eq(hl_account_api.login_status, 'PENDING_APPROVAL', 'pending buyer: says why');
  select count(*) into l_count from hl_pending_accounts_v where user_name = l_user and buyer_type = 'RETAILER';
  hlt.eq(l_count, 1, 'listed for the team to approve');
  hl_auth.set_user('BUYER_DEMO');
  hlt.raises('hl_account_api.approve(''' || l_user || ''');', -20712, 'only admins approve');
  hl_auth.set_user('OPS_DEMO');
  l_mails := mails(c_buyer);
  hl_account_api.approve(l_user);
  commit;
  hl_auth.set_user(null);
  hlt.ok(hl_account_api.authenticate(c_buyer, 'fresh-mart-orders'), 'approved buyer signs in');
  hlt.eq(mails(c_buyer), l_mails + 1, 'approval emailed');
  hl_auth.set_user(c_buyer);
  select count(*) into l_count from hl_buyers where buyer_id = hl_auth.buyer_id and buyer_name = 'FreshMart Ltd';
  hlt.eq(l_count, 1, 'signed-in buyer maps to their record');
  hl_auth.set_user(null);

  -- Lockout after 5 wrong passwords, even with the right one
  for i in 1 .. 5 loop
    l_status := case when hl_account_api.authenticate(c_farmer, 'wrong-' || i) then 'Y' else 'N' end;
  end loop;
  hlt.ok(not hl_account_api.authenticate(c_farmer, 'mavuno-2026!'), 'locked after 5 wrong passwords');
  hlt.eq(hl_account_api.login_status, 'LOCKED', 'locked: says why');

  -- Password reset unlocks
  l_mails := mails('nobody@example.com');
  hl_account_api.request_password_reset('nobody@example.com');
  hlt.eq(mails('nobody@example.com'), l_mails, 'reset for an unknown email sends nothing');
  hl_account_api.request_password_reset(c_farmer);
  l_token := last_token(c_farmer);
  hlt.raises('hl_account_api.reset_password(''' || l_token || ''', ''short'');', -20704, 'reset keeps the password rules');
  hl_account_api.reset_password(l_token, 'new-harvest-pass');
  commit;
  hlt.ok(hl_account_api.authenticate(c_farmer, 'new-harvest-pass'), 'new password works and unlocks');
  hlt.ok(not hl_account_api.authenticate(c_farmer, 'mavuno-2026!'), 'old password no longer works');
  hlt.raises('hl_account_api.reset_password(''' || l_token || ''', ''another-pass-2'');', -20708, 'reset link works once');

  -- Admin can disable and re-enable
  hl_auth.set_user('OPS_DEMO');
  hl_account_api.set_disabled(c_farmer, true);
  commit;
  hlt.ok(not hl_account_api.authenticate(c_farmer, 'new-harvest-pass'), 'disabled account refused');
  hl_account_api.set_disabled(c_farmer, false);
  commit;
  hlt.ok(hl_account_api.authenticate(c_farmer, 'new-harvest-pass'), 're-enabled account signs in');
  hl_auth.set_user(null);

  -- Demo logins get passwords from the setup scripts
  hl_account_api.set_password('JUDGE', 'judge-demo-pass');
  commit;
  hlt.ok(hl_account_api.authenticate('judge', 'judge-demo-pass'), 'demo login signs in by user name');

  -- Sent mail without Brevo stays queued
  select count(*) into l_count from hl_mail_outbox where status <> 'QUEUED';
  hlt.eq(l_count, 0, 'mail off: everything stays queued');

  -- The demo reset keeps registered farmers and buyers
  select count(*) into l_farmers from hl_farmers where is_demo = 'N';
  hl_demo.reset;
  commit;
  select count(*) into l_count from hl_farmers where is_demo = 'N';
  hlt.eq(l_count, l_farmers, 'demo reset keeps registered farmers');
  select count(*) into l_count from hl_buyers where buyer_name = 'FreshMart Ltd';
  hlt.eq(l_count, 1, 'demo reset keeps registered buyers');
  hlt.ok(hl_demo.featured_demand_id is not null, 'demo reset restores the demo story');
  hlt.ok(hl_account_api.authenticate(c_farmer, 'new-harvest-pass'), 'registered account still signs in after a demo reset');
  commit;
end;
/
