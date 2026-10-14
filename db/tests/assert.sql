-- Minimal assertion helper for db/tests. Each check prints PASS or FAIL;
-- hlt.summary raises if anything failed, which stops run.sh.
create or replace package hlt as
  procedure ok (p_condition in boolean, p_name in varchar2);
  procedure eq (p_actual in varchar2, p_expected in varchar2, p_name in varchar2);
  -- Runs p_plsql and passes when it raises p_sqlcode
  procedure raises (p_plsql in varchar2, p_sqlcode in number, p_name in varchar2);
  procedure summary;
end hlt;
/

create or replace package body hlt as
  g_pass pls_integer := 0;
  g_fail pls_integer := 0;

  procedure ok (p_condition in boolean, p_name in varchar2) is
  begin
    if nvl(p_condition, false) then
      g_pass := g_pass + 1;
      dbms_output.put_line('PASS ' || p_name);
    else
      g_fail := g_fail + 1;
      dbms_output.put_line('FAIL ' || p_name);
    end if;
  end ok;

  procedure eq (p_actual in varchar2, p_expected in varchar2, p_name in varchar2) is
  begin
    ok(p_actual = p_expected or (p_actual is null and p_expected is null),
       p_name || case when not (p_actual = p_expected) or (p_actual is null) <> (p_expected is null)
                      then ' (got "' || p_actual || '", expected "' || p_expected || '")' end);
  end eq;

  procedure raises (p_plsql in varchar2, p_sqlcode in number, p_name in varchar2) is
  begin
    execute immediate 'begin ' || p_plsql || ' end;';
    ok(false, p_name || ' (no error raised)');
  exception
    when others then
      ok(sqlcode = p_sqlcode, p_name || case when sqlcode <> p_sqlcode
                                             then ' (got ' || sqlcode || ': ' || sqlerrm || ')' end);
  end raises;

  procedure summary is
  begin
    dbms_output.put_line('RESULT ' || g_pass || ' passed, ' || g_fail || ' failed');
    if g_fail > 0 then
      raise_application_error(-20998, g_fail || ' backend test(s) failed');
    end if;
  end summary;
end hlt;
/
