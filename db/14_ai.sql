-- HarvestLink: one-sentence match explanations with Select AI (stretch).
--
-- HL_AI.EXPLAIN_MATCH turns the four rule-based reasons of a match (quantity,
-- grade, harvest window, distance in HL_MATCH_V) into one sentence, in English
-- or Kiswahili, using Select AI (DBMS_CLOUD_AI). The reasons stay the source
-- of truth: the model only rewords them, and whenever AI is switched off,
-- not set up or failing, the function returns the reasons joined into one
-- sentence instead. Pages never break because of AI.
--
-- Setup (Autonomous Database only, see db/README.md): scripts/enable_select_ai.py
-- grants DBMS_CLOUD_AI, opens the network ACL to the provider, stores the API
-- key with DBMS_CLOUD.CREATE_CREDENTIAL (in the database, never in the repo),
-- creates the HL_EXPLAIN profile and switches AI_ENABLED on.
--
-- DBMS_CLOUD_AI is called through dynamic SQL so this file installs on
-- databases without it (Oracle Database Free, the backend tests).
--
-- Privacy: the prompt carries only the reasons, crop, grade and match status;
-- never farmer or buyer names or phone numbers.
--
-- Error codes: -20611..-20619 (docs/backend-api.md).

merge into hl_settings s
using (select 'AI_ENABLED' as setting_key, 0 as setting_value,
              'Select AI match sentences: 1 = on, 0 = off (rule-based reasons only)' as description
         from dual) n
   on (s.setting_key = n.setting_key)
 when not matched then insert (setting_key, setting_value, description)
                       values (n.setting_key, n.setting_value, n.description);

-- Generated sentences, reused until the match's reasons change (FINGERPRINT).
-- Only AI sentences are stored; the rule-based fallback is cheap to rebuild.
-- No foreign key to HL_MATCHES: rows are written in an autonomous
-- transaction, which would deadlock on a match not yet committed by the page.
-- Rows of deleted matches are removed on the next write instead.
create table hl_ai_explanations (
  match_id     number          not null,
  lang         varchar2(2)     not null,
  fingerprint  varchar2(64)    not null,  -- SHA-256 of the reasons and status it was written from
  sentence     varchar2(1000)  not null,
  created_at   timestamp       default systimestamp not null,
  constraint hl_ai_explanations_pk primary key (match_id, lang),
  constraint hl_ai_explanations_lang_ck check (lang in ('en', 'sw'))
);

create or replace package hl_ai as

  -- Select AI profile the sentences are generated with
  c_profile constant varchar2(30) := 'HL_EXPLAIN';

  -- One sentence explaining why the farm fits the order. p_lang: 'en' or 'sw'
  -- (Kiswahili). Falls back to the four rule-based reasons in one sentence
  -- (English) when AI is off or unavailable. Safe to call from a query.
  function explain_match (p_match_id in number, p_lang in varchar2 default 'en') return varchar2;

  -- 'AI' when EXPLAIN_MATCH would return a stored AI sentence for the match's
  -- current reasons, else 'RULES'. For a small "AI" tag beside the sentence.
  function explained_by (p_match_id in number, p_lang in varchar2 default 'en') return varchar2;

  -- The rule-based sentence: the four reasons joined
  function rules_sentence (p_match_id in number) return varchar2;

  -- Identifies the reasons and status a sentence was generated from
  function fingerprint (p_match_id in number, p_lang in varchar2) return varchar2;

  -- AI_ENABLED setting. After a failed call, a session uses the rules for
  -- 5 minutes before trying AI again; set_enabled resets that.
  function is_enabled return boolean;
  procedure set_enabled (p_enabled in boolean);

  -- (Re)creates the HL_EXPLAIN profile. The credential must already exist
  -- (DBMS_CLOUD.CREATE_CREDENTIAL). Needs EXECUTE on DBMS_CLOUD_AI.
  procedure create_profile (
    p_provider        in varchar2,
    p_credential_name in varchar2,
    p_model           in varchar2 default null);

  -- Why the last AI call in this session fell back (null when it did not)
  function last_error return varchar2;

end hl_ai;
/

