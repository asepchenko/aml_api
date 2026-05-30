-- DPL: deliver per STT

DELIMITER //

DROP PROCEDURE IF EXISTS sp_agent_delivery_confirm_json//

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_agent_delivery_confirm_json`(
	IN `p_user_id` VARCHAR(50),
	IN `p_sttnumber` VARCHAR(50),
	IN `p_confirmed_koli` INT,
	IN `p_photo_base64` LONGTEXT,
	IN `p_recipient_name` VARCHAR(50),
	IN `p_driver_name` VARCHAR(100),
	IN `p_lastlocation` VARCHAR(100),
	IN `p_city` VARCHAR(100)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
proc: BEGIN
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_confirmed_at DATETIME;
    DECLARE v_city_id INT;
    DECLARE v_destination INT;

    /* ===== CEK ORDER ===== */
    SELECT pr.last_status, pr.order_number, pr.destination
    INTO v_current_status, v_order_number, v_destination
    FROM v_order_agents pr
    WHERE pr.awb_no = p_sttnumber
      AND pr.agent_id = p_user_id
    LIMIT 1;

    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    /* ===== CEK STATUS ===== */
    IF v_current_status = 'Delivered' THEN
        SELECT JSON_OBJECT('error', 'already_delivered') AS json;
        LEAVE proc;
    END IF;

    IF v_current_status IN ('Open','Closing','Warehouse') THEN
        SELECT JSON_OBJECT('error', 'not_ready') AS json;
        LEAVE proc;
    END IF;

    /* ===== LOOKUP CITY ===== */
	SELECT id INTO v_city_id
	FROM cities
	WHERE city_name = p_city
	LIMIT 1;
	
	IF v_city_id IS NULL THEN
	    SET v_city_id = v_destination;
	END IF;

    SET v_confirmed_at = NOW();

    START TRANSACTION;

    /* ===== INSERT TRACKING ===== */
    INSERT INTO order_trackings (
        order_number,
        status_date,
        status_name,
        city_id,
        photo_base64,
        recipient,
        last_location,
        last_city,
        user_id,
        driver_name,
        created_at,
        updated_at
    )
    VALUES (
        v_order_number,
        v_confirmed_at,
        'Delivered',
        v_city_id,
        p_photo_base64,
        p_recipient_name,
        p_lastlocation,
        p_city,
        p_user_id,
        p_driver_name,
        NOW(),
        NOW()
    );

    /* ===== UPDATE ORDER ===== */
    UPDATE orders
    SET last_status = 'Delivered',
        delivered_date = v_confirmed_at
    WHERE order_number = v_order_number;

    COMMIT;

    /* ===== RESPONSE ===== */
    SELECT JSON_OBJECT(
        'sttnumber', p_sttnumber,
        'status', 'Delivered',
        'confirmed_koli', p_confirmed_koli,
        'delivery_foto', IFNULL(p_photo_base64, ''),
        'delivery_at', DATE_FORMAT(v_confirmed_at, '%d %b %Y, %H:%i')
    ) AS json;
END//

DELIMITER ;
