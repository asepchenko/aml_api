-- DPL: deliver per STT

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_deliver_item_json//

CREATE PROCEDURE `sp_driver_delivery_deliver_item_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_dpl_key` VARCHAR(50),
    IN `p_order_number` VARCHAR(50),
    IN `p_recipient` VARCHAR(100),
    IN `p_description` VARCHAR(1000),
    IN `p_photo_base64` LONGTEXT,
    IN `p_scan_code` VARCHAR(100),
    IN `p_scan_lat` DECIMAL(10,7),
    IN `p_scan_lng` DECIMAL(10,7),
    IN `p_scan_device` VARCHAR(120)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver deliver satu item DPL'
proc: BEGIN
    DECLARE v_dpl_status VARCHAR(30);
    DECLARE v_packing_list_number VARCHAR(20);
    DECLARE v_detail_id BIGINT;
    DECLARE v_item_status VARCHAR(30);
    DECLARE v_order_status VARCHAR(30);
    DECLARE v_destination BIGINT;
    DECLARE v_remaining INT;
    DECLARE v_now DATETIME;
    DECLARE v_actor_id BIGINT;
    DECLARE v_key VARCHAR(50);
    DECLARE v_order VARCHAR(50);
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_event_type VARCHAR(40) DEFAULT 'driver_delivery_scan';
    DECLARE v_event_scope_key VARCHAR(160);

    SET v_now = NOW();
    SET v_actor_id = CAST(p_user_id AS UNSIGNED);
    SET v_key = TRIM(p_dpl_key);
    SET v_order = TRIM(p_order_number);

    IF p_recipient IS NULL OR TRIM(p_recipient) = '' THEN
        SELECT JSON_OBJECT('error', 'validation', 'message', 'recipient wajib diisi') AS json;
        LEAVE proc;
    END IF;

    SELECT d.last_status, d.packing_list_number
    INTO v_dpl_status, v_packing_list_number
    FROM delivery_packing_lists d
    WHERE d.driver_id = v_actor_id
      AND (
          CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
          OR CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
      )
    LIMIT 1;

    IF v_packing_list_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Packing list tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_dpl_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', 'Packing list sudah Delivered') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_dpl_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT('Open' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', 'Packing list belum On Process Delivery') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_dpl_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        <> CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', CONCAT('Status harus On Process Delivery (current: ', IFNULL(v_dpl_status, '-'), ')')) AS json;
        LEAVE proc;
    END IF;

    SELECT det.id, IFNULL(det.item_status, 'Open')
    INTO v_detail_id, v_item_status
    FROM delivery_packing_list_details det
    WHERE CONVERT(det.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(det.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order USING utf8mb4) COLLATE utf8mb4_unicode_ci
    LIMIT 1;

    IF v_detail_id IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', CONCAT('Order ', v_order, ' tidak ada di DPL')) AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_item_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'already_delivered', 'message', CONCAT('Order ', v_order, ' sudah Delivered')) AS json;
        LEAVE proc;
    END IF;

    SELECT o.last_status, o.destination
    INTO v_order_status, v_destination
    FROM orders o
    WHERE CONVERT(o.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order USING utf8mb4) COLLATE utf8mb4_unicode_ci
    LIMIT 1;

    IF v_order_status IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Order tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    SET v_event_scope_key = CONCAT('dpl:', v_packing_list_number);

    SELECT COUNT(*)
    INTO v_total_koli
    FROM order_collies oc
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    SELECT COUNT(DISTINCT e.order_colly_id)
    INTO v_scanned_koli
    FROM order_colly_scan_events e
    INNER JOIN order_collies oc ON oc.id = e.order_colly_id
    WHERE CONVERT(oc.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(e.event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_event_type USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(e.event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_event_scope_key USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    IF v_total_koli <= 0 THEN
        SELECT JSON_OBJECT('error', 'koli_not_ready', 'message', 'Data koli STT belum tersedia') AS json;
        LEAVE proc;
    END IF;

    IF v_scanned_koli < v_total_koli THEN
        SELECT JSON_OBJECT(
            'error', 'koli_not_fully_scanned',
            'message', CONCAT('Scan koli belum lengkap (', v_scanned_koli, '/', v_total_koli, ')'),
            'scannedCount', v_scanned_koli,
            'totalCount', v_total_koli
        ) AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_order_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'already_delivered', 'message', 'Order sudah Delivered di sistem') AS json;
        LEAVE proc;
    END IF;

    UPDATE delivery_packing_list_details
    SET item_status = 'Delivered',
        delivered_at = v_now,
        delivered_by = v_actor_id,
        delivered_recipient = p_recipient,
        delivered_note = p_description,
        scan_code = p_scan_code,
        scan_lat = p_scan_lat,
        scan_lng = p_scan_lng,
        scan_device = p_scan_device,
        updated_at = v_now
    WHERE id = v_detail_id;

    UPDATE orders
    SET last_status = 'Delivered',
        delivered_date = v_now,
        updated_at = v_now
    WHERE CONVERT(order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_order USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    INSERT INTO order_trackings (
        order_number, status_date, status_name, city_id, photo_base64, recipient, description,
        is_admin_view, user_id, created_at, updated_at
    ) VALUES (
        v_order, v_now, 'Delivered', v_destination, p_photo_base64, p_recipient, p_description,
        0, v_actor_id, v_now, v_now
    );

    SELECT COUNT(*)
    INTO v_remaining
    FROM delivery_packing_list_details det
    WHERE CONVERT(det.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
      AND CONVERT(IFNULL(det.item_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        <> CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    IF v_remaining = 0 THEN
        UPDATE delivery_packing_lists
        SET last_status = 'Delivered',
            delivered_at = v_now,
            delivered_by = v_actor_id,
            updated_at = v_now
        WHERE CONVERT(packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
            = CONVERT(v_packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci;
    END IF;

    SELECT JSON_OBJECT(
        'code', v_packing_list_number,
        'order_number', v_order,
        'item_status', 'Delivered',
        'delivery_foto', IFNULL(p_photo_base64, ''),
        'dpl_status', IF(v_remaining = 0, 'Delivered', 'On Process Delivery'),
        'pending_items', v_remaining,
        'completed', IF(v_remaining = 0, TRUE, FALSE)
    ) AS json;

END//

DELIMITER ;