create or replace package body hl_ai as

  g_last_error varchar2(4000);
  g_failed_at  date;          -- last failed call in this session

  -- After a failure, skip AI for this long so a page of match cards does not
  -- wait on the provider once per card
  c_backoff constant number := 5 / 1440;  -- 5 minutes

  type t_match is record (
    ui_status     varchar2(20),
    crop_name     varchar2(100),
    grade         varchar2(1),
    grade_req     varchar2(1),
    reason_qty    varchar2(4000),
    reason_grade  varchar2(4000),
    reason_window varchar2(4000),
    reason_dist   varchar2(4000)
  );

  procedure check_lang (p_lang in varchar2) is
  begin
    if p_lang is null or p_lang not in ('en', 'sw') then
      raise_application_error(-20612, 'Language must be en (English) or sw (Kiswahili)');
    end if;
  end check_lang;

  function load (p_match_id in number) return t_match is
    l_m t_match;
  begin
    select ui_status, crop_name, grade, grade_required,
           reason_qty, reason_grade, reason_window, reason_dist
      into l_m
      from hl_match_v
     where match_id = p_match_id;
    return l_m;
  exception
    when no_data_found then
      raise_application_error(-20611, 'Match ' || p_match_id || ' does not exist');
  end load;

  function rules_text (p_m in t_match) return varchar2 is
  begin
    return p_m.reason_qty || '; ' || p_m.reason_grade || '; '
           || p_m.reason_window || '; ' || p_m.reason_dist || '.';
  end rules_text;

  function rules_sentence (p_match_id in number) return varchar2 is
  begin
    return rules_text(load(p_match_id));
  end rules_sentence;

  function fingerprint_of (p_m in t_match, p_lang in varchar2) return varchar2 is
    l_hash  varchar2(64);
    l_input varchar2(4000) := substr(p_lang || '|' || p_m.ui_status || '|' || p_m.crop_name || '|'
                                     || rules_text(p_m), 1, 4000);
  begin
    select rawtohex(standard_hash(l_input, 'SHA256')) into l_hash from dual;
    return l_hash;
  end fingerprint_of;

  function fingerprint (p_match_id in number, p_lang in varchar2) return varchar2 is
  begin
    check_lang(p_lang);
    return fingerprint_of(load(p_match_id), p_lang);
  end fingerprint;

  function is_enabled return boolean is
    l_value hl_settings.setting_value%type;
  begin
    select max(setting_value) into l_value from hl_settings where setting_key = 'AI_ENABLED';
    return nvl(l_value, 0) = 1;
  end is_enabled;

  procedure set_enabled (p_enabled in boolean) is
  begin
    g_failed_at := null;
    update hl_settings
       set setting_value = case when p_enabled then 1 else 0 end
     where setting_key = 'AI_ENABLED';
  end set_enabled;

  function last_error return varchar2 is
  begin
    return g_last_error;
  end last_error;

  function prompt (p_m in t_match, p_lang in varchar2) return clob is
  begin
    return 'You write for HarvestLink, a Kenyan marketplace that matches smallholder farms with buyers '
        || 'before harvest. Rewrite the facts below as ONE plain sentence of at most 35 words saying why '
        || 'this farm fits this order. Use only these facts and keep every number as given; do not add '
        || 'names, advice or anything else. Reply in '
        || case p_lang when 'sw' then 'Kiswahili, for the farmer' else 'English, for the buyer' end
        || ', with the sentence only.' || chr(10)
        || '- Crop: ' || p_m.crop_name || ', Grade ' || p_m.grade
        || ' (order asks for Grade ' || p_m.grade_req || ')' || chr(10)
        || '- Quantity: ' || p_m.reason_qty || chr(10)
        || '- Grade: ' || p_m.reason_grade || chr(10)
        || '- Harvest window: ' || p_m.reason_window || chr(10)
        || '- Distance: ' || p_m.reason_dist || chr(10)
        || '- Status: ' || case p_m.ui_status
                             when 'PENDING'  then 'offered, waiting for the farmer to accept'
                             when 'MATCHED'  then 'the farmer has confirmed'
                             when 'DECLINED' then 'the farmer declined'
                           end;
  end prompt;

  -- Calls Select AI and stores the sentence. Autonomous, so EXPLAIN_MATCH can
  -- run inside a query (the provider call and the insert are not allowed
  -- there otherwise). Returns null on any failure.
  function generate (
    p_match_id    in number,
    p_lang        in varchar2,
    p_fingerprint in varchar2,
    p_prompt      in clob
  ) return varchar2 is
    pragma autonomous_transaction;
    l_out      clob;
    l_sentence varchar2(1000);
  begin
    execute immediate
      'begin :r := dbms_cloud_ai.generate(prompt => :p, profile_name => :n, action => ''chat''); end;'
      using out l_out, in p_prompt, in c_profile;

    -- First non-empty line, without wrapping quotes
    l_sentence := trim(regexp_substr(dbms_lob.substr(l_out, 2000, 1), '[^' || chr(10) || ']+'));
    l_sentence := trim(both '"' from trim(both '''' from l_sentence));
    if l_sentence is null or length(l_sentence) > 400 then
      g_last_error := 'Select AI returned ' || case when l_sentence is null then 'nothing'
                                                    else 'more than one sentence' end;
      rollback;
      return null;
    end if;

    delete from hl_ai_explanations e
     where not exists (select 1 from hl_matches m where m.match_id = e.match_id);
    merge into hl_ai_explanations e
    using (select p_match_id as match_id, p_lang as lang from dual) s
       on (e.match_id = s.match_id and e.lang = s.lang)
     when matched then update set e.fingerprint = p_fingerprint, e.sentence = l_sentence,
                                  e.created_at = systimestamp
     when not matched then insert (match_id, lang, fingerprint, sentence)
                           values (p_match_id, p_lang, p_fingerprint, l_sentence);
    commit;
    g_last_error := null;
    return l_sentence;
  exception
    when others then
      g_last_error := substr(sqlerrm, 1, 4000);
      g_failed_at  := sysdate;
      rollback;
      return null;
  end generate;

  function cached (p_match_id in number, p_lang in varchar2, p_fingerprint in varchar2) return varchar2 is
    l_sentence hl_ai_explanations.sentence%type;
  begin
    select max(sentence) into l_sentence
      from hl_ai_explanations
     where match_id = p_match_id and lang = p_lang and fingerprint = p_fingerprint;
    return l_sentence;
  end cached;

  function explain_match (p_match_id in number, p_lang in varchar2 default 'en') return varchar2 is
    l_m           t_match;
    l_fingerprint varchar2(64);
  begin
    check_lang(p_lang);
    l_m := load(p_match_id);
    if not is_enabled then
      return rules_text(l_m);
    end if;
    l_fingerprint := fingerprint_of(l_m, p_lang);
    return coalesce(cached(p_match_id, p_lang, l_fingerprint),
                    case when g_failed_at is null or sysdate - g_failed_at > c_backoff
                         then generate(p_match_id, p_lang, l_fingerprint, prompt(l_m, p_lang)) end,
                    rules_text(l_m));
  end explain_match;

  function explained_by (p_match_id in number, p_lang in varchar2 default 'en') return varchar2 is
  begin
    check_lang(p_lang);
    if is_enabled and cached(p_match_id, p_lang, fingerprint_of(load(p_match_id), p_lang)) is not null then
      return 'AI';
    end if;
    return 'RULES';
  end explained_by;

  procedure create_profile (
    p_provider        in varchar2,
    p_credential_name in varchar2,
    p_model           in varchar2 default null
  ) is
    l_attributes clob;
  begin
    select json_object('provider'        value lower(p_provider),
                       'credential_name' value upper(p_credential_name),
                       'model'           value p_model,
                       'temperature'     value 0.2,
                       'max_tokens'      value 120
                       absent on null returning clob)
      into l_attributes
      from dual;
    execute immediate 'begin dbms_cloud_ai.drop_profile(profile_name => :n, force => true); end;'
      using c_profile;
    execute immediate
      'begin dbms_cloud_ai.create_profile(profile_name => :n, attributes => :a, '
      || 'description => ''HarvestLink one-sentence match explanations''); end;'
      using c_profile, l_attributes;
  end create_profile;

end hl_ai;
/
