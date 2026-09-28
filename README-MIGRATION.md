# Migración Odoo 15 → 16 con OpenUpgrade

## Requisitos
- Docker y Docker Compose
- Contenedor `db-odoo-16` corriendo: `docker-compose up -d db-odoo-16`
- Contenedor `db-odoo-15` corriendo (si vas a copiar desde v15)

> **Nota:** El Dockerfile usa Python 3.7 con Debian Buster (EOL). Se ha configurado automáticamente para usar `archive.debian.org` en lugar de los repositorios normales.

---

## Caso 1: Migrar copiando DB desde v15

Copia la base de datos **y el filestore** desde el contenedor de v15 y ejecuta la migración.

### ⚠️ IMPORTANTE: Identificar los nombres correctos de los contenedores

#### Opción 1: Script automático (recomendado)

```bash
# Ejecutar el script de ayuda para identificar contenedores
./docker/scripts/find_containers.sh 15
```

Este script mostrará todos los contenedores de Odoo 15 y generará el comando completo para ti.

#### Opción 2: Identificación manual

```bash
# Listar contenedores de Odoo 15
docker ps -a | grep odoo-15

# Listar contenedores de PostgreSQL 15
docker ps -a | grep db
```

Necesitas dos nombres:
- **Contenedor PostgreSQL de v15**: Para copiar la base de datos (ej: `solvoerp15_db-odoo-15_1`)
- **Contenedor Odoo de v15**: Para copiar el filestore (ej: `solvoerp15_odoo-15_1`)

### Comando de migración:

```bash
SOURCE_HOST=<CONTENEDOR_POSTGRESQL_V15> \
DB_SOURCE=nombre_db_v15 \
DB_NAME=nombre_db_v16 \
COPY_DB=true \
SOURCE_FILESTORE_CONTAINER=<CONTENEDOR_ODOO_V15> \
docker-compose -f docker-compose-migrate.yml run --rm odoo-16-migrate
```

### Ejemplo real con nombres típicos:

```bash
# Asumiendo:
# - PostgreSQL v15: solvoerp15_db-odoo-15_1
# - Odoo v15: solvoerp15_odoo-15_1
# - DB name: pidea

SOURCE_HOST=solvoerp15_db-odoo-15_1 \
DB_SOURCE=pidea \
DB_NAME=pidea \
COPY_DB=true \
SOURCE_FILESTORE_CONTAINER=solvoerp15_odoo-15_1 \
docker-compose -f docker-compose-migrate.yml run --rm odoo-16-migrate
```

### Si no encuentras los nombres, usa docker inspect:

```bash
# Ver redes Docker
docker network ls

# Ver contenedores en la red de v15
docker network inspect <nombre_red_v15> | grep Name
```

---

## Caso 2: Continuar migración después de un error

Si la migración falló y la DB ya existe en v16, simplemente vuelve a ejecutar:

```bash
DB_NAME=nombre_db \
docker-compose -f docker-compose-migrate.yml run --rm odoo-16-migrate
```

**Ejemplo:**
```bash
DB_NAME=pidea docker-compose -f docker-compose-migrate.yml run --rm odoo-16-migrate
```

> **Nota:** Antes de reintentar, corrige el error (ej: agregar fix en `migration_tools/pre_migration.sql`)

---

## Logs y Dumps

Los archivos se guardan en carpetas accesibles desde el host:

| Ubicación | Contenido |
|-----------|-----------|
| `./migration_logs/` | Logs de cada migración |
| `./migration_dumps/` | Dumps de la DB copiada |

---

## Fixes de Pre-Migración

Si encuentras errores de tablas/columnas faltantes, agrégalos en:

```
migration_tools/pre_migration.sql
```

**Ejemplo** (tabla `product_tag` no existe):
```sql
CREATE TABLE IF NOT EXISTS product_tag (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    color INTEGER DEFAULT 0,
    create_uid INTEGER,
    create_date TIMESTAMP,
    write_uid INTEGER,
    write_date TIMESTAMP
);
```

---

## Rollback

Restaurar desde el backup automático:

