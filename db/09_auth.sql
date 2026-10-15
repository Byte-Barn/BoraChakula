-- HarvestLink: roles, the signed-in party, and "my" views.
--
-- Each login maps to one role: BUYER, FARMER or OPS (operations, sees
-- everything). Demo logins link to their party by name, so hl_demo.reset (which
-- recreates the demo parties with new IDs) never breaks them; accounts created
-- by sign-up (HL_ACCOUNT_API, db/15_accounts.sql) link by FARMER_ID / BUYER_ID.
-- The sign-in columns (email, password hash, status) belong to HL_ACCOUNT_API.
-- Pages and authorization schemes use HL_AUTH; they never read HL_APP_USERS
-- directly.

create table hl_app_users (
  user_name          varchar2(255)  not null,   -- login name, upper case (the email, for sign-ups)
  role               varchar2(10)   not null,
  party_name         varchar2(150),             -- HL_BUYERS.BUYER_NAME or HL_FARMERS.FULL_NAME
  farmer_id          number,                    -- set for sign-ups; demo logins match by name
  buyer_id           number,
  email              varchar2(254),
  password_hash      varchar2(200),             -- pbkdf2-sha256$iterations$salt$hash (HL_ACCOUNT_API)
  status             varchar2(20)   default 'ACTIVE' not null,
  email_verified_at  timestamp,
  approved_at        timestamp,
  approved_by        varchar2(255),
  failed_logins      number         default 0 not null,
  locked_until       timestamp,
  last_login_at      timestamp,
  created_at         timestamp      default systimestamp not null,
  constraint hl_app_users_pk primary key (user_name),
  constraint hl_app_users_status_ck check (status in ('PENDING_EMAIL', 'PENDING_APPROVAL', 'ACTIVE', 'DISABLED')),
  constraint hl_app_users_role_ck check (role in ('BUYER', 'FARMER', 'OPS')),
  constraint hl_app_users_party_ck check (
    (role = 'OPS' and party_name is null) or (role <> 'OPS' and party_name is not null)),
  constraint hl_app_users_upper_ck check (user_name = upper(user_name))
);
create unique index hl_app_users_email_uk on hl_app_users (lower(email));

create or replace package hl_auth as

  -- The signed-in user: the APEX session user, else the database user.
  -- set_user overrides it for scripts and tests; pass null to clear.
  function app_user return varchar2;
  procedure set_user (p_user_name in varchar2);

  -- Role and party of a user (default: the signed-in user); null when unmapped
  function role      (p_user_name in varchar2 default null) return varchar2;
  function buyer_id  (p_user_name in varchar2 default null) return number;
  function farmer_id (p_user_name in varchar2 default null) return number;

  -- For APEX authorization schemes ("PL/SQL Function Returning Boolean"):
  --   IS_BUYER:  return hl_auth.is_buyer;
  --   IS_FARMER: return hl_auth.is_farmer;
  --   IS_OPS:    return hl_auth.is_ops;
  function is_buyer  return boolean;
  function is_farmer return boolean;
  function is_ops    return boolean;

  -- Creates or updates a login's role and party (party name required for
  -- BUYER and FARMER). Does not create the APEX account itself.
  procedure register_user (
    p_user_name  in varchar2,
    p_role       in varchar2,
    p_party_name in varchar2 default null);

end hl_auth;
/

