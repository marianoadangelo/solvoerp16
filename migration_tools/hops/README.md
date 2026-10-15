# Per-hop migration fixes

The inova_cp upgrade worker runs these on every migration that goes through the hop.
The folder lives in the repo of the **target** version: the 16 -> 17 hop reads
`migration_tools/hops/16-17/` from the 17 repo.

| File | When | Runs with |
|---|---|---|
| `pre.sql` | before OpenUpgrade | psql on the worker database (source schema) |
| `pre.py` | before OpenUpgrade | `odoo shell` of the source version (`env`; call `env.cr.commit()`) |
| `post.sql` | after OpenUpgrade | psql (target schema) |
| `post.py` | after OpenUpgrade | `odoo shell` of the target version |

They run before the scripts typed on the upgrade form, and again on Retry Step (which
restores the checkpoint first): keep them idempotent and guard tables that may not exist.
The worker reads them from the remote branch at each hop, so a push is enough.

`examples/` next to those files is not executed. It only keeps statements that change
business data and must not run on every migration.
