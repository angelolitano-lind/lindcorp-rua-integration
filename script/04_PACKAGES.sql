CREATE OR REPLACE PACKAGE LND_0005_PKG_CTRL AS
    FUNCTION GET_PARAM(p_key IN VARCHAR2) RETURN VARCHAR2;
    PROCEDURE START_EXEC(p_job_name IN VARCHAR2, p_exec_id OUT NUMBER);
    PROCEDURE END_EXEC(p_exec_id IN NUMBER, p_read IN NUMBER, p_success IN NUMBER, p_failed IN NUMBER, p_error IN VARCHAR2 DEFAULT NULL);
END LND_0005_PKG_CTRL;
/

CREATE OR REPLACE PACKAGE BODY LND_0005_PKG_CTRL AS
    FUNCTION GET_PARAM(p_key IN VARCHAR2) RETURN VARCHAR2 IS
        v_val VARCHAR2(255);
    BEGIN
        SELECT PARAM_VALUE INTO v_val
          FROM LND_0005_CFG_PARAM
         WHERE INTERFACE_ID = 'LND_0005' AND PARAM_KEY = p_key;
        RETURN v_val;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END GET_PARAM;

    PROCEDURE START_EXEC(p_job_name IN VARCHAR2, p_exec_id OUT NUMBER) IS
    BEGIN
        INSERT INTO LND_0005_CTL_EXEC (JOB_NAME, START_TIME, STATUS)
        VALUES (p_job_name, SYSTIMESTAMP, 'RUNNING')
        RETURNING EXEC_ID INTO p_exec_id;
        COMMIT;
    END START_EXEC;

    PROCEDURE END_EXEC(p_exec_id IN NUMBER, p_read IN NUMBER, p_success IN NUMBER, p_failed IN NUMBER, p_error IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        UPDATE LND_0005_CTL_EXEC
           SET END_TIME        = SYSTIMESTAMP,
               STATUS          = CASE WHEN p_error IS NULL THEN 'SUCCESS' ELSE 'ERROR' END,
               RECORDS_READ    = p_read,
               RECORDS_SUCCESS = p_success,
               RECORDS_FAILED  = p_failed,
               ERROR_MESSAGE   = p_error
         WHERE EXEC_ID = p_exec_id;
        COMMIT;
    END END_EXEC;
END LND_0005_PKG_CTRL;
/

CREATE OR REPLACE PACKAGE LND_0005_PKG_EXTRACT AS
    PROCEDURE INGEST_FROM_SRC(p_read_count OUT NUMBER);
END LND_0005_PKG_EXTRACT;
/

CREATE OR REPLACE PACKAGE BODY LND_0005_PKG_EXTRACT AS
    PROCEDURE INGEST_FROM_SRC(p_read_count OUT NUMBER) IS
        v_payload CLOB;
        v_max_retries NUMBER := TO_NUMBER(NVL(LND_0005_PKG_CTRL.GET_PARAM('MAX_RETRIES'), '5'));
        v_order_location NUMBER;
    BEGIN
        p_read_count := 0;
        FOR r IN (SELECT * FROM LND_0005_VW_PO_RECEIPTS_SRC) LOOP

            SELECT JSON_OBJECT(
                'collectionSize' VALUE 1,
                'items' VALUE JSON_ARRAY(
                    JSON_OBJECT(
                        'appointmentNo' VALUE 1,
                        'receipts' VALUE JSON_ARRAY(
                            JSON_OBJECT(
                                'location'             VALUE r.LOCATION,
                                'orderNo'              VALUE r.ORDER_NO,
                                'referenceDocumentNo' VALUE r.REF_DOC_NO,
                                'asnNo'                VALUE r.ASN_NO,
                                'receiptDetails'       VALUE JSON_QUERY(r.RECEIPT_DETAILS_JSON, '$')
                            )
                        )
                    )
                )
            )
            INTO v_payload
            FROM DUAL;

            BEGIN
                SELECT RTL_LOC_ID 
                  INTO v_order_location
                  FROM XO_RDS.rds_inv_invctl_document
                 WHERE INVCTL_DOCUMENT_ID = TO_CHAR(r.ORDER_NO)
                   AND RTL_LOC_ID         = r.LOCATION
                   AND ROWNUM = 1;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN
                    INSERT INTO LND_0005_OBX_PO_RECEIPTS (
                        BUSINESS_KEY, PAYLOAD_JSON, PROCESS_STATUS, ATTEMPT_COUNT, MAX_ATTEMPTS, 
                        NEXT_ATTEMPT_AT, LAST_ERROR_CODE, LAST_ERROR_MSG
                    )
                    SELECT 
                        r.BUSINESS_KEY, 
                        v_payload,
                        'D', 
                        v_max_retries, 
                        v_max_retries, 
                        SYSTIMESTAMP, 
                        '-20002', 
                        'Error: La tienda no coincide o la orden de compra no existe'
                    FROM DUAL
                    WHERE NOT EXISTS (
                        SELECT 1 FROM LND_0005_OBX_PO_RECEIPTS WHERE BUSINESS_KEY = r.BUSINESS_KEY
                    );

                    CONTINUE;
            END;

            p_read_count := p_read_count + 1;

            INSERT INTO LND_0005_OBX_PO_RECEIPTS (
                BUSINESS_KEY, PAYLOAD_JSON, PROCESS_STATUS, ATTEMPT_COUNT, MAX_ATTEMPTS, NEXT_ATTEMPT_AT
            )
            SELECT 
                r.BUSINESS_KEY, v_payload, 'U', 0, v_max_retries, SYSTIMESTAMP
            FROM DUAL
            WHERE NOT EXISTS (
                SELECT 1 FROM LND_0005_OBX_PO_RECEIPTS WHERE BUSINESS_KEY = r.BUSINESS_KEY
            );
        END LOOP;
        COMMIT;
    END INGEST_FROM_SRC;
END LND_0005_PKG_EXTRACT;
/

CREATE OR REPLACE PACKAGE LND_0005_PKG_DISPATCH AS
    PROCEDURE DISPATCH_BATCH(p_success_count OUT NUMBER, p_failed_count OUT NUMBER);
END LND_0005_PKG_DISPATCH;
/

CREATE OR REPLACE PACKAGE BODY LND_0005_PKG_DISPATCH AS
    PROCEDURE DISPATCH_BATCH(p_success_count OUT NUMBER, p_failed_count OUT NUMBER) IS
        v_conn          LND_0005_CFG_CONNECTION%ROWTYPE;
        v_response      CLOB;
        v_status_code   NUMBER;
        v_start_time    TIMESTAMP;
        v_exec_time_ms  NUMBER;
        v_err_msg       VARCHAR2(4000);
        v_err_code      VARCHAR2(100);
    BEGIN
        p_success_count := 0;
        p_failed_count  := 0;

        SELECT * INTO v_conn
          FROM LND_0005_CFG_CONNECTION
         WHERE ENVIRONMENT_CODE = 'PRD' 
           AND CONNECTION_CODE  = 'MFCS_PO_RECEIPTS_API'
           AND ACTIVE_IND       = 'Y';

        FOR r IN (
            SELECT * 
              FROM LND_0005_OBX_PO_RECEIPTS
             WHERE PROCESS_STATUS IN ('U', 'E')
               AND NEXT_ATTEMPT_AT <= SYSTIMESTAMP
             ORDER BY CREATED_AT ASC
        ) LOOP
            v_start_time  := SYSTIMESTAMP;
            v_status_code := NULL;
            v_response    := NULL;

            BEGIN
                -- Limpiar y establecer cabeceras HTTP necesarias
                APEX_WEB_SERVICE.G_REQUEST_HEADERS.DELETE;
                APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).NAME  := 'Content-Type';
                APEX_WEB_SERVICE.G_REQUEST_HEADERS(1).VALUE := 'application/json';

                -- Llamada REST a MFCS
                v_response := APEX_WEB_SERVICE.MAKE_REST_REQUEST(
                    p_url                  => v_conn.BASE_URL,
                    p_http_method          => v_conn.HTTP_METHOD,
                    p_body                 => r.PAYLOAD_JSON,
                    p_credential_static_id => v_conn.CREDENTIAL_STATIC_ID,
                    p_transfer_timeout     => v_conn.TIMEOUT_SECONDS
                );

                v_status_code  := APEX_WEB_SERVICE.G_STATUS_CODE;
                v_exec_time_ms := EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start_time)) * 1000;

                -- Insertar log de auditoria
                INSERT INTO LND_0005_LOG_DISPATCH (OUTBOX_ID, HTTP_STATUS_CODE, EXECUTION_TIME_MS, REQUEST_PAYLOAD, RESPONSE_PAYLOAD)
                VALUES (r.OUTBOX_ID, v_status_code, v_exec_time_ms, r.PAYLOAD_JSON, v_response);

                IF v_status_code IN (200, 201) THEN
                    UPDATE LND_0005_OBX_PO_RECEIPTS
                       SET PROCESS_STATUS = 'P', UPDATED_AT = SYSTIMESTAMP
                     WHERE OUTBOX_ID = r.OUTBOX_ID;
                    p_success_count := p_success_count + 1;
                ELSE
                    RAISE_APPLICATION_ERROR(-20001, 'HTTP Status Error: ' || v_status_code);
                END IF;

            EXCEPTION
                WHEN OTHERS THEN
                    p_failed_count := p_failed_count + 1;
                    v_exec_time_ms := EXTRACT(SECOND FROM (SYSTIMESTAMP - v_start_time)) * 1000;
                    v_err_code     := TO_CHAR(SQLCODE);
                    v_err_msg      := SUBSTR(SQLERRM || ' | Resp: ' || DBMS_LOB.SUBSTR(v_response, 1000, 1), 1, 4000);

                    INSERT INTO LND_0005_LOG_DISPATCH (OUTBOX_ID, HTTP_STATUS_CODE, EXECUTION_TIME_MS, REQUEST_PAYLOAD, RESPONSE_PAYLOAD, ERROR_STACK)
                    VALUES (r.OUTBOX_ID, NVL(v_status_code, 500), v_exec_time_ms, r.PAYLOAD_JSON, v_response, v_err_msg);

                    UPDATE LND_0005_OBX_PO_RECEIPTS
                       SET ATTEMPT_COUNT   = ATTEMPT_COUNT + 1,
                           PROCESS_STATUS  = CASE WHEN ATTEMPT_COUNT + 1 >= MAX_ATTEMPTS THEN 'D' ELSE 'E' END,
                           NEXT_ATTEMPT_AT = SYSTIMESTAMP + NUMTODSINTERVAL(POWER(2, ATTEMPT_COUNT + 1) * 5, 'MINUTE'),
                           LAST_ERROR_CODE = v_err_code,
                           LAST_ERROR_MSG  = v_err_msg,
                           UPDATED_AT      = SYSTIMESTAMP
                     WHERE OUTBOX_ID = r.OUTBOX_ID;
            END;
            COMMIT;
        END LOOP;
    END DISPATCH_BATCH;
