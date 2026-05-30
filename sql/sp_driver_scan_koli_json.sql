-- =============================================================================
-- Driver scan koli saat transit (load ke trip/manifest)
-- Menggantikan order_scan_loadings (is_scan_transit) dengan:
--   - order_colly_scan_events  (log idempoten per trip+manifest)
--   - order_colly_states       (snapshot loaded_*)
--
-- Deploy: delimiter // → Execute ALL (manual di HeidiSQL)
-- CALL sp_driver_scan_koli_json('1', 'TRIP001', 'MF001', 'AWB123', 'AWB123-1');
-- =============================================================================

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_scan_koli_json//

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_driver_scan_koli_json`(
	IN `p_user_id` VARCHAR(50),
	IN `p_trip_id` VARCHAR(50),
	IN `p_manifest_id` VARCHAR(50),
	IN `p_stt_number` VARCHAR(50),
	IN `p_koli_id` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver scan koli transit — order_colly_scan_events + order_colly_states'
proc: BEGIN
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_order_colly_id BIGINT UNSIGNED DEFAULT NULL;
    DECLARE v_event_type VARCHAR(40) DEFAULT 'driver_transit_load';
    DECLARE v_event_scope_key VARCHAR(160);
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_scanned TINYINT(1) DEFAULT 0;
    DECLARE v_affected INT DEFAULT 0;
    DECLARE v_now DATETIME;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT JSON_OBJECT('error','sql_error') AS json;
    END;

    SET v_now = NOW();
    SET v_event_scope_key = CONCAT('trip:', TRIM(p_trip_id), '|manifest:', TRIM(p_manifest_id));

    SELECT o.order_number
      INTO v_order_number
    FROM orders o
    JOIN manifest_details md
      ON md.order_number = o.order_number
     AND CONVERT(md.manifest_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(TRIM(p_manifest_id) USING utf8mb4) COLLATE utf8mb4_unicode_ci
    JOIN trip_details td
      ON td.manifest_number = md.manifest_number
     AND CONVERT(td.trip_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(TRIM(p_trip_id) USING utf8mb4) COLLATE utf8mb4_unicode_ci
    WHERE CONVERT(o.awb_no USING utf8mb4) COLLATE utf8mb4_unicode_ci
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

    START TRANSACTION;

    INSERT INTO order_colly_scan_events (
        order_colly_id,
        event_type,
        event_scope_key,
        event_time,
        trip_number,
        manifest_number,
        actor_kind,
        actor_driver_id,
        created_at
    )
    SELECT
        v_order_colly_id,
        v_event_type,
        v_event_scope_key,
        v_now,
        TRIM(p_trip_id),
        TRIM(p_manifest_id),
        'driver',
        CAST(p_user_id AS UNSIGNED),
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
        last_trip_number,
        last_manifest_number,
        loaded_at,
        loaded_trip_number,
        loaded_manifest_number,
        updated_at
    ) VALUES (
        v_order_colly_id,
        TRIM(p_trip_id),
        TRIM(p_manifest_id),
        v_now,
        TRIM(p_trip_id),
        TRIM(p_manifest_id),
        v_now
    )
    ON DUPLICATE KEY UPDATE
        last_trip_number = VALUES(last_trip_number),
        last_manifest_number = VALUES(last_manifest_number),
        loaded_at = VALUES(loaded_at),
        loaded_trip_number = VALUES(loaded_trip_number),
        loaded_manifest_number = VALUES(loaded_manifest_number),
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
