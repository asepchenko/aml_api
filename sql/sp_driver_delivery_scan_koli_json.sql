-- =============================================================================
-- Driver scan koli pada Delivery Packing List (DPL)
-- Tujuan:
--   - log scan per koli ke order_colly_scan_events (idempoten per DPL)
--   - snapshot state ke order_colly_states
--
-- Output JSON disamakan dengan sp_driver_scan_koli_json:
--   { koliId, sttNumber, scannedCount, totalCount, allScanned }
--
-- Deploy: delimiter // -> Execute ALL (manual di HeidiSQL)
-- CALL sp_driver_delivery_scan_koli_json('84', '34', 'AWB123', 'AWB123-1');
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_scan_koli_json//

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_driver_delivery_scan_koli_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_dpl_key` VARCHAR(50),
    IN `p_stt_number` VARCHAR(50),
    IN `p_koli_id` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver scan koli per DPL'
proc: BEGIN
    DECLARE v_packing_list_number VARCHAR(20);
    DECLARE v_dpl_status VARCHAR(30);
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_order_colly_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_event_type VARCHAR(40) DEFAULT 'driver_delivery_scan';
    DECLARE v_event_scope_key VARCHAR(160);
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_scanned TINYINT(1) DEFAULT 0;
    DECLARE v_affected INT DEFAULT 0;
    DECLARE v_now DATETIME;
    DECLARE v_trip_number VARCHAR(30);
    DECLARE v_has_table_events INT DEFAULT 0;
    DECLARE v_has_table_states INT DEFAULT 0;
    DECLARE v_has_table_collies INT DEFAULT 0;
    DECLARE v_driver_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT JSON_OBJECT('error', 'sql_error') AS json;
    END;

    SET v_now = NOW();

    SELECT COUNT(*) INTO v_has_table_events
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'order_colly_scan_events';

    SELECT COUNT(*) INTO v_has_table_states
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'order_colly_states';

    SELECT COUNT(*) INTO v_has_table_collies
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'order_collies';

    IF v_has_table_events = 0 THEN
        SELECT JSON_OBJECT('error', 'missing_table', 'table', 'order_colly_scan_events') AS json;
        LEAVE proc;
    END IF;

    IF v_has_table_states = 0 THEN
        SELECT JSON_OBJECT('error', 'missing_table', 'table', 'order_colly_states') AS json;
        LEAVE proc;
    END IF;

    IF v_has_table_collies = 0 THEN
        SELECT JSON_OBJECT('error', 'missing_table', 'table', 'order_collies') AS json;
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
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_dpl_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        <> CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status') AS json;
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
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    SELECT oc.id
      INTO v_order_colly_id
    FROM order_collies oc
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(oc.barcode_text USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(TRIM(p_koli_id) USING utf8mb4) COLLATE utf8mb4_unicode_ci
    LIMIT 1;

    IF v_order_colly_id IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    SET v_event_scope_key = CONCAT('dpl:', v_packing_list_number);
    SET v_trip_number = CONCAT('DPL:', v_packing_list_number);

    START TRANSACTION;

    INSERT INTO order_colly_scan_events (
        order_colly_id,
        event_type,
        event_scope_key,
        event_time,
        trip_number,
        packing_list_number,
        actor_kind,
        actor_driver_id,
        created_at
    )
    SELECT
        v_order_colly_id,
        v_event_type,
        v_event_scope_key,
        v_now,
        v_trip_number,
        v_packing_list_number,
        'driver',
        CAST(p_user_id AS SIGNED),
        v_now
    FROM DUAL
    WHERE NOT EXISTS (
        SELECT 1
        FROM order_colly_scan_events e
        WHERE e.order_colly_id = v_order_colly_id
          AND CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
          AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
    );

    SET v_affected = ROW_COUNT();

    IF v_affected = 0 THEN
        ROLLBACK;
        SELECT JSON_OBJECT('error', 'already_scanned') AS json;
        LEAVE proc;
    END IF;

    INSERT INTO order_colly_states (
        order_colly_id,
        delivered_packing_list_number,
        updated_at
    ) VALUES (
        v_order_colly_id,
        v_packing_list_number,
        v_now
    )
    ON DUPLICATE KEY UPDATE
        delivered_packing_list_number = VALUES(delivered_packing_list_number),
        updated_at = VALUES(updated_at);

    SELECT COUNT(*)
      INTO v_total_koli
    FROM order_collies oc
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci;

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

    COMMIT;

    SELECT JSON_OBJECT(
        'koliId', p_koli_id,
        'sttNumber', p_stt_number,
        'scannedCount', v_scanned_koli,
        'totalCount', v_total_koli,
        'allScanned', v_all_scanned
    ) AS json;

END//

DELIMITER ;
