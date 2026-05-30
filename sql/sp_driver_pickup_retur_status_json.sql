-- Pickup Retur: assigned -> on_trip -> arrived (+ order_trackings)
-- Selaras PickupReturService::driverUpdateStatus
-- CALL sp_driver_pickup_retur_status_json('1', 'RET-xxx', 'start_trip');

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_pickup_retur_status_json//

CREATE PROCEDURE `sp_driver_pickup_retur_status_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_retur_key` VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    IN `p_action` VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver update status pickup retur'
proc: BEGIN
    DECLARE v_retur_number VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_current VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_next VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_tracking_status VARCHAR(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_now DATETIME;
    DECLARE v_actor_id BIGINT;
    DECLARE v_branch_id BIGINT;
    DECLARE v_arrived_city_id BIGINT;
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_order_number VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_city_id BIGINT;
    DECLARE v_key VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_action VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    DECLARE v_pickup_scanned INT DEFAULT 0;
    DECLARE v_arrived_scanned INT DEFAULT 0;
    DECLARE v_pickup_total_koli INT DEFAULT 0;
    DECLARE v_event_scope_key VARCHAR(160) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

    DECLARE cur_orders CURSOR FOR
        SELECT prd.order_number
        FROM pickup_retur_details prd
        WHERE prd.retur_number COLLATE utf8mb4_unicode_ci = v_retur_number
          AND TRIM(prd.order_number) <> '';

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    SET v_now = NOW();
    SET v_actor_id = CAST(p_user_id AS UNSIGNED);
    SET v_key = TRIM(p_retur_key);
    SET v_action = LOWER(TRIM(IFNULL(p_action, '')));

    IF v_action NOT IN ('start_trip', 'arrived') THEN
        SELECT JSON_OBJECT('error', 'validation', 'message', 'action harus start_trip atau arrived') AS json;
        LEAVE proc;
    END IF;

    SELECT pr.retur_number, pr.last_status, pr.branch_id
    INTO v_retur_number, v_current, v_branch_id
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

    SET v_event_scope_key = CONCAT('retur:', v_retur_number);

    IF v_action = 'start_trip' THEN
        IF IFNULL(v_current, '') COLLATE utf8mb4_unicode_ci <> 'assigned' COLLATE utf8mb4_unicode_ci THEN
            SELECT JSON_OBJECT(
                'error', 'invalid_status',
                'message', CONCAT('Status harus assigned untuk start_trip (current: ', IFNULL(v_current, '-'), ')')
            ) AS json;
            LEAVE proc;
        END IF;

        SELECT COUNT(DISTINCT e.order_colly_id)
        INTO v_pickup_scanned
        FROM order_colly_scan_events e
        WHERE CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT('driver_pickup_retur_pickup_scan' USING utf8mb4) COLLATE utf8mb4_unicode_ci
          AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci;

        SELECT COUNT(DISTINCT oc.id)
        INTO v_pickup_total_koli
        FROM pickup_retur_details prd
        INNER JOIN order_collies oc
            ON CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
             = CONVERT(prd.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        WHERE CONVERT(prd.retur_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_retur_number USING utf8mb4) COLLATE utf8mb4_unicode_ci;

        IF v_pickup_scanned > 0 AND v_pickup_scanned < v_pickup_total_koli THEN
            SELECT JSON_OBJECT(
                'error', 'scan_pickup_not_complete',
                'message', CONCAT('Scan pickup belum lengkap (', v_pickup_scanned, '/', v_pickup_total_koli, ')')
            ) AS json;
            LEAVE proc;
        END IF;

        SET v_next = 'on_trip';
        SET v_tracking_status = 'On Process Delivery';
    ELSE
        IF IFNULL(v_current, '') COLLATE utf8mb4_unicode_ci <> 'on_trip' COLLATE utf8mb4_unicode_ci THEN
            SELECT JSON_OBJECT(
                'error', 'invalid_status',
                'message', CONCAT('Status harus on_trip untuk arrived (current: ', IFNULL(v_current, '-'), ')')
            ) AS json;
            LEAVE proc;
        END IF;

        SELECT COUNT(DISTINCT e.order_colly_id)
        INTO v_pickup_scanned
        FROM order_colly_scan_events e
        WHERE CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT('driver_pickup_retur_pickup_scan' USING utf8mb4) COLLATE utf8mb4_unicode_ci
          AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci;

        SELECT COUNT(DISTINCT e.order_colly_id)
        INTO v_arrived_scanned
        FROM order_colly_scan_events e
        WHERE CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT('driver_pickup_retur_arrived_scan' USING utf8mb4) COLLATE utf8mb4_unicode_ci
          AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci;

        IF v_pickup_scanned > 0 AND v_arrived_scanned < v_pickup_scanned THEN
            SELECT JSON_OBJECT(
                'error', 'scan_required_before_arrived',
                'message', CONCAT('Scan arrived wajib karena sudah ada scan pickup (', v_arrived_scanned, '/', v_pickup_scanned, ')')
            ) AS json;
            LEAVE proc;
        END IF;

        SET v_next = 'arrived';
        SET v_tracking_status = 'Transit';
        SET v_arrived_city_id = NULL;
        IF v_branch_id > 0 THEN
            SELECT b.city_id INTO v_arrived_city_id FROM branchs b WHERE b.id = v_branch_id LIMIT 1;
        END IF;
    END IF;

    UPDATE pickup_returs
    SET last_status = v_next,
        updated_at = v_now
    WHERE retur_number COLLATE utf8mb4_unicode_ci = v_retur_number;

    OPEN cur_orders;
    read_loop: LOOP
        FETCH cur_orders INTO v_order_number;
        IF v_done THEN
            LEAVE read_loop;
        END IF;

        SET v_city_id = NULL;

        IF v_action = 'start_trip' THEN
            SELECT COALESCE(a.city_id, b.city_id)
            INTO v_city_id
            FROM order_agents oa
            LEFT JOIN agents a ON a.id = oa.agent_id
            LEFT JOIN branchs b ON b.id = oa.branch_id
            WHERE oa.order_number COLLATE utf8mb4_unicode_ci = v_order_number
              AND oa.sequence = 1
            LIMIT 1;
        ELSE
            SET v_city_id = v_arrived_city_id;
        END IF;

        IF v_city_id IS NOT NULL AND v_city_id > 0 THEN
            INSERT INTO order_trackings (
                order_number, status_date, status_name, filename, city_id,
                recipient, description, is_admin_view, user_id, created_at, updated_at
            ) VALUES (
                v_order_number, v_now, v_tracking_status, NULL, v_city_id,
                NULL, CONCAT('Pickup Retur ', v_tracking_status, ' (', v_retur_number, ')'),
                0, v_actor_id, v_now, v_now
            );
        END IF;
    END LOOP;
    CLOSE cur_orders;

    SELECT JSON_OBJECT(
        'code', v_retur_number,
        'last_status', v_next,
        'next_action', CASE v_next COLLATE utf8mb4_unicode_ci
            WHEN 'on_trip' COLLATE utf8mb4_unicode_ci THEN 'arrived'
            ELSE NULL
        END
    ) AS json;

END//

DELIMITER ;