create or replace package body hl_auth as

  g_user_override varchar2(255);

  function app_user return varchar2 is
  begin
    return upper(coalesce(g_user_override,
                          sys_context('APEX$SESSION', 'APP_USER'),
                          sys_context('USERENV', 'SESSION_USER')));
  end app_user;

  procedure set_user (p_user_name in varchar2) is
  begin
    g_user_override := upper(p_user_name);
  end set_user;

  function mapping (p_user_name in varchar2) return hl_app_users%rowtype is
    l_row hl_app_users%rowtype;
  begin
    select * into l_row
      from hl_app_users
     where user_name = upper(coalesce(p_user_name, app_user));
    return l_row;
  exception
    when no_data_found then
      return null;
  end mapping;

  function role (p_user_name in varchar2 default null) return varchar2 is
  begin
    return mapping(p_user_name).role;
  end role;

  function buyer_id (p_user_name in varchar2 default null) return number is
    l_map hl_app_users%rowtype := mapping(p_user_name);
    l_id  hl_buyers.buyer_id%type;
  begin
    if l_map.role <> 'BUYER' or l_map.role is null then
      return null;
    end if;
    if l_map.buyer_id is not null then
      return l_map.buyer_id;
    end if;
    select min(buyer_id) into l_id from hl_buyers where buyer_name = l_map.party_name;
    return l_id;
  end buyer_id;

  function farmer_id (p_user_name in varchar2 default null) return number is
    l_map hl_app_users%rowtype := mapping(p_user_name);
    l_id  hl_farmers.farmer_id%type;
  begin
    if l_map.role <> 'FARMER' or l_map.role is null then
      return null;
    end if;
    if l_map.farmer_id is not null then
      return l_map.farmer_id;
    end if;
    select min(farmer_id) into l_id from hl_farmers where full_name = l_map.party_name;
    return l_id;
  end farmer_id;

  function is_buyer return boolean is
  begin
    return nvl(role = 'BUYER', false);
  end is_buyer;

  function is_farmer return boolean is
  begin
    return nvl(role = 'FARMER', false);
  end is_farmer;

  function is_ops return boolean is
  begin
    return nvl(role = 'OPS', false);
  end is_ops;

  procedure register_user (
    p_user_name  in varchar2,
    p_role       in varchar2,
    p_party_name in varchar2 default null
  ) is
    l_role  varchar2(10) := upper(p_role);
    l_found number;
  begin
    if l_role is null or l_role not in ('BUYER', 'FARMER', 'OPS') then
      raise_application_error(-20501, 'Role must be BUYER, FARMER or OPS');
    end if;
    if l_role = 'BUYER' then
      select count(*) into l_found from hl_buyers where buyer_name = p_party_name;
    elsif l_role = 'FARMER' then
      select count(*) into l_found from hl_farmers where full_name = p_party_name;
    end if;
    if l_role <> 'OPS' and nvl(l_found, 0) = 0 then
      raise_application_error(-20502, 'No ' || lower(l_role) || ' named "' || p_party_name || '"');
    end if;

    merge into hl_app_users u
    using (select upper(p_user_name) as user_name, upper(p_role) as role,
                  case when upper(p_role) = 'OPS' then null else p_party_name end as party_name
             from dual) s
       on (u.user_name = s.user_name)
     when matched then update set u.role = s.role, u.party_name = s.party_name
     when not matched then insert (user_name, role, party_name)
                           values (s.user_name, s.role, s.party_name);
  end register_user;

end hl_auth;
/

-- The signed-in buyer's demands, with fulfilment (buyer dashboard)
create or replace view hl_my_demands_v as
select f.*
  from hl_fulfil_v f
 where f.buyer_id = hl_auth.buyer_id;

-- The signed-in farmer's expected harvests and how much is still unpromised
create or replace view hl_my_harvests_v as
select h.harvest_id,
       h.crop_id,
       c.crop_name,
       h.grade,
       h.expected_qty_kg,
       hl_match_pkg.available_kg(h.harvest_id) as available_kg,
       h.harvest_from,
       h.harvest_to,
       h.status,
       h.notes
  from hl_harvests h
  join hl_crops c on c.crop_id = h.crop_id
 where h.farmer_id = hl_auth.farmer_id;

-- Offers to the signed-in farmer: each match with the buyer's terms
-- (farmer dashboard: accept with hl_match_pkg.confirm, decline with decline)
create or replace view hl_my_offers_v as
select m.match_id,
       m.demand_id,
       m.harvest_id,
       m.ui_status,
       m.crop_name,
       m.grade,
       m.allocated_kg,
       d.price_per_kg,
       m.allocated_kg * d.price_per_kg as offer_value_kes,
       d.need_by_date,
       b.buyer_name,
       b.location_name || ', ' || b.county as buyer_location,
       m.reason_qty,
       m.reason_grade,
       m.reason_window,
       m.reason_dist,
       m.agreement_hash
  from hl_match_v m
  join hl_demands d on d.demand_id = m.demand_id
  join hl_buyers b on b.buyer_id = d.buyer_id
 where m.farmer_id = hl_auth.farmer_id;

-- Demo logins (the APEX accounts are created by scripts/bootstrap_db.py)
begin
  hl_auth.register_user('BUYER_DEMO',  'BUYER',  'Kijani Fresh Grocers');
  hl_auth.register_user('FARMER_DEMO', 'FARMER', 'Wanjiru Muthoni');
  hl_auth.register_user('OPS_DEMO',    'OPS');
  hl_auth.register_user('JUDGE',       'OPS');
  commit;
end;
/
