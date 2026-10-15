-- Crop prices from market interviews, and the income uplift provenance that
-- follows the price basis of the crops it uses
declare
  l_prov    varchar2(20);
  l_method  varchar2(4000);
  l_n       number;
  l_c       hl_crops%rowtype;
  l_s       hl_price_summary_v%rowtype;
begin
  -- Demo orders use tomatoes, onions, green peppers and carrots: all FAOSTAT
  select provenance, method into l_prov, l_method from hl_impact_metrics_v where metric_key = 'INCOME_UPLIFT';
  hlt.eq(l_prov, 'sourced', 'income uplift is sourced when every broker price it uses is published');
  hlt.ok(l_method like '%Roma tomatoes KES %FAOSTAT 2024%', 'method names each broker price and its source');
  select count(*) into l_n from hl_crops where broker_price_basis = 'ESTIMATE';
  hlt.eq(l_n, 2, 'French beans and kale are still estimates');

  -- An estimate in use makes the metric demo again
  update hl_crops set broker_price_basis = 'ESTIMATE', broker_price_source = 'Team estimate'
   where crop_name = 'Roma tomatoes';
  select provenance, method into l_prov, l_method from hl_impact_metrics_v where metric_key = 'INCOME_UPLIFT';
  hlt.eq(l_prov, 'demo', 'an estimated broker price in use makes it demo');
  hlt.ok(l_method like '%team estimate%', 'method says so');

  -- Interview answers (Appendix A: broker price vs market price)
  insert into hl_price_observations (observed_on, market, interviewee_role, crop_name, broker_price_kg, market_price_kg, quoted_as)
  values (date '2026-10-15', 'Murang''a town market', 'FARMER', 'Roma tomatoes', 2500 / 64, 60, 'KES 2,500 per 64 kg crate');
  insert into hl_price_observations (observed_on, market, interviewee_role, crop_name, broker_price_kg, market_price_kg)
  values (date '2026-10-15', 'Murang''a town market', 'FARMER', 'Roma tomatoes', 35, 65);
  insert into hl_price_observations (observed_on, market, interviewee_role, crop_name, broker_price_kg, market_price_kg)
  values (date '2026-10-15', 'Murang''a town market', 'BROKER', 'Roma tomatoes', 45, null);
  insert into hl_price_observations (observed_on, market, interviewee_role, crop_name, broker_price_kg)
  values (date '2026-10-15', 'Murang''a town market', 'FARMER', 'Kale (sukuma wiki)', 12);
  hlt.raises('insert into hl_price_observations (observed_on, market, interviewee_role, crop_name) '
             || 'values (sysdate, ''x'', ''FARMER'', ''Onions'');', -2290, 'an observation needs a price');
  hlt.raises('insert into hl_price_observations (observed_on, market, interviewee_role, crop_name, broker_price_kg) '
             || 'values (sysdate, ''x'', ''FARMER'', ''Mangoes'', 10);', -2291, 'an observation needs a known crop');

  select * into l_s from hl_price_summary_v where crop_name = 'Roma tomatoes';
  hlt.ok(l_s.broker_observations = 3 and l_s.market_observations = 2 and round(l_s.broker_median_kg, 2) = 39.06,
         'summary shows counts and medians');

  -- Apply: tomatoes have 3 broker and 2 market prices; kale only 1
  hl_auth.set_user('BUYER_DEMO');
  hlt.raises('declare n pls_integer; begin n := hl_calibration.apply_interview_prices; end;', -20621,
             'only operations can apply prices');
  hl_auth.set_user('OPS_DEMO');
  hlt.eq(hl_calibration.apply_interview_prices(p_min_observations => 2), 2, 'two prices changed (tomato broker and market)');
  hl_auth.set_user(null);
  select * into l_c from hl_crops where crop_name = 'Roma tomatoes';
  hlt.eq(l_c.typical_broker_price_kg, 39.06, 'broker price is the median');
  hlt.eq(l_c.typical_market_price_kg, 62.5, 'market price is the median');
  hlt.eq(l_c.broker_price_source, 'Market interviews, Murang''a town market, 15 Oct 2026: median of 3', 'source recorded');
  hlt.eq(l_c.broker_price_basis, 'INTERVIEW', 'basis recorded');
  select broker_price_basis into l_prov from hl_crops where crop_name = 'Kale (sukuma wiki)';
  hlt.eq(l_prov, 'ESTIMATE', 'crops with too few observations keep their price');

  select provenance, method into l_prov, l_method from hl_impact_metrics_v where metric_key = 'INCOME_UPLIFT';
  hlt.eq(l_prov, 'sourced', 'interview prices make the metric sourced again');
  hlt.ok(l_method like '%Roma tomatoes KES 39.06 (Market interviews%', 'method cites the interviews');
  rollback;
end;
/
