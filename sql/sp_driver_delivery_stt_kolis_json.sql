-- =============================================================================
-- Driver: daftar koli per STT dalam DPL (untuk layar scan sebelum POST scan/koli)
-- Output:
--   {
--     sttNumber, orderNumber, dplCode, dplStatus,
--     scannedCount, totalCount, allScanned,
--     kolis: [{ koliId, collyNo, isScanned, scannedAt }]
--   }
--
-- Deploy: delimiter // -> Execute ALL (manual di HeidiSQL)
-- CALL sp_driver_delivery_stt_kolis_json('84', '34', 'AWB123');
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_stt_kolis_json//

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_driver_delivery_stt_kolis_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_dpl_key` VARCHAR(50),
    IN `p_stt_number` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver list koli STT dalam DPL untuk scan delivery'
proc: BEGIN
    DECLARE v_packing_list_number VARCHAR(20);
    DECLARE v_dpl_status VARCHAR(30);
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_event_type VARCHAR(40) DEFAULT 'driver_delivery_scan';
    DECLARE v_event_scope_key VARCHAR(160);
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_scanned TINYINT(1) DEFAULT 0;
    DECLARE v_has_table_events INT DEFAULT 0;
    DECLARE v_has_table_collies INT DEFAULT 0;
    DECLARE v_driver_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        SELECT JSON_OBJECT('error', 'sql_error') AS json;
    END;

    SELECT COUNT(*) INTO v_has_table_events
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'order_colly_scan_events';

    SELECT COUNT(*) INTO v_has_table_collies
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'order_collies';

    IF v_has_table_collies = 0 THEN
        SELECT JSON_OBJECT('error', 'missing_table', 'table', 'order_collies') AS json;
        LEAVE proc;
    END IF;

    IF v_has_table_events = 0 THEN
        SELECT JSON_OBJECT('error', 'missing_table', 'table', 'order_colly_scan_events') AS json;
        LEAVE proc;
    END IF;

    SELECT COUNT(*) INTO v_driver_exists
    FROM drivers
    WHERE id = CAST(p_user_id AS SIGNED);

    IF v_driver_exists = 0 THEN
        SELECT JSON_OBJECT('error', 'driver_not_found') AS json;
        LEAVE proc;
    END IF;

    SELECT d.packing_list_number, IFNULL(d.last_status, 'Open')
      INTO v_packing_list_number, v_dpl_status
    FROM delivery_packing_lists d
    WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
      AND (
          CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(TRIM(p_dpl_key) USING utf8mb4) COLLATE utf8mb4_unicode_ci
          OR CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(TRIM(p_dpl_key) USING utf8mb4) COLLATE utf8mb4_unicode_ci
      )
    LIMIT 1;

    IF v_packing_list_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Delivery packing list tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_dpl_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        <> CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT(
            'error', 'invalid_status',
            'message', 'Status DPL harus On Process Delivery untuk scan koli'
        ) AS json;
        LEAVE proc;
    END IF;

    SELECT o.order_number
      INTO v_order_number
    FROM delivery_packing_list_details det
    INNER JOIN orders o
        ON CONVERT(o.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
         = CONVERT(det.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
    WHERE CONVERT(det.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(o.awb_no USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(TRIM(p_stt_number) USING utf8mb4) COLLATE utf8mb4_unicode_ci
    LIMIT 1;

    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT(
            'error', 'not_found',
            'message', CONCAT('STT ', TRIM(p_stt_number), ' tidak ditemukan di DPL ini')
        ) AS json;
        LEAVE proc;
    END IF;

    SET v_event_scope_key = CONCAT('dpl:', v_packing_list_number);

    SELECT COUNT(*)
      INTO v_total_koli
    FROM order_collies oc
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    IF v_total_koli <= 0 THEN
        SELECT JSON_OBJECT(
            'error', 'koli_not_ready',
            'message', 'Data koli STT belum tersedia',
            'sttNumber', TRIM(p_stt_number),
            'orderNumber', v_order_number
        ) AS json;
        LEAVE proc;
    END IF;

    SELECT COUNT(DISTINCT e.order_colly_id)
      INTO v_scanned_koli
    FROM order_colly_scan_events e
    INNER JOIN order_collies oc ON oc.id = e.order_colly_id
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    SET v_all_scanned =
        IF(v_total_koli > 0 AND v_scanned_koli = v_total_koli, 1, 0);

    SELECT JSON_OBJECT(
        'sttNumber', TRIM(p_stt_number),
        'orderNumber', v_order_number,
        'dplCode', v_packing_list_number,
        'dplStatus', v_dpl_status,
        'scannedCount', v_scanned_koli,
        'totalCount', v_total_koli,
        'allScanned', v_all_scanned,
        'kolis', IFNULL((
            SELECT JSON_ARRAYAGG(koli_json)
            FROM (
                SELECT JSON_OBJECT(
                    'koliId', oc.barcode_text,
                    'collyNo', oc.colly_no,
                    'isScanned', IF(sc.order_colly_id IS NOT NULL, TRUE, FALSE),
                    'scannedAt', IFNULL(DATE_FORMAT(sc.event_time, '%Y-%m-%d %H:%i:%s'), NULL)
                ) AS koli_json
                FROM order_collies oc
                LEFT JOIN (
                    SELECT e.order_colly_id, MAX(e.event_time) AS event_time
                    FROM order_colly_scan_events e
                    WHERE CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
                        = CONVERT(v_event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
                      AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
                        = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
                    GROUP BY e.order_colly_id
                ) sc ON sc.order_colly_id = oc.id
                WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                    = CONVERT(v_order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                ORDER BY oc.colly_no ASC
            ) x
        ), JSON_ARRAY())
    ) AS json;

END//

DELIMITER ;
