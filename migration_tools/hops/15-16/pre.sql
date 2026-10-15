-- Hop 15 -> 16, before OpenUpgrade (15 schema). Run by the inova_cp upgrade worker on every 15 -> 16 migration
-- (psql -1 with ON_ERROR_STOP: one transaction, no BEGIN/COMMIT here). Must be safe to run
-- twice (Retry Step restores the checkpoint and runs it again) and on databases without
-- every module: guard tables/columns that may be missing.

-- enterprise account_reports 15 already registers an abstract account.report (no table), so the
-- rename hits ir_model_obj_name_uniq. Drop that abstract registration; 17 account_reports
-- redefines account.report on the renamed model.
DO $$
DECLARE mid int;
BEGIN
  SELECT m.id INTO mid FROM ir_model m
   WHERE m.model = 'account.report'
     AND EXISTS (SELECT 1 FROM ir_model WHERE model = 'account.tax.report')
     AND to_regclass('account_report') IS NULL;
  IF mid IS NULL THEN RETURN; END IF;
  DELETE FROM ir_model_data d USING ir_model_fields f
   WHERE d.model = 'ir.model.fields' AND d.res_id = f.id AND f.model_id = mid;
  DELETE FROM ir_model_data WHERE model = 'ir.model' AND res_id = mid;
  DELETE FROM ir_model WHERE id = mid;
END $$;

-- 15 -> 16: action/view bindings owned by another module than the action (project_enterprise
-- overriding project actions) collide when 16 moves them into the action's own module
-- (act_window_view_unique_mode_per_action). Bindings without xmlid on module actions too.
-- Every module with code recreates its bindings on -u; Studio / exported ones are kept.
CREATE TEMP TABLE _inova_bind AS
SELECT v.id FROM ir_act_window_view v
  JOIN ir_model_data a ON a.model = 'ir.actions.act_window' AND a.res_id = v.act_window_id
 WHERE a.module NOT IN ('__export__', 'studio_customization')
   AND NOT EXISTS (SELECT 1 FROM ir_model_data b
                    WHERE b.model = 'ir.actions.act_window.view' AND b.res_id = v.id
                      AND (b.module = a.module OR b.module IN ('__export__', 'studio_customization')));
DELETE FROM ir_model_data WHERE model = 'ir.actions.act_window.view' AND res_id IN (SELECT id FROM _inova_bind);
DELETE FROM ir_act_window_view WHERE id IN (SELECT id FROM _inova_bind);
DROP TABLE _inova_bind;
