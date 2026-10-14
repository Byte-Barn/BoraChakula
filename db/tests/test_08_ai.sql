-- Select AI match sentences: rule-based fallback, then the AI path against a
-- stand-in DBMS_CLOUD_AI (Oracle Database Free has no Select AI)
declare
  l_m     number;
  l_rules varchar2(4000);
  l_n     number;
  l_all   number;
begin
  select match_id into l_m
    from hl_match_v
   where demand_id = hl_demo.featured_demand_id and rank_no = 1;
  l_rules := hl_ai.rules_sentence(l_m);

  -- AI switched off (the installed default)
  hlt.ok(not hl_ai.is_enabled, 'AI is off after install');
  hlt.eq(hl_ai.explain_match(l_m), l_rules, 'AI off: explain_match returns the rule-based sentence');
  hlt.ok(l_rules like '%kg allocated%; Grade %; %; % km by road to the delivery point%.', 'rule sentence joins the four reasons');
  hlt.eq(hl_ai.explained_by(l_m), 'RULES', 'AI off: explained by rules');
  select count(*), count(hl_ai.explain_match(match_id, 'sw')) into l_all, l_n from hl_match_v;
  hlt.eq(l_n, l_all, 'AI off: a page query gets a sentence for every match');

  hlt.raises('declare s varchar2(4000); begin s := hl_ai.explain_match(-1); end;', -20611, 'unknown match refused');
  hlt.raises('declare s varchar2(4000); begin s := hl_ai.explain_match(' || l_m || ', ''fr''); end;', -20612, 'unsupported language refused');

  -- AI switched on, but Select AI is not installed here
  hl_ai.set_enabled(true);
  hlt.eq(hl_ai.explain_match(l_m), l_rules, 'AI on without Select AI: falls back to the rules');
  hlt.ok(hl_ai.last_error is not null, 'the failure reason is kept');
  hl_ai.set_enabled(false);
  commit;
end;
/

-- Stand-in for Select AI: replies with G_REPLY, or fails when it is 'FAIL'
create or replace package dbms_cloud_ai as
  g_reply varchar2(4000);
  g_calls pls_integer := 0;
  g_last_prompt clob;
  function generate (prompt in clob, profile_name in varchar2 default null,
                     action in varchar2 default null, attributes in clob default null,
                     params in clob default null) return clob;
end dbms_cloud_ai;
/
create or replace package body dbms_cloud_ai as
  function generate (prompt in clob, profile_name in varchar2 default null,
                     action in varchar2 default null, attributes in clob default null,
                     params in clob default null) return clob is
  begin
    g_calls := g_calls + 1;
    g_last_prompt := prompt;
    if g_reply = 'FAIL' then
      raise_application_error(-20000, 'provider unavailable');
    end if;
    return g_reply;
  end generate;
end dbms_cloud_ai;
/

declare
  l_m     number;
  l_rules varchar2(4000);
  l_s     varchar2(4000);
  l_ai    constant varchar2(200) := 'Grade A tomatoes, 650 kg, ready two days before delivery and 114 km away.';
begin
  select match_id into l_m
    from hl_match_v
   where demand_id = hl_demo.featured_demand_id and rank_no = 1;
  l_rules := hl_ai.rules_sentence(l_m);
  hl_ai.set_enabled(true);

  -- A working provider: first line only, quotes stripped, stored
  dbms_cloud_ai.g_reply := '"' || l_ai || '"' || chr(10) || 'Anything after the first line is dropped.';
  hlt.eq(hl_ai.explain_match(l_m), l_ai, 'AI on: one sentence from Select AI');
  hlt.eq(hl_ai.explained_by(l_m), 'AI', 'AI on: explained by AI');
  hlt.ok(dbms_lob.instr(dbms_cloud_ai.g_last_prompt, 'Wanjiru') = 0
         and dbms_lob.instr(dbms_cloud_ai.g_last_prompt, '+2547') = 0, 'prompt carries no farmer name or phone');
  hlt.eq(hl_ai.explain_match(l_m), l_ai, 'second call reuses the stored sentence');
  hlt.eq(dbms_cloud_ai.g_calls, 1, 'stored sentence costs no second AI call');

  -- Kiswahili is a separate sentence, and works from inside a query
  dbms_cloud_ai.g_reply := 'Nyanya za daraja A, kilo 650.';
  select hl_ai.explain_match(match_id, 'sw') into l_s from hl_matches where match_id = l_m;
  hlt.eq(l_s, 'Nyanya za daraja A, kilo 650.', 'Kiswahili sentence from a SELECT');
  hlt.ok(dbms_lob.instr(dbms_cloud_ai.g_last_prompt, 'Kiswahili') > 0, 'prompt asks for Kiswahili');

  -- Changed reasons make the stored sentence stale
  update hl_matches set allocated_kg = allocated_kg - 1 where match_id = l_m;
  hlt.eq(hl_ai.explained_by(l_m), 'RULES', 'changed reasons: stored sentence no longer used');
  dbms_cloud_ai.g_reply := 'FAIL';
  hlt.eq(hl_ai.explain_match(l_m), hl_ai.rules_sentence(l_m), 'provider failure: falls back to the rules');
  dbms_cloud_ai.g_reply := l_ai;
  hlt.eq(hl_ai.explain_match(l_m), hl_ai.rules_sentence(l_m), 'after a failure the session waits before retrying');
  hlt.eq(dbms_cloud_ai.g_calls, 3, 'no AI call during the wait');
  rollback;

  -- Switching AI off wins over stored sentences
  hl_ai.set_enabled(false);
  hlt.eq(hl_ai.explain_match(l_m), l_rules, 'AI off again: rules, even with a stored sentence');
  commit;
end;
/

drop package dbms_cloud_ai;
