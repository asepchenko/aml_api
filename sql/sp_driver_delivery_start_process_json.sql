-- DPL: Open -> On Process Delivery

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_start_process_json//

CREATE PROCEDURE `sp_driver_delivery_start_process_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_dpl_key` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver start process DPL'
proc: BEGIN
    DECLARE v_status VARCHAR(30);
    DECLARE v_packing_list_number VARCHAR(20);
    DECLARE v_now DATETIME;
    DECLARE v_key VARCHAR(50);

    SET v_now = NOW();
    SET v_key = TRIM(p_dpl_key);

    SELECT d.last_status, d.packing_list_number
    INTO v_status, v_packing_list_number
    FROM delivery_packing_lists d
    WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
      AND (
          CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
          OR CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
      )
    LIMIT 1;

    IF v_packing_list_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Packing list tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_status, '') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT('error', 'invalid_status', 'message', 'Packing list sudah Delivered') AS json;
        LEAVE proc;
    END IF;

    IF CONVERT(IFNULL(v_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
        <> CONVERT('Open' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN
        SELECT JSON_OBJECT(
            'error', 'invalid_status',
            'message', CONCAT('Status harus Open (current: ', IFNULL(v_status, '-'), ')')
        ) AS json;
        LEAVE proc;
    END IF;

    UPDATE delivery_packing_lists
    SET last_status = 'On Process Delivery',
        on_process_at = v_now,
        updated_at = v_now
    WHERE CONVERT(packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
        = CONVERT(v_packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci;

    SELECT JSON_OBJECT(
        'code', v_packing_list_number,
        'last_status', 'On Process Delivery',
        'on_process_at', DATE_FORMAT(v_now, '%Y-%m-%d %H:%i:%s'),
        'next_action', 'deliver_items'
    ) AS json;

END//

DELIMITER ;
