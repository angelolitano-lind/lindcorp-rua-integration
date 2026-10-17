BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'LND_0005_JOB_5MIN_DISPATCH',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'LND_0005_PKG_ORCH.DISPATCH_JOB',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=MINUTELY; INTERVAL=5',
    enabled         => TRUE,
    comments        => 'Prueba de integración LND_0005 cada 5 minutos'
  );
END;
/