END LND_0005_PKG_DISPATCH;
/

CREATE OR REPLACE PACKAGE LND_0005_PKG_ORCH AS
    PROCEDURE DISPATCH_JOB;
END LND_0005_PKG_ORCH;
/

CREATE OR REPLACE PACKAGE BODY LND_0005_PKG_ORCH AS
    PROCEDURE DISPATCH_JOB IS
        v_exec_id       NUMBER;
        v_read          NUMBER := 0;
        v_success       NUMBER := 0;
        v_failed        NUMBER := 0;
        
        v_workspace     VARCHAR2(100);
        v_workspace_id  NUMBER;
        v_app_id        NUMBER;
    BEGIN
        BEGIN
            SELECT APEX_WORKSPACE 
              INTO v_workspace
              FROM LND_0005_CFG_CONNECTION
             WHERE ENVIRONMENT_CODE = 'PRD' 
               AND CONNECTION_CODE  = 'MFCS_PO_RECEIPTS_API'
               AND ACTIVE_IND       = 'Y'
               AND ROWNUM = 1;
        EXCEPTION
            WHEN OTHERS THEN
                v_workspace := 'MY_WORKSPACE';
        END;

        v_workspace_id := APEX_UTIL.FIND_SECURITY_GROUP_ID(p_workspace => v_workspace);
        IF v_workspace_id IS NOT NULL THEN
            APEX_UTIL.SET_SECURITY_GROUP_ID(p_security_group_id => v_workspace_id);
        END IF;

        BEGIN
            SELECT APPLICATION_ID
              INTO v_app_id
              FROM APEX_APPLICATIONS
             WHERE WORKSPACE = v_workspace
               AND ROWNUM = 1;
        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                v_app_id := 100;
        END;

        APEX_SESSION.CREATE_SESSION(
            p_app_id   => v_app_id,
            p_page_id  => 1,
            p_username => 'SCHEDULER_JOB'
        );

        LND_0005_PKG_CTRL.START_EXEC('LND_0005_JOB_DISPATCH', v_exec_id);
        LND_0005_PKG_EXTRACT.INGEST_FROM_SRC(v_read);
        LND_0005_PKG_DISPATCH.DISPATCH_BATCH(v_success, v_failed);
        LND_0005_PKG_CTRL.END_EXEC(v_exec_id, v_read, v_success, v_failed);

        APEX_SESSION.DELETE_SESSION;

    EXCEPTION
        WHEN OTHERS THEN
            BEGIN
                APEX_SESSION.DELETE_SESSION;
            EXCEPTION
                WHEN OTHERS THEN NULL;
            END;

            LND_0005_PKG_CTRL.END_EXEC(v_exec_id, v_read, v_success, v_failed, SQLERRM);
            RAISE;
    END DISPATCH_JOB;
END LND_0005_PKG_ORCH;
/