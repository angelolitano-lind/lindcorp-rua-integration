-- 1. ELIMINACION DE JOBS
BEGIN
  FOR r IN (
    SELECT job_name 
    FROM user_scheduler_jobs 
    WHERE job_name LIKE 'LND\_0005%' ESCAPE '\'
  ) LOOP
    BEGIN
      DBMS_SCHEDULER.DROP_JOB(job_name => r.job_name, force => TRUE);
      DBMS_OUTPUT.PUT_LINE('Job eliminado: ' || r.job_name);
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error al eliminar job ' || r.job_name || ': ' || SQLERRM);
    END;
  END LOOP;
END;
/

-- 2. ELIMINACION DE PACKAGES
BEGIN
  FOR r IN (
    SELECT object_name, object_type 
    FROM user_objects 
    WHERE object_name LIKE 'LND\_0005%' ESCAPE '\'
      AND object_type = 'PACKAGE'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP PACKAGE ' || r.object_name;
    DBMS_OUTPUT.PUT_LINE('Package eliminado: ' || r.object_name);
  END LOOP;
END;
/

-- 3. ELIMINACION DE VISTAS
BEGIN
  FOR r IN (
    SELECT object_name 
    FROM user_objects 
    WHERE object_name LIKE 'LND\_0005%' ESCAPE '\'
      AND object_type = 'VIEW'
  ) LOOP
    EXECUTE IMMEDIATE 'DROP VIEW ' || r.object_name;
    DBMS_OUTPUT.PUT_LINE('Vista eliminada: ' || r.object_name);
  END LOOP;
END;
/

-- 4. ELIMINACION DE TABLAS (Con Cascade Constraints)
DECLARE
  TYPE t_tab_list IS TABLE OF VARCHAR2(128);
  v_tables t_tab_list := t_tab_list(
    'LND_0005_LOG_DISPATCH',
    'LND_0005_OBX_PO_RECEIPTS',
    'LND_0005_CTL_EXEC',
    'LND_0005_CFG_CONNECTION',
    'LND_0005_CFG_PARAM'
  );
BEGIN
  FOR i IN 1..v_tables.COUNT LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || v_tables(i) || ' CASCADE CONSTRAINTS PURGE';
      DBMS_OUTPUT.PUT_LINE('Tabla eliminada: ' || v_tables(i));
    EXCEPTION
      WHEN OTHERS THEN
        IF SQLCODE <> -942 THEN -- ORA-00942: table or view does not exist
          DBMS_OUTPUT.PUT_LINE('Error eliminando ' || v_tables(i) || ': ' || SQLERRM);
        END IF;
    END;
  END LOOP;
END;
/