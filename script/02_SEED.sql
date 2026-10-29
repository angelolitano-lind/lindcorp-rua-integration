INSERT INTO LND_0005_CFG_PARAM (PARAM_KEY, PARAM_VALUE, DESCRIPTION)
VALUES ('MAX_RETRIES', '5', 'Numero maximo de reintentos por documento');


-- PENDIENTE DE EJECUTAR EN PRODUCCION
INSERT INTO LND_0005_CFG_CONNECTION (
    ENVIRONMENT_CODE, CONNECTION_CODE, DESCRIPTION, BASE_URL, HTTP_METHOD,
    CREDENTIAL_STATIC_ID, APEX_WORKSPACE, TIMEOUT_SECONDS, ACTIVE_IND
) VALUES (
    'PRD', 'MFCS_PO_RECEIPTS_API', 'Endpoint REST MFCS Recepciones OC',
    'https://rex.retail.us-ashburn-1.ocs.oraclecloud.com/rgbu-rex-lind-prd1-mfcs/MerchIntegrations/services/inventory/shipmentsAndReceipts/purchaseOrder/receipts/manage', 'PUT',
    'MFCS_IDCS_API_CREDENTIAL', 'MY_WORKSPACE', 60, 'Y'
);
COMMIT;