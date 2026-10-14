-- =============================================================================
-- Automatic re-matching: any saved change to demand or supply re-runs the
-- matching engine once per statement, so APEX forms need no extra button.
-- Status columns are excluded from the column lists because the engine
-- itself updates them. Bulk loads can pause this with
-- hl_match_pkg.g_auto_match := false.
-- =============================================================================

create or replace trigger hl_demands_auto_match
  after insert or delete or update of
    buyer_id, crop_id, grade_required, quantity_kg, price_per_kg,
    need_by_date, delivery_lat, delivery_lon
  on hl_demands
begin
  if hl_match_pkg.g_auto_match then
    hl_match_pkg.rematch_all;
  end if;
end;
/

create or replace trigger hl_harvests_auto_match
  after insert or delete or update of
    farmer_id, crop_id, grade, expected_qty_kg, harvest_from, harvest_to
  on hl_harvests
begin
  if hl_match_pkg.g_auto_match then
    hl_match_pkg.rematch_all;
  end if;
end;
/

create or replace trigger hl_farmers_auto_match
  after update of latitude, longitude
  on hl_farmers
begin
  if hl_match_pkg.g_auto_match then
    hl_match_pkg.rematch_all;
  end if;
end;
/
