-- Pickup Retur: scan koli per STT (pickup dari agent / arrived di tujuan)
-- Output disamakan style scan koli:
--   { koliId, sttNumber, scannedCount, totalCount, allScanned }
--
-- CALL sp_driver_pickup_retur_scan_koli_json('84', 'RET-0001', 'pickup', 'A0037908', 'A0037908-1');
-- CALL sp_driver_pickup_retur_scan_koli_json('84', 'RET-0001', 'arrived', 'A0037908', 'A0037908-1');

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_pickup_retur_scan_koli_json//

CREATE PROCEDURE `sp_driver_pickup_retur_scan_koli_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_retur_key` VARCHAR(50),
    IN `p_scan_phase` VARCHAR(20),
    IN `p_stt_number` VARCHAR(50),
    IN `p_koli_id` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver scan koli pickup retur (pickup/arrived)'
proc: BEGIN
    DECLARE v_retur_number VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_current_status VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_order_number VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_order_colly_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_event_type VARCHAR(40) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_event_scope_key VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_scanned TINYINT(1) DEFAULT 0;
    DECLARE v_affected INT DEFAULT 0;
    DECLARE v_now DATETIME;
    DECLARE v_actor_id BIGINT;
    DECLARE v_phase VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_key VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_trip_number VARCHAR(30);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT JSON_OBJECT('error', 'sql_error') AS json;
    END;

    SET v_now = NOW();
    SET v_actor_id = CAST(p_user_id AS UNSIGNED);
    SET v_phase = LOWER(TRIM(IFNULL(p_scan_phase, '')));
    SET v_key = TRIM(p_retur_key);

    IF v_phase NOT IN ('pickup', 'arrived') THEN
        SELECT JSON_OBJECT('error', 'validation', 'message', 'scan_phase harus pickup atau arrived') AS json;
        LEAVE proc;
    END IF;

    SELECT pr.retur_number, IFNULL(pr.last_status, 'draft')
    INTO v_retur_number, v_current_status
    FROM pickup_returs pr
    WHERE pr.driver_id = v_actor_id
      AND (
          CAST(pr.id AS CHAR) COLLATE utf8mb4_unicode_ci = v_key
          OR pr.retur_number COLLATE utf8mb4_unicode_ci = v_key
      )
    LIMIT 1;

    IF v_retur_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Pickup retur tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    IF v_phase = 'pickup'
       AND v_current_status COLLATE utf8mb4_unicode_ci <> 'assigned' COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', 'Scan pickup hanya boleh saat status assigned') AS json;
        LEAVE proc;
    END IF;

    IF v_phase = 'arrived'
       AND v_current_status COLLATE utf8mb4_unicode_ci <> 'on_trip' COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', 'Scan arrived hanya boleh saat status on_trip') AS json;
        LEAVE proc;
    END IF;

    SELECT o.order_number
    INTO v_order_number
    FROM pickup_retur_details prd
    INNER JOIN orders o
        ON CONVERT(o.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
         = CONVERT(prd.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
    WHERE CONVERT(prd.retur_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_retur_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(o.awb_no USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(TRIM(p_stt_number) USING utf8mb4) COLLATE utf8mb4_unicode_ci
    LIMIT 1;

    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'STT tidak ditemukan di pickup retur') AS json;
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
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Koli tidak ditemukan di STT pickup retur') AS json;
        LEAVE proc;
    END IF;

    IF v_phase = 'pickup' THEN
        SET v_event_type = 'driver_pickup_retur_pickup_scan';
    ELSE
        SET v_event_type = 'driver_pickup_retur_arrived_scan';
    END IF;

    SET v_event_scope_key = CONCAT('retur:', v_retur_number);
    SET v_trip_number = CONCAT('RETUR:', v_retur_number);

    START TRANSACTION;

    INSERT INTO order_colly_scan_events (
        order_colly_id,
        event_type,
        event_scope_key,
        event_time,
        trip_number,
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

    SET v_all_scanned = IF(v_total_koli > 0 AND v_scanned_koli = v_total_koli, 1, 0);

    COMMIT;

    SELECT JSON_OBJECT(
        'phase', v_phase,
        'code', v_retur_number,
        'koliId', p_koli_id,
        'sttNumber', p_stt_number,
        'scannedCount', v_scanned_koli,
        'totalCount', v_total_koli,
        'allScanned', v_all_scanned
    ) AS json;
END//

DELIMITER ;
