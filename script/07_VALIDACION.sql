-- 1. Inventario completo de objetos de la interfaz LND_0005:
SELECT object_type, object_name, status, last_ddl_time
FROM user_objects
WHERE object_name LIKE 'LND\_0005%' ESCAPE '\'
ORDER BY object_type, object_name;

-- 2. Verificación de Objetos Inválidos (Debe retornar 0 filas):
SELECT object_name, object_type, status
FROM user_objects
WHERE object_name LIKE 'LND\_0005%' ESCAPE '\'
  AND status <> 'VALID';

-- 3. Constraints declarados en la interfaz:
SELECT constraint_name, table_name, constraint_type, status
FROM user_constraints
WHERE constraint_name LIKE '%LND\_0005%' ESCAPE '\'
ORDER BY table_name, constraint_name;

-- 4. Estado de DBMS_SCHEDULER JOBS:
SELECT job_name, enabled, state, last_start_date, next_run_date, run_count, failure_count
FROM user_scheduler_jobs
WHERE job_name LIKE 'LND\_0005%' ESCAPE '\';

-- 5. Verificación de Semillas/Configuración de Parámetros:
SELECT param_key, param_value, description
FROM LND_0005_CFG_PARAM;

-- 6. Verificación de Configuración de Conexiones:
SELECT environment_code, connection_code, connection_type, active_ind, base_url
FROM LND_0005_CFG_CONNECTION
WHERE environment_code = 'PRD';

-- 7. Estado/Salud del Outbox (LND_0005_OBX_PO_RECEIPTS):
SELECT process_status, COUNT(*) AS total_registros
FROM LND_0005_OBX_PO_RECEIPTS
GROUP BY process_status;