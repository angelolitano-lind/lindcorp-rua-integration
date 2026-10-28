CREATE OR REPLACE VIEW LND_0005_VW_PO_RECEIPTS_SRC AS
SELECT 
    h.RTL_LOC_ID || '|' || h.INVCTL_DOCUMENT_ID AS BUSINESS_KEY,
    h.CREATE_DATE_TIMESTAMP AS SOURCE_CHANGE_DATETIME,
    
    -- location: Number
    TO_NUMBER(h.RTL_LOC_ID) AS LOCATION,
    
    -- orderNo: Extraído directamente de las notas rds_trn_trans_notes.NOTE
    TO_NUMBER(
        REGEXP_REPLACE(
            (
                SELECT n.NOTE
                  FROM XO_RDS.rds_inv_invctl_document_lineitm d_note
                  JOIN XO_RDS.rds_trn_trans_notes n
                    ON n.ORGANIZATION_ID = d_note.ORGANIZATION_ID
                   AND n.RTL_LOC_ID      = d_note.LINEITM_RTL_LOC_ID
                   AND n.BUSINESS_DATE   = d_note.LINEITM_BUSINESS_DATE
                   AND n.WKSTN_ID        = d_note.LINEITM_WKSTN_ID
                   AND n.TRANS_SEQ       = d_note.LINEITM_TRANS_SEQ
                 WHERE d_note.INVCTL_DOCUMENT_ID = h.INVCTL_DOCUMENT_ID
                   AND d_note.ORGANIZATION_ID    = h.ORGANIZATION_ID
                   AND d_note.RTL_LOC_ID         = h.RTL_LOC_ID
                   AND ROWNUM = 1
            ), 
            '[^0-9]', ''
        )
    ) AS ORDER_NO,
    
    -- referenceDocumentNo: Number (Máximo 8 dígitos para cumplir restricción < 10 digits en MFCS)
    TO_NUMBER(SUBSTR(REGEXP_REPLACE(h.INVCTL_DOCUMENT_ID, '[^0-9]', ''), -8)) AS REF_DOC_NO,
    
    -- asnNo: String
    'PO_' || NVL(h.PO_REF_NBR, h.INVCTL_DOCUMENT_ID) AS ASN_NO,
    
    -- receiptDetails: Filtra ÚNICAMENTE las líneas asociadas a las transacciones con razón 1010 o 1011
    (
        SELECT JSON_ARRAYAGG(
            JSON_OBJECT(
                'item'                    VALUE TO_CHAR(d.INVENTORY_ITEM_ID),
                'receivedQuantity'        VALUE NVL(d.POSTED_COUNT, NVL(d.UNIT_COUNT, 0)),
                'shippedQuantity'         VALUE NVL(d.EXPECTED_COUNT, 0),
                'receiptTransactionType'  VALUE 'A',
                'receiptDate'             VALUE TO_CHAR(h.CREATE_DATE_TIMESTAMP, 'YYYY-MM-DD'),
                'externalReferenceNo'     VALUE SUBSTR('Rec_' || REGEXP_REPLACE(h.INVCTL_DOCUMENT_ID, '[^0-9]', ''), 1, 17),
                'unitCost'                VALUE NVL(d.UNIT_COST, 0),
                'grossCost'               VALUE NVL(d.POSTED_COST, 0),
                'inventoryIdentifierType' VALUE 'L',
                'inventoryId'             VALUE TO_CHAR(d.INVCTL_DOCUMENT_LINE_NBR)
            )
        )
        FROM XO_RDS.rds_inv_invctl_document_lineitm d
        WHERE d.INVCTL_DOCUMENT_ID = h.INVCTL_DOCUMENT_ID
          AND d.ORGANIZATION_ID    = h.ORGANIZATION_ID
          AND d.RTL_LOC_ID         = h.RTL_LOC_ID
          -- Condición clave: Solo toma las líneas cuya transacción corresponda a razón 1010 o 1011
          AND EXISTS (
              SELECT 1 
                FROM XO_RDS.rds_inv_invctl_trans t
               WHERE t.INVCTL_DOCUMENT_ID = d.INVCTL_DOCUMENT_ID
                 AND t.ORGANIZATION_ID    = d.ORGANIZATION_ID
                 AND t.RTL_LOC_ID         = d.RTL_LOC_ID
                 AND t.TRANS_SEQ          = d.LINEITM_TRANS_SEQ
                 AND t.INVCTL_TRANS_REASCODE IN ('1010', '1011')
          )
    ) AS RECEIPT_DETAILS_JSON
FROM XO_RDS.rds_inv_invctl_document h
WHERE h.STATUS_CODE = 'CLOSED'
  AND EXISTS (
      SELECT 1 
        FROM XO_RDS.rds_inv_invctl_trans t
       WHERE t.INVCTL_DOCUMENT_ID    = h.INVCTL_DOCUMENT_ID
         AND t.ORGANIZATION_ID       = h.ORGANIZATION_ID
         AND t.RTL_LOC_ID            = h.RTL_LOC_ID
         AND t.INVCTL_TRANS_REASCODE IN ('1010', '1011')
  );
/