```bash
# Ver backups disponibles
ls -la migration_dumps/

# Restaurar (reemplazar NOMBRE_ARCHIVO)
docker exec -i solvoerp16-db-odoo-16-1 dropdb -U odoo nombre_db
docker exec -i solvoerp16-db-odoo-16-1 pg_restore -U odoo -d postgres --create migration_dumps/NOMBRE_ARCHIVO.dump
```

---

## Variables de Entorno

| Variable | Descripción                 | Default | Ejemplo |
|----------|-----------------------------|---------|---------|
| `DB_NAME` | Base de datos destino (v16) | `solvo` | `pidea` |
| `DB_SOURCE` | Base de datos origen (v15)  | - | `pidea` |
| `COPY_DB` | Copiar DB y filestore antes de migrar | `false` | `true` |
| `SOURCE_HOST` | **Contenedor PostgreSQL origen** (no Odoo) | - | `solvoerp15_db-odoo-15_1` |
| `SOURCE_USER` | Usuario PostgreSQL origen   | `odoo` | `odoo` |
| `SOURCE_PASSWORD` | Password PostgreSQL origen  | `odoo` | `odoo` |
| `SOURCE_FILESTORE_CONTAINER` | **Contenedor Odoo origen** para copiar filestore | `solvoerp15_odoo-15_1` | `mi_contenedor_odoo15` |

### ⚠️ Diferencia importante:
- **`SOURCE_HOST`**: Nombre del contenedor de **PostgreSQL** (donde está la base de datos)
- **`SOURCE_FILESTORE_CONTAINER`**: Nombre del contenedor de **Odoo** (donde está el filestore)

Estos son generalmente contenedores diferentes. Usa `docker ps -a` para verificar los nombres exactos.

---

## Troubleshooting

### Error: "PostgreSQL is unavailable - sleeping"

**Síntoma:** El script se queda esperando conexión a PostgreSQL indefinidamente.

**Causas comunes:**

1. **SOURCE_HOST incorrecto**: Pasaste el nombre del contenedor de Odoo en lugar del de PostgreSQL
   ```bash
   # ❌ INCORRECTO
   SOURCE_HOST=solvoerp15_odoo-15_1  # Este es el contenedor de Odoo, NO PostgreSQL
   
   # ✅ CORRECTO
   SOURCE_HOST=solvoerp15_db-odoo-15_1  # Este es el contenedor de PostgreSQL
   ```

2. **Contenedor de PostgreSQL no está corriendo:**
   ```bash
   # Verificar estado
   docker ps | grep db-odoo-15
   
   # Si no está corriendo, iniciarlo
   docker start solvoerp15_db-odoo-15_1
   ```

3. **Contenedores en redes diferentes:** Los contenedores deben estar en la misma red Docker
   ```bash
   # Ver redes de cada contenedor
   docker inspect solvoerp16_odoo-16-migrate | grep NetworkMode
   docker inspect solvoerp15_db-odoo-15_1 | grep NetworkMode
   
   # Si están en redes diferentes, especifica la red en docker-compose-migrate.yml
   ```

**Solución rápida:** Verifica los nombres correctos:
```bash
# Listar TODOS los contenedores (incluyendo detenidos)
docker ps -a

# Buscar específicamente PostgreSQL
docker ps -a | grep -E "(postgres|db-odoo)"

# Buscar específicamente Odoo
docker ps -a | grep odoo
```

### Error: "Source database does not exist"

**Causa:** El nombre de la base de datos es incorrecto.

**Solución:**
```bash
# Conectarse al contenedor de PostgreSQL y listar bases de datos
docker exec -it solvoerp15_db-odoo-15_1 psql -U odoo -l

# O usar este comando directo
docker exec -it solvoerp15_db-odoo-15_1 psql -U odoo -d postgres -c "\l"
```

### Error: "Container not found" (filestore)

**Causa:** `SOURCE_FILESTORE_CONTAINER` tiene un nombre incorrecto.

**Solución:**
```bash
# Verificar nombre exacto del contenedor de Odoo 15
docker ps -a | grep odoo-15

# Usar el nombre completo encontrado
SOURCE_FILESTORE_CONTAINER=nombre_real_del_contenedor
```

---