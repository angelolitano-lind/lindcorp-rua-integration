PROMPT
PROMPT [1/7] Ejecutando 01_TABLAS.sql ...
@01_TABLAS.sql

PROMPT
PROMPT [2/7] Ejecutando 02_SEED.sql ...
@02_SEED.sql

PROMPT
PROMPT [3/7] Ejecutando 03_VISTAS.sql ...
@03_VISTAS.sql

PROMPT
PROMPT [4/7] Ejecutando 04_PACKAGES.sql ...
@04_PACKAGES.sql

PROMPT
PROMPT [5/7] Ejecutando 05_JOBS.sql ...
@05_JOBS.sql

PROMPT
PROMPT [7/7] Ejecutando 07_VALIDACION.sql ...
@07_VALIDACION.sql

PROMPT
PROMPT ====================================================================
PROMPT Instalación finalizada. 
PROMPT NOTA: Los Jobs fueron creados DESHABILITADOS según norma LIN-DEV-005.
PROMPT Para habilitar en Producción tras certificación, ejecutar:
PROMPT   EXEC DBMS_SCHEDULER.ENABLE('LND_0005_JOB_DISPATCH');
PROMPT ====================================================================