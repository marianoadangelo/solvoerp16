# Hop 15 -> 16, before OpenUpgrade (odoo shell 15). Run by the inova_cp upgrade worker on every
# 15 -> 16 migration; safe to run twice.
#
# Odoo enterprise modules that have no code from 16 on (removed or merged upstream) are
# uninstalled here, while the 15 code can still run their uninstall. Done on the last version
# that ships them, so a migration that stops earlier keeps them. web_dashboard views are lost (16 replaces them with spreadsheet dashboards).
NAMES = ['web_dashboard', 'account_predictive_bills', 'purchase_enterprise', 'barcodes_mobile', 'project_timesheet_synchro']
# xmlids of model metadata whose record is already gone (deleted while uninstalling another module
# that owned the field/model) make button_uninstall raise MissingError: drop them first.
for model, table in (('ir.model', 'ir_model'), ('ir.model.fields', 'ir_model_fields'),
                     ('ir.model.fields.selection', 'ir_model_fields_selection'),
                     ('ir.model.constraint', 'ir_model_constraint'), ('ir.model.relation', 'ir_model_relation')):
    env.cr.execute("SELECT to_regclass(%s)", [table])
    if env.cr.fetchone()[0]:
        env.cr.execute(
            "DELETE FROM ir_model_data d WHERE d.model = %s "
            "AND NOT EXISTS (SELECT 1 FROM " + table + " t WHERE t.id = d.res_id)", [model])
        if env.cr.rowcount:
            print('INOVA dangling %s xmlids removed: %s' % (model, env.cr.rowcount))
env.cr.commit()
env.invalidate_all() if hasattr(env, 'invalidate_all') else env.cache.invalidate()
Module = env['ir.module.module']
mods = Module.search([('name', 'in', NAMES), ('state', 'in', ('installed', 'to upgrade'))])
print('INOVA uninstall modules without code from 16 on:', mods.mapped('name'))
if mods:
    mods.button_immediate_uninstall()
    env.cr.commit()
    left = Module.search([('name', 'in', NAMES), ('state', 'not in', ('uninstalled', 'uninstallable'))])
    if left:
        raise Exception('INOVA still installed after the uninstall: %s' % left.mapped('name'))
