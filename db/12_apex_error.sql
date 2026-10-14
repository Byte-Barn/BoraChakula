-- HarvestLink: APEX error handling function.
--
-- The backend APIs raise ORA-20100..-20599 with messages written for end
-- users (docs/backend-api.md). APEX would show them with the ORA- code and a
-- PL/SQL stack; this handler shows just the message, inline when the page
-- process names the item it belongs to. Set as the application's Error
-- Handling Function (scripts/install_app.py does this on every build).

create or replace package hl_apex_error as

  -- HarvestLink business errors: ORA-20100 .. ORA-20599
  function is_business_error (p_ora_sqlcode in number) return boolean;

  -- The message without its "ORA-20xxx: " prefix and stack lines
  function clean_message (p_message in varchar2) return varchar2;

  function handle (p_error in apex_error.t_error) return apex_error.t_error_result;

end hl_apex_error;
/

create or replace package body hl_apex_error as

  function is_business_error (p_ora_sqlcode in number) return boolean is
  begin
    return p_ora_sqlcode between -20599 and -20100;
  end is_business_error;

  function clean_message (p_message in varchar2) return varchar2 is
    l_msg varchar2(32767) := p_message;
  begin
    -- First line only: drops ORA-06512 stack lines and the Help URL
    l_msg := regexp_substr(l_msg, '^[^' || chr(10) || ']*');
    l_msg := regexp_replace(l_msg, '^ORA-2[01][0-9]{3}: ', '');
    return trim(l_msg);
  end clean_message;

  function handle (p_error in apex_error.t_error) return apex_error.t_error_result is
    l_result apex_error.t_error_result;
  begin
    l_result := apex_error.init_error_result(p_error => p_error);

    if is_business_error(p_error.ora_sqlcode) then
      l_result.message         := clean_message(nvl(p_error.ora_sqlerrm, p_error.message));
      l_result.additional_info := null;
      l_result.display_location := apex_error.c_inline_in_notification;
      -- Show it next to the field when the page set one (e.g. apex_error.add_error)
      if l_result.page_item_name is not null then
        l_result.display_location := apex_error.c_inline_with_field_and_notif;
      end if;
    elsif p_error.is_internal_error then
      -- Keep APEX's own handling for its internal errors
      null;
    elsif p_error.ora_sqlcode in (-1, -2290, -2291, -2292) then
      -- Constraint errors from forms: friendlier than the raw ORA text
      l_result.message := case p_error.ora_sqlcode
                            when -1    then 'This record already exists.'
                            when -2290 then 'A value is outside the allowed range.'
                            when -2291 then 'A related record does not exist.'
                            when -2292 then 'This record is still used elsewhere and cannot be deleted.'
                          end;
      l_result.additional_info := null;
    end if;

    return l_result;
  end handle;

end hl_apex_error;
/
