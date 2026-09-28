-- Fix: Eliminar duplicado de módulo account_statement_import_qif antes de la migración

-- 1. Eliminar el registro duplicado en ir_model_data
DELETE FROM ir_model_data
WHERE module = 'base'
AND name = 'module_account_statement_import_qif'
AND model = 'ir.module.module';

-- 2. Eliminar el módulo duplicado en ir_module_module
DELETE FROM ir_module_module
WHERE name = 'account_statement_import_qif'
AND state = 'uninstalled';

-- 3. Si ambos módulos existen, eliminar el antiguo
DELETE FROM ir_module_module
WHERE name = 'account_bank_statement_import_qif'
AND EXISTS (
    SELECT 1 FROM ir_module_module
    WHERE name = 'account_statement_import_qif'
);

-- 4. Eliminar también el ir_model_data del módulo antiguo si existe
DELETE FROM ir_model_data
WHERE module = 'base'
AND name = 'module_account_bank_statement_import_qif'
AND model = 'ir.module.module'
AND EXISTS (
    SELECT 1 FROM ir_model_data
    WHERE module = 'base'
    AND name = 'module_account_statement_import_qif'
    AND model = 'ir.module.module'
);

-- Fix: Eliminar duplicados en ir_act_window_view
DELETE FROM ir_act_window_view a
USING ir_act_window_view b
WHERE a.id > b.id
AND a.act_window_id = b.act_window_id
AND a.view_mode = b.view_mode;

-- Fix: Agregar claves primarias a todas las tablas que tengan columna 'id' pero no tengan PRIMARY KEY
DO $$
DECLARE
    rec RECORD;
BEGIN
    FOR rec IN
        SELECT t.tablename
        FROM pg_tables t
        WHERE t.schemaname = 'public'
        AND EXISTS (
            SELECT 1 FROM information_schema.columns c
            WHERE c.table_schema = 'public'
            AND c.table_name = t.tablename
            AND c.column_name = 'id'
        )
        AND NOT EXISTS (
            SELECT 1 FROM pg_constraint pc
            WHERE pc.conrelid = (quote_ident(t.tablename))::regclass
            AND pc.contype = 'p'
        )
    LOOP
        BEGIN
            EXECUTE format('ALTER TABLE %I ADD PRIMARY KEY (id)', rec.tablename);
            RAISE NOTICE 'Added PRIMARY KEY to table: %', rec.tablename;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not add PRIMARY KEY to table %: %', rec.tablename, SQLERRM;
        END;
    END LOOP;
END $$;

-- Fix: prevent duplicate act_window_view for helpdesk analysis actions
DELETE FROM ir_model_data 
WHERE model = 'ir.actions.act_window.view' 
AND res_id IN (
    SELECT id FROM ir_act_window_view
    WHERE view_mode IN ('pivot', 'graph')
    AND act_window_id IN (
        SELECT res_id FROM ir_model_data
        WHERE model = 'ir.actions.act_window'
        AND module = 'helpdesk'
        AND name IN (
            'helpdesk_ticket_action_close_analysis',
            'helpdesk_ticket_action_7days_analysis',
            'helpdesk_ticket_action_success',
            'helpdesk_ticket_action_7dayssuccess',
            'helpdesk_ticket_action_dashboard'
        )
    )
);

DELETE FROM ir_act_window_view
WHERE view_mode IN ('pivot', 'graph')
AND act_window_id IN (
    SELECT res_id FROM ir_model_data
    WHERE model = 'ir.actions.act_window'
    AND module = 'helpdesk'
    AND name IN (
        'helpdesk_ticket_action_close_analysis',
        'helpdesk_ticket_action_7days_analysis',
        'helpdesk_ticket_action_success',
        'helpdesk_ticket_action_7dayssuccess',
        'helpdesk_ticket_action_dashboard'
    )
);

-- Fix: Prevent Odoo 16 subscription constraint crash on old Odoo 15 sale orders
ALTER TABLE sale_order ADD COLUMN IF NOT EXISTS recurrence_id INT;

UPDATE sale_order so
SET recurrence_id = (SELECT MIN(id) FROM sale_subscription_template)
FROM sale_order_line sol
JOIN product_product pp ON sol.product_id = pp.id
JOIN product_template pt ON pp.product_tmpl_id = pt.id
WHERE so.id = sol.order_id
  AND pt.recurring_invoice = true
  AND so.recurrence_id IS NULL;

-- Fix: Clear dangling subscription_id references on account_move_line before 
-- Odoo 16 enforces the new FOREIGN KEY to sale_order
UPDATE account_move_line
SET subscription_id = NULL
WHERE subscription_id IS NOT NULL;

-- Fix: Update model references for subscription close reasons
UPDATE ir_model_data
SET model = 'sale.order.close.reason'
WHERE module = 'sale_subscription' 
  AND name LIKE 'close_reason_%'
  AND model = 'sale.subscription.close.reason';

-- Fix: Update model references for subscription stages
UPDATE ir_model_data
SET model = 'sale.order.stage'
WHERE module = 'sale_subscription' 
  AND model = 'sale.subscription.stage';

-- Fix: Delete old obsolete views referencing deleted subscription models to pass validation
DELETE FROM ir_model_data 
WHERE model = 'ir.ui.view' AND res_id IN (
    SELECT id FROM ir_ui_view WHERE model LIKE 'sale.subscription%'
);

DELETE FROM ir_ui_view 
WHERE model LIKE 'sale.subscription%';




