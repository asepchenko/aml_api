-- Detail DPL — CONVERT utf8mb4_unicode_ci untuk hindari error 1267

DELIMITER //

DROP PROCEDURE IF EXISTS sp_driver_delivery_detail_json//

CREATE PROCEDURE `sp_driver_delivery_detail_json`(
    IN `p_user_id` VARCHAR(50),
    IN `p_dpl_key` VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT 'Driver detail DPL'
proc: BEGIN
    DECLARE v_found INT DEFAULT 0;
    DECLARE v_key VARCHAR(50);

    SET v_key = TRIM(p_dpl_key);

    SELECT COUNT(*)
    INTO v_found
    FROM delivery_packing_lists d
    WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
      AND (
          CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
          OR CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
      );

    IF v_found = 0 THEN
        SELECT JSON_OBJECT('error', 'not_found', 'message', 'Delivery packing list tidak ditemukan') AS json;
        LEAVE proc;
    END IF;

    SELECT JSON_OBJECT(
        'delivery', (
            SELECT JSON_OBJECT(
                'id', CAST(d.id AS CHAR),
                'code', d.packing_list_number,
                'packing_list_date', DATE_FORMAT(d.packing_list_date, '%Y-%m-%d'),
                'origin', IFNULL(d.origin, '-'),
                'police_number', IFNULL(d.police_number, '-'),
                'total_order', IFNULL(d.total_order, 0),
                'total_kg', IFNULL(d.total_kg, 0),
                'status', IFNULL(d.last_status, 'Open'),
                'status_hpp', IFNULL(d.status_hpp, '-'),
                'on_process_at', IFNULL(DATE_FORMAT(d.on_process_at, '%Y-%m-%d %H:%i:%s'), NULL),
                'delivered_at', IFNULL(DATE_FORMAT(d.delivered_at, '%Y-%m-%d %H:%i:%s'), NULL),
                'next_action', CASE CONVERT(IFNULL(d.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                    WHEN CONVERT('Open' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN 'start_process'
                    WHEN CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN 'deliver_items'
                    ELSE NULL
                END,
                'allowed_actions', CASE CONVERT(IFNULL(d.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                    WHEN CONVERT('Open' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN JSON_ARRAY('start_process')
                    WHEN CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci THEN JSON_ARRAY('deliver_item')
                    ELSE JSON_ARRAY()
                END
            )
            FROM delivery_packing_lists d
            WHERE d.driver_id = CAST(p_user_id AS UNSIGNED)
              AND (
                  CONVERT(CAST(d.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
                  OR CONVERT(d.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
              )
            LIMIT 1
        ),
        'items', IFNULL((
            SELECT JSON_ARRAYAGG(item_json)
            FROM (
                SELECT JSON_OBJECT(
                    'order_number', det.order_number,
                    'awb_no', IFNULL(o.awb_no, '-'),
                    'customer_name', IFNULL(c.customer_name, '-'),
                    'destination', IFNULL(o.destination, NULL),
                    'destination_name', IFNULL(ci.city_name, '-'),
                    'total_colly', IFNULL(o.total_colly, 0),
                    'total_kg', IFNULL(o.total_kg, 0),
                    'item_status', IFNULL(det.item_status, 'Open'),
                    'delivered_at', IFNULL(DATE_FORMAT(det.delivered_at, '%Y-%m-%d %H:%i:%s'), NULL),
                    'delivered_recipient', IFNULL(det.delivered_recipient, NULL),
                    'can_deliver', IF(
                        CONVERT(IFNULL(dpl.last_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                            = CONVERT('On Process Delivery' USING utf8mb4) COLLATE utf8mb4_unicode_ci
                        AND CONVERT(IFNULL(det.item_status, 'Open') USING utf8mb4) COLLATE utf8mb4_unicode_ci
                            <> CONVERT('Delivered' USING utf8mb4) COLLATE utf8mb4_unicode_ci,
                        TRUE,
                        FALSE
                    )
                ) AS item_json
                FROM delivery_packing_list_details det
                INNER JOIN delivery_packing_lists dpl
                    ON CONVERT(dpl.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                     = CONVERT(det.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                LEFT JOIN orders o
                    ON CONVERT(o.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                     = CONVERT(det.order_number USING utf8mb4) COLLATE utf8mb4_unicode_ci
                LEFT JOIN customers c ON c.id = o.customer_id
                LEFT JOIN cities ci ON ci.id = o.destination
                WHERE dpl.driver_id = CAST(p_user_id AS UNSIGNED)
                  AND (
                      CONVERT(CAST(dpl.id AS CHAR) USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
                      OR CONVERT(dpl.packing_list_number USING utf8mb4) COLLATE utf8mb4_unicode_ci = CONVERT(v_key USING utf8mb4) COLLATE utf8mb4_unicode_ci
                  )
                ORDER BY det.id ASC
            ) x
        ), JSON_ARRAY())
    ) AS json;

END//

DELIMITER ;
