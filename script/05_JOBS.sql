BEGIN
  DBMS_SCHEDULER.CREATE_JOB (
    job_name        => 'LND_0005_JOB_DISPATCH',
    job_type        => 'STORED_PROCEDURE',
    job_action      => 'LND_0005_PKG_ORCH.DISPATCH_JOB',
    start_date      => SYSTIMESTAMP,
    repeat_interval => 'FREQ=HOURLY; INTERVAL=1',
    -- repeat_interval => 'FREQ=MINUTELY; INTERVAL=5',
    enabled         => FALSE,
    comments        => 'Prueba de integración LND_0005 cada 1 hora'
  );
END;
/