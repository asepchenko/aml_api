-- =====================================================
-- AML API - Dummy Stored Procedures
-- =====================================================
-- Semua SP ini adalah dummy untuk development
-- Return format: JSON dengan kolom 'json'
-- =====================================================

DELIMITER //

-- =====================================================
-- AUTH MODULE (001)
-- =====================================================

-- SP: Login user
DROP PROCEDURE IF EXISTS sp_user_login_json//
CREATE PROCEDURE sp_user_login_json(
    IN p_username VARCHAR(255)
)
BEGIN
    SELECT JSON_OBJECT(
        'user', JSON_OBJECT(
            'id', 'USR001',
            'username', p_username,
            'name', 'John Doe',
            'role', 'customer',
            'avatar', 'https://ui-avatars.com/api/?name=John+Doe',
            'email', CONCAT(p_username, '@example.com'),
            'password_hash', '$2a$10$dummy.hash.for.testing.only'
        )
    ) as json;
END//

-- SP: Password reset request
DROP PROCEDURE IF EXISTS sp_password_reset_request_json//
CREATE PROCEDURE sp_password_reset_request_json(
    IN p_email VARCHAR(255)
)
BEGIN
    SELECT JSON_OBJECT(
        'user_id', 'USR001',
        'reset_token', UUID(),
        'expired_at', DATE_ADD(NOW(), INTERVAL 1 HOUR)
    ) as json;
END//

-- =====================================================
-- CUSTOMER MODULE (002)
-- =====================================================

-- SP: Customer Dashboard
DROP PROCEDURE IF EXISTS sp_customer_dashboard_json//
CREATE PROCEDURE sp_customer_dashboard_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    DECLARE v_total_order INT DEFAULT 0;
    DECLARE v_in_progress INT DEFAULT 0;
    DECLARE v_completed INT DEFAULT 0;
    
    -- Count total orders
    SELECT COUNT(*) INTO v_total_order
    FROM orders
    WHERE customer_id = p_user_id AND pickup_date >= CURDATE() - INTERVAL 30 DAY; -- >=  DATE_FORMAT(CURDATE(), '%Y-%m-01') AND pickup_date <= LAST_DAY(CURDATE());
    
    -- Count in progress orders
    SELECT COUNT(*) INTO v_in_progress
    FROM orders
    WHERE customer_id = p_user_id
      AND last_status != 'Delivered' AND pickup_date >= CURDATE() - INTERVAL 30 DAY; -- >=  DATE_FORMAT(CURDATE(), '%Y-%m-01') AND pickup_date <= LAST_DAY(CURDATE());
    
    -- Count completed orders
    SELECT COUNT(*) INTO v_completed
    FROM orders
    WHERE customer_id = p_user_id
      AND last_status = 'Delivered' AND pickup_date >= CURDATE() - INTERVAL 30 DAY; -- >=  DATE_FORMAT(CURDATE(), '%Y-%m-01') AND pickup_date <= LAST_DAY(CURDATE());
    
    -- Return dashboard data
    SELECT JSON_OBJECT(
        'stats', JSON_ARRAY(
            JSON_OBJECT('label', 'Total Order', 'value', CAST(v_total_order AS CHAR)),
            JSON_OBJECT('label', 'Dalam Perjalanan', 'value', CAST(v_in_progress AS CHAR)),
            JSON_OBJECT('label', 'Selesai', 'value', CAST(v_completed AS CHAR))
        ),
        'recentOrders', IFNULL((
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'id', t.awb_no,
                    'destination',t.destination,
                    'status', t.last_status,
                    'lastUpdate', CASE
                        WHEN TIMESTAMPDIFF(MINUTE, t.last_update, NOW()) < 60 
                            THEN CONCAT(TIMESTAMPDIFF(MINUTE, t.last_update, NOW()), ' menit lalu')
                        WHEN TIMESTAMPDIFF(HOUR, t.last_update, NOW()) < 24 
                            THEN CONCAT(TIMESTAMPDIFF(HOUR, t.last_update, NOW()), ' jam lalu')
                        WHEN TIMESTAMPDIFF(DAY, t.last_update, NOW()) < 7 
                            THEN CONCAT(TIMESTAMPDIFF(DAY, t.last_update, NOW()), ' hari lalu')
                        ELSE DATE_FORMAT(t.last_update, '%d %b %Y')
                    END
                )
            )
            FROM (
                   SELECT a.awb_no, concat(b.city_name, ' → ',c.city_name) AS destination, a.last_status, 
						(SELECT MAX(z.updated_at) FROM order_trackings z WHERE z.order_number = a.order_number) AS last_update FROM orders a 
						LEFT JOIN cities b ON a.origin = b.id 
						LEFT JOIN cities c ON a.destination = c.id 
						WHERE a.customer_id = p_user_id
					   ORDER BY a.updated_at DESC
                LIMIT 5
            ) t
        ), JSON_ARRAY())
    ) AS json;
END

-- SP: Customer Orders List
DROP  PROCEDURE IF EXISTS sp_customer_orders_json;
CREATE PROCEDURE 'sp_customer_orders_json'(
	IN 'p_user_id' VARCHAR(50),
	IN 'p_status' VARCHAR(20),
	IN 'p_page' INT,
	IN 'p_limit' INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;
  --  SET p_limit = 5;
  --  SET v_total = 20;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= TOTAL DATA ================= */
   
	SELECT COUNT(*)
    INTO v_total
    FROM orders t
    WHERE t.customer_id = p_user_id
      AND (p_status IS NULL OR p_status = '' OR t.last_status = p_status)
      AND t.pickup_date >= CURDATE() - INTERVAL 30 DAY;
   

    SET v_total_pages = CEIL(v_total * 1.0 / p_limit);

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'orders', IFNULL((
            SELECT JSON_ARRAYAGG(order_data)
            FROM (
                SELECT JSON_OBJECT(
                    'tripId', t.awb_no,
                    'route', CONCAT(x.city_name, ' → ', y.city_name),
                    'pickupDate', DATE_FORMAT(t.pickup_date, '%d %b %Y'),
                    'status', t.last_status,

                    'lastLocation', IFNULL(lt.last_location, '-'),
                    'lastCity', IFNULL(lt.last_city, '-'),
                    'lastUpdate', IFNULL(
                        DATE_FORMAT(lt.updated_at, '%d %b %Y, %H:%i'), '-'
                    ),
                    'tujuan', IFNULL(cb.branch_name,'-'),
                    'address', IFNULL(cb.address,'-'),
                    'receipent', IFNULL(lt.recipient, '-'),

                    'deliveryDate', IFNULL(
                        DATE_FORMAT(t.delivered_date, '%d %b %Y %H:%i'), '-'
                    ),
                    'contains', IFNULL(t.contains, '-'),
                    'volume', IFNULL(CAST(t.total_kg AS CHAR), '0'),
                    'JmlColly', IFNULL(CAST(t.total_colly AS CHAR), '0'),
                    'keterangan', IFNULL(t.description, '-'),

                    'trackings', IFNULL((
                        SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                                'StatusName', th.status_name,
                                'city', th.last_city,
                                'lastLocation', th.last_location,
                                'lastUpdate',
                                DATE_FORMAT(th.updated_at, '%d %b %Y, %H:%i')
                            )
                            ORDER BY th.updated_at ASC
                        )
                        FROM order_trackings th
                        WHERE th.order_number = t.order_number
                    ), JSON_ARRAY())
                ) AS order_data
                FROM orders t
                LEFT JOIN cities x ON t.origin = x.id
                LEFT JOIN cities y ON t.destination = y.id
                LEFT JOIN customer_branchs cb ON t.customer_branch_id = cb.id

                /* ===== LAST TRACKING JOIN ===== */
                LEFT JOIN (
                    SELECT ot.*
                    FROM order_trackings ot
                    JOIN (
                        SELECT order_number, MAX(updated_at) AS max_updated
                        FROM order_trackings
                        GROUP BY order_number
                    ) z
                    ON ot.order_number = z.order_number
                    AND ot.updated_at = z.max_updated
                ) lt ON lt.order_number = t.order_number
                
                WHERE t.customer_id = p_user_id
                  AND (p_status IS NULL OR p_status = '' OR t.last_status = p_status)
                  AND t.pickup_date >= CURDATE() - INTERVAL 30 DAY 

                ORDER BY t.pickup_date DESC
                LIMIT v_offset, p_limit
            ) a
        ), JSON_ARRAY()),

        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json_result;
END

-- SP: Customer Orders List
DROP PROCEDURE IF EXISTS sp_customer_orders_json//
CREATE PROCEDURE sp_customer_orders_json(
    IN p_user_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    SELECT JSON_OBJECT(
        'orders', JSON_ARRAY(
            JSON_OBJECT(
                'tripId', 'TRIP0001',
                'route', 'Jakarta → Medan',
                'status', 'in_progress',
                'driverName', 'Rudi Hartono',
                'truckType', 'Fuso',
                'plateNumber', 'B 9123 KZN',
                'tripDate', '17 Okt 2025',
                'manifests', JSON_ARRAY(
                    JSON_OBJECT(
                        'id', 'MF001',
                        'city', 'Medan',
                        'manifestCode', 'MF-MDN-001',
                        'stts', JSON_ARRAY(
                            JSON_OBJECT(
                                'sttNumber', 'STT20251105',
                                'recipientName', 'Ahmad Sudrajat',
                                'recipientAddress', 'Jl. Merdeka No. 123, Medan',
                                'kolis', JSON_ARRAY(
                                    JSON_OBJECT(
                                        'id', 'STT20251105-1',
                                        'weight', 2.5,
                                        'dimensions', '30x20x15 cm'
                                    )
                                ),
                                'estimatedDelivery', '19 Okt 2025',
                                'lastLocation', 'Jl. Gatot Subroto, Jakarta',
                                'lastCity', 'Jakarta',
                                'lastUpdate', '15 Okt 2025, 14:30'
                            )
                        ),
                        'lastLocation', 'Jl. Gatot Subroto, Jakarta',
                        'lastCity', 'Jakarta',
                        'lastUpdate', '15 Okt 2025, 14:30'
                    )
                )
            )
        ),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', 45,
            'totalPages', 3
        )
    ) as json;
END//

-- SP: Customer Order Tracking
DROP PROCEDURE IF EXISTS sp_customer_order_tracking_json//
CREATE PROCEDURE sp_customer_order_tracking_json(
    IN p_user_id VARCHAR(50),
    IN p_trip_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'tripId', p_trip_id,
        'status', 'in_progress',
        'currentLocation', 'Jl. Gatot Subroto, Jakarta',
        'estimatedArrival', '19 Okt 2025, 10:00',
        'driver', 'Rudi Hartono',
        'driverPhone', '+6281234567890',
        'timeline', JSON_ARRAY(
            JSON_OBJECT(
                'status', 'picked_up',
                'title', 'Paket Diambil',
                'description', 'Paket telah diambil dari gudang',
                'time', '14:30',
                'date', '15 Okt 2025',
                'location', 'Gudang Jakarta',
                'completed', true
            ),
            JSON_OBJECT(
                'status', 'in_transit',
                'title', 'Dalam Perjalanan',
                'description', 'Paket sedang dalam perjalanan ke tujuan',
                'time', '15:00',
                'date', '15 Okt 2025',
                'location', 'Jl. Gatot Subroto, Jakarta',
                'completed', true
            ),
            JSON_OBJECT(
                'status', 'out_for_delivery',
                'title', 'Sedang Dikirim',
                'description', 'Paket sedang dalam perjalanan ke alamat tujuan',
                'time', NULL,
                'date', NULL,
                'location', NULL,
                'completed', false
            ),
            JSON_OBJECT(
                'status', 'delivered',
                'title', 'Terkirim',
                'description', 'Paket telah diterima oleh penerima',
                'time', NULL,
                'date', NULL,
                'location', NULL,
                'completed', false
            )
        )
    ) as json;
END//

-- SP: Customer Pickup Create
DROP  PROCEDURE IF EXISTS sp_customer_pickup_create_json;
CREATE PROCEDURE 'sp_customer_pickup_create_json'(
	IN 'p_user_id' VARCHAR(50),
	IN 'p_data_json' TEXT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    DECLARE v_pickup_id INT;
    DECLARE v_pickup_code VARCHAR(50);
    DECLARE v_year VARCHAR(4);
    DECLARE v_sequence INT;
    
    -- Extract JSON fields
    DECLARE v_customer_name VARCHAR(100);
    DECLARE v_pickup_address TEXT;
    DECLARE v_koli INT;
    DECLARE v_weight_kg DECIMAL(10,2);
    DECLARE v_description TEXT;
    DECLARE v_schedule_date DATE;
    DECLARE v_schedule_time VARCHAR(50);
    DECLARE v_instructions TEXT;
    DECLARE v_pic_name VARCHAR(100);
    DECLARE v_pic_phone VARCHAR(20);
    DECLARE v_pic_whatsapp TINYINT;
    DECLARE v_destination_city VARCHAR(100);
    DECLARE v_destination_address TEXT;
    
    -- Parse JSON data
    SET v_customer_name = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.customer_name'));
    SET v_pickup_address = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.pickup_address'));
    SET v_koli = JSON_EXTRACT(p_data_json, '$.item.koli');
    SET v_weight_kg = JSON_EXTRACT(p_data_json, '$.item.weight_kg');
    SET v_description = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.item.description'));
    SET v_schedule_date = STR_TO_DATE(JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.schedule.date')),'%d %M %Y');
    SET v_schedule_time = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.schedule.time_range'));
    SET v_instructions = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.instructions'));
    SET v_pic_name = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.pic.name'));
    SET v_pic_phone = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.pic.phone'));
    SET v_pic_whatsapp = IFNULL(JSON_EXTRACT(p_data_json, '$.pic.whatsapp'), false);
    SET v_destination_city = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.destination.city'));
    SET v_destination_address = JSON_UNQUOTE(JSON_EXTRACT(p_data_json, '$.destination.address'));
    
    -- Generate pickup code: #PU-YYYY-NNNNNN
    SET v_year = YEAR(NOW());
    
    -- Get next sequence number for this year
    SELECT IFNULL(MAX(CAST(SUBSTRING(request_number, 10) AS UNSIGNED)), 0) + 1 
    INTO v_sequence
    FROM pickup_requests 
    WHERE request_number LIKE CONCAT('PU-', v_year, '-%');
    
    SET v_pickup_code = CONCAT('PU-', v_year, '-', LPAD(v_sequence, 6, '0'));
    
    -- Insert into pickups table
    INSERT INTO pickup_requests (
        request_number,
        user_id,
        customer_id,
        address,
        total_colly,
        total_volume,
        description,
        request_date,
        request_time,
        note_admin,
        pic_name,
        pic_phone,
        pic_whatsapp,
        destination_city,
        destination_address,
        last_status,
        created_at
    ) VALUES (
        v_pickup_code,
        p_user_id,
        p_user_id,
        v_pickup_address,
        v_koli,
        v_weight_kg,
        v_description,
        v_schedule_date,
        v_schedule_time,
        v_instructions,
        v_pic_name,
        v_pic_phone,
        v_pic_whatsapp,
        v_destination_city,
        v_destination_address,
        'pending',
        NOW()
    );
    
    SET v_pickup_id = LAST_INSERT_ID();
    
    -- Return created pickup data
    SELECT JSON_OBJECT(
        'id', CAST(v_pickup_id AS CHAR),
        'code', v_pickup_code,
        'date', DATE_FORMAT(NOW(), '%d %M %Y, %H:%i'),
        'status', 'pending'
    ) AS json;
END

-- SP: Customer Pickup Detail
DELIMITER //

DROP  PROCEDURE IF EXISTS sp_customer_pickup_detail_json;
CREATE PROCEDURE 'sp_customer_pickup_detail_json'(
	IN 'p_user_id' VARCHAR(50),
	IN 'p_pickup_id' VARCHAR(50)
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    SELECT JSON_OBJECT(
        'id', CAST(p.id AS CHAR),
        'code', p.request_number,
        'date', DATE_FORMAT(p.request_date, '%d %M %Y, %H:%i'),
        'customer_name', c.customer_name,
        'pickup_address', p.address,
        'schedule_date', p.request_date,
        'schedule_time', p.request_time,
        'koli', p.total_colly,
        'weight_kg', p.total_volume,
        'weight_display', CONCAT(FORMAT(p.total_volume, 1), ' kg'),
        'description', IFNULL(p.description, '-'),
        'category', IFNULL(p.category, '-'),
        'instructions', IFNULL(p.note_admin, '-'),
        'pic_name', IFNULL(p.pic_name, '-'),
        'pic_phone', IFNULL(p.pic_phone, '-'),
        'pic_whatsapp', IFNULL(p.pic_whatsapp, false),
        'destination_city', IFNULL(p.destination_city, '-'),
        'destination_address', IFNULL(p.destination_address, '-'),
        'status', p.last_status,
        'driver', CASE 
            WHEN d.id IS NOT NULL THEN CONCAT(d.driver_name, ' (', tr.police_number, ')')
            ELSE NULL
        END,
        'eta', '-',
        'confirmed_koli', p.colly_real,
        'pickup_photo', '-', -- p.pickup_photo,
        'confirmed_at', CASE 
            WHEN p.realisasi_date IS NOT NULL 
            THEN DATE_FORMAT(p.realisasi_date, '%d %M %Y, %H:%i')
            ELSE NULL
        END
    ) AS json
    FROM pickup_requests p
    LEFT JOIN drivers d ON p.driver_id = d.id
    LEFT JOIN customers c ON p.customer_id = c.id
    LEFT JOIN trucks tr ON d.truck_id = tr.id
    WHERE p.id = p_pickup_id
      AND p.user_id = p_user_id LIMIT 1;
END

DELIMITER ;

-- SP : Customer Pickup History
DELIMITER //

DROP  PROCEDURE IF EXISTS sp_customer_pickup_history_json;
CREATE PROCEDURE 'sp_customer_pickup_history_json'(
	IN 'p_user_id' VARCHAR(50),
	IN 'p_status' VARCHAR(20),
	IN 'p_page' INT,
	IN 'p_limit' INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;

    /* ================= SAFETY ================= */
    IF p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit < 1 THEN SET p_limit = 10; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= TOTAL DATA ================= */
    SELECT COUNT(*)
    INTO v_total
    FROM pickup_requests p
    WHERE p.user_id = p_user_id
      AND p.last_status = IFNULL(NULLIF(p_status, ''), p.last_status);

    SET v_total_pages = CEIL(v_total * 1.0 / p_limit);

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'pickups', IFNULL((
            SELECT JSON_ARRAYAGG(pickup_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', CAST(p.id AS CHAR),
                    'code', p.request_number,

                    /* === DISPLAY FORMAT (boleh pindah FE kalau mau) === */
                    'date', DATE_FORMAT(p.request_date, '%d %M %Y, %H:%i'),

                    'customer_name', c.customer_name,
                    'pickup_address', p.address,

                    'schedule_date', p.request_date,
                    'schedule_time', p.request_time,

                    'koli', p.total_colly,
                    'weight_kg', p.total_volume,
                    'weight_display', CONCAT(FORMAT(p.total_volume, 1), ' kg'),

                    'description', IFNULL(p.description, '-'),
                    'category', IFNULL(p.category, '-'),
                    'status', p.last_status,

                    'driver',
                        IF(d.id IS NULL,
                            NULL,
                            CONCAT(d.driver_name, ' (', tr.police_number, ')')
                        ),

                    'confirmed_koli', p.colly_real,
                    'confirmed_at',
                        IF(p.realisasi_date IS NULL,
                            NULL,
                            DATE_FORMAT(p.realisasi_date, '%d %M %Y, %H:%i')
                        ),

                    'pickup_photo', '-'
                ) AS pickup_data
                FROM pickup_requests p
                LEFT JOIN customers c ON c.id = p.customer_id
                LEFT JOIN drivers d ON d.id = p.driver_id
                LEFT JOIN trucks tr ON tr.id = d.truck_id

                WHERE p.customer_id = p_user_id
                  AND p.last_status = IFNULL(NULLIF(p_status, ''), p.last_status)

                ORDER BY p.created_at DESC
                LIMIT v_offset, p_limit
            ) q
        ), JSON_ARRAY()),

        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json_result;
END

DELIMITER ;

-- SP: Customer Invoice List
DROP  PROCEDURE IF EXISTS sp_customer_invoice_list_json;
CREATE DEFINER='root'@'localhost' PROCEDURE 'sp_customer_invoice_list_json'(
	IN 'p_user_id' VARCHAR(50),
	IN 'p_month' INT,
	IN 'p_year' INT,
	IN 'p_status' VARCHAR(20),
	IN 'p_page' INT,
	IN 'p_limit' INT
)
LANGUAGE SQL
NOT DETERMINISTIC
CONTAINS SQL
SQL SECURITY DEFINER
COMMENT ''
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_start_date DATE;
    DECLARE v_end_date DATE;

    /* ================= SAFETY ================= */
    IF p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit < 1 THEN SET p_limit = 10; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= DATE RANGE ================= */
    IF p_year IS NOT NULL AND p_month IS NOT NULL THEN
        SET v_start_date = STR_TO_DATE(CONCAT(p_year,'-',p_month,'-01'), '%Y-%m-%d');
        SET v_end_date   = LAST_DAY(v_start_date);
    ELSEIF p_year IS NOT NULL THEN
        SET v_start_date = STR_TO_DATE(CONCAT(p_year,'-01-01'), '%Y-%m-%d');
        SET v_end_date   = STR_TO_DATE(CONCAT(p_year,'-12-31'), '%Y-%m-%d');
    ELSE
        SET v_start_date = NULL;
        SET v_end_date   = NULL;
    END IF;

    /* ================= TOTAL ================= */
    SELECT COUNT(*)
    INTO v_total
    FROM invoices i
    WHERE i.customer_id = p_user_id
      AND i.last_status = IFNULL(NULLIF(p_status,''), i.last_status)
      AND (
            v_start_date IS NULL
            OR i.invoice_date BETWEEN v_start_date AND v_end_date
          );

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'invoices', IFNULL((
            SELECT JSON_ARRAYAGG(invoice_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', i.id,
                    'invoiceNumber', i.invoice_number,
                    'title', i.notes,
                    'amount', i.grand_total,
                    'date', DATE_FORMAT(i.invoice_date, '%d %b %Y'),
                    'month', MONTH(i.invoice_date),
                    'year', YEAR(i.invoice_date),
                    'status', i.last_status,
                    'dueDate', DATE_FORMAT(i.due_date, '%d %b %Y')
                ) AS invoice_data
                FROM invoices i
                WHERE i.customer_id = p_user_id
                  AND i.last_status = IFNULL(NULLIF(p_status,''), i.last_status)
                  AND (
                        v_start_date IS NULL
                        OR i.invoice_date BETWEEN v_start_date AND v_end_date
                      )
                ORDER BY i.invoice_date DESC
                LIMIT v_offset, p_limit
            ) x
        ), JSON_ARRAY()),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total
        )
    ) AS json_result;
END

-- SP: Customer Order History
DROP PROCEDURE IF EXISTS sp_customer_order_history_json//
CREATE PROCEDURE sp_customer_order_history_json(
    IN p_user_id VARCHAR(50),
    IN p_date_from VARCHAR(20),
    IN p_date_to VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    SELECT JSON_OBJECT(
        'orders', JSON_ARRAY(
            JSON_OBJECT(
                'id', 'ORD002',
                'orderDate', '10 Jan 2024',
                'totalSTT', 2,
                'totalKoli', 5,
                'totalWeight', 18.2,
                'status', 'completed',
                'stt','STT01001010'
                'stts', JSON_ARRAY(
                    JSON_OBJECT(
                        'sttNumber', 'STT001234560',
                        'destination', 'Yogyakarta',
                        'recipientName', 'Dewi Sartika',
                        'recipientAddress', 'Jl. Malioboro No. 89, Yogyakarta',
                        'status', 'delivered',
                        'estimatedDelivery', '12 Jan 2024',
                        'actualDelivery', '11 Jan 2024, 16:45',
                        'kolis', JSON_ARRAY(
                            JSON_OBJECT(
                                'id', 'K009',
                                'description', 'Kerajinan - Batik',
                                'weight', 1.0,
                                'dimensions', '50x30x2 cm'
                            )
                        )
                    )
                )
            )
        ),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', 37
        )
    ) as json;
END//

-- SP: Customer Reports
DROP PROCEDURE IF EXISTS sp_customer_reports_json//
DELIMITER //

CREATE PROCEDURE sp_customer_reports_json(
    IN p_customer_id INT
)
proc: BEGIN
    DECLARE v_start_date DATE;
    DECLARE v_end_date DATE;

    /* ================= DATE RANGE: 3 BULAN TERAKHIR ================= */
    SET v_start_date = DATE_SUB(DATE_FORMAT(CURDATE(), '%Y-%m-01'), INTERVAL 2 MONTH);
    SET v_end_date   = LAST_DAY(CURDATE());

SELECT JSON_OBJECT(
        /* ================= CHART DATA ================= */
        'chartData', IFNULL((
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'month', DATE_FORMAT(m.month_date, '%b'),
                    'orders', m.total_orders,
                    'delivered', m.total_delivered
                )
                ORDER BY m.month_date
            )
            FROM (
                SELECT
                    DATE_FORMAT(o.pickup_date, '%Y-%m-01') AS month_date,
                    COUNT(*) AS total_orders,
                    SUM(CASE WHEN o.last_status = 'Delivered' THEN 1 ELSE 0 END) AS total_delivered
                FROM orders o
                WHERE o.customer_id = p_customer_id
                  AND o.pickup_date >= v_start_date
                  AND o.pickup_date <= v_end_date
                GROUP BY DATE_FORMAT(o.pickup_date, '%Y-%m')
            ) m
        ), JSON_ARRAY()),

        /* ================= REPORT LIST ================= */
        'reports', IFNULL((
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'id', r.period_key,
                    'title', r.title,
                    'period', r.period_label
                )
                ORDER BY r.sort_order DESC
            )
            FROM (
                /* laporan bulanan (3 bulan terakhir) */
                SELECT
                    DATE_FORMAT(o.pickup_date, '%Y-%m') AS period_key,
                    CONCAT(
                        'Laporan Pengiriman ',
                        DATE_FORMAT(o.pickup_date, '%M %Y')
                    ) AS title,
                    DATE_FORMAT(o.pickup_date, '%M %Y') AS period_label,
                    YEAR(o.pickup_date) * 100 + MONTH(o.pickup_date) AS sort_order
                FROM orders o
                WHERE o.customer_id = p_customer_id
                  AND o.pickup_date >= v_start_date
                  AND o.pickup_date <= v_end_date
                GROUP BY YEAR(o.pickup_date), MONTH(o.pickup_date)
            ) r
        ), JSON_ARRAY())
    ) AS json;

END//

DELIMITER ;


-- SP: Customer Profile Get
DROP PROCEDURE IF EXISTS sp_customer_profile_get_json//
CREATE PROCEDURE sp_customer_profile_get_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_user_id,
        'username', 'customer1',
        'name', 'Andi Pratama',
        'email', 'andi.customer@gmail.com',
        'avatar', 'https://ui-avatars.com/api/?name=Andi+Pratama',
        'phone', '+6281234567890',
        'address', 'Jl. Contoh No. 123, Jakarta',
        'company', 'PT. Contoh'
    ) as json;
END//

-- SP: Customer Profile Update
DROP PROCEDURE IF EXISTS sp_customer_profile_update_json//
CREATE PROCEDURE sp_customer_profile_update_json(
    IN p_user_id VARCHAR(50),
    IN p_data_json TEXT
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_user_id,
        'name', 'Andi Pratama Updated',
        'email', 'andi.updated@gmail.com',
        'message', 'Profil berhasil diupdate'
    ) as json;
END//

-- =====================================================
-- DRIVER MODULE (003)
-- =====================================================

-- SP: Driver Dashboard
DROP PROCEDURE IF EXISTS sp_driver_dashboard_json//
CREATE PROCEDURE sp_driver_dashboard_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'stats', JSON_ARRAY(
            JSON_OBJECT('label', 'Pickup Request', 'value', 12),
            JSON_OBJECT('label', 'Order Active', 'value', 3)
        ),
        'recentPickups', JSON_ARRAY(
            JSON_OBJECT(
                'id', '1',
                'code', '#PU-2024-001234',
                'customer_name', 'Ahmad Rizki',
                'pickup_address', 'Jl. Sudirman No. 123',
                'schedule_time', '14:30',
                'status', 'pending'
            )
        )
    ) as json;
END//

-- SP: Driver Pickup List
DROP PROCEDURE IF EXISTS sp_driver_pickup_list_json//
CREATE PROCEDURE sp_driver_pickup_list_json(
    IN p_user_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
proc: BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;

    /* ================= SAFETY ================= */
    IF p_page IS NULL OR p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN SET p_limit = 20; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= COUNT TOTAL ================= */
    SELECT COUNT(*)
    INTO v_total
    FROM pickup_requests pr
    WHERE (pr.driver_id = p_user_id OR pr.driver_id IS NULL)
      AND (p_status IS NULL OR p_status = '' OR pr.status = p_status);

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ================= MAIN QUERY ================= */
    SELECT JSON_OBJECT(
        'pickups', IFNULL((
            SELECT JSON_ARRAYAGG(pickup_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', pr.id,
                    'code', pr.pickup_code,
                    'date', DATE_FORMAT(pr.created_at, '%d %b %Y, %H:%i'),
                    'customer_name', IFNULL(pr.customer_name, '-'),
                    'pickup_address', IFNULL(pr.pickup_address, '-'),
                    'schedule_date', IFNULL(DATE_FORMAT(pr.schedule_date, '%d %b %Y'), '-'),
                    'schedule_time', IFNULL(pr.schedule_time, '-'),
                    'koli', IFNULL(pr.koli, 0),
                    'weight_kg', IFNULL(pr.weight_kg, 0),
                    'description', IFNULL(pr.description, '-'),
                    'category', IFNULL(pr.category, '-'),
                    'pic_name', IFNULL(pr.pic_name, '-'),
                    'pic_phone', IFNULL(pr.pic_phone, '-'),
                    'pic_whatsapp', IFNULL(pr.pic_whatsapp, false),
                    'status', pr.status,
                    'eta', pr.eta
                ) AS pickup_data
                FROM pickup_requests pr
                WHERE (pr.driver_id = p_user_id OR pr.driver_id IS NULL)
                  AND (p_status IS NULL OR p_status = '' OR pr.status = p_status)
                ORDER BY 
                    CASE pr.status 
                        WHEN 'pending' THEN 1 
                        WHEN 'in_progress' THEN 2 
                        ELSE 3 
                    END,
                    pr.schedule_date ASC,
                    pr.created_at DESC
                LIMIT v_offset, p_limit
            ) AS pickups_sub
        ), JSON_ARRAY()),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json;
END//

-- SP: Driver Pickup Accept
DROP PROCEDURE IF EXISTS sp_driver_pickup_accept_json//
DELIMITER //

CREATE PROCEDURE sp_driver_pickup_accept_json(
    IN p_user_id   VARCHAR(50),
    IN p_pickup_id VARCHAR(50),
    IN p_email_id  VARCHAR(50)
)
proc: BEGIN
    DECLARE v_driver_name VARCHAR(255);

    /* ================= UPDATE ATOMIC (ANTI DOUBLE ACCEPT) ================= */
    UPDATE pickup_requests
    SET status = 'in_progress',
        driver_id = p_user_id,
        accepted_at = NOW()
    WHERE request_number = p_pickup_id
      AND status = 'pending';

    /* Tidak ada row ter-update */
    IF ROW_COUNT() = 0 THEN

        /* Cek pickup ada atau tidak */
        IF NOT EXISTS (
            SELECT 1
            FROM pickup_requests
            WHERE request_number = p_pickup_id
        ) THEN
            SELECT JSON_OBJECT('error', 'not_found') AS json;
            LEAVE proc;
        ELSE
            SELECT JSON_OBJECT('error', 'already_accepted') AS json;
            LEAVE proc;
        END IF;

    END IF;

    /* ================= GET DRIVER NAME ================= */
    SELECT IFNULL(u.name,'-')
    INTO v_driver_name
    FROM v_user u
    WHERE u.email = p_email_id
    LIMIT 1;

    /* ================= OUTPUT ================= */
    SELECT JSON_OBJECT(
        'id', p_pickup_id,
        'status', 'in_progress',
        'driver', v_driver_name
    ) AS json;

END//

DELIMITER ;


-- SP: Driver Pickup Status Update
DROP PROCEDURE IF EXISTS sp_driver_pickup_status_update_json//
CREATE PROCEDURE sp_driver_pickup_status_update_json(
    IN p_user_id VARCHAR(50),
    IN p_pickup_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_eta VARCHAR(100)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_pickup_id,
        'status', p_status,
        'eta', IFNULL(p_eta, '')
    ) as json;
END//

-- SP: Driver Pickup Confirm
DROP PROCEDURE IF EXISTS sp_driver_pickup_confirm_json//
CREATE PROCEDURE sp_driver_pickup_confirm_json(
    IN p_user_id VARCHAR(50),
    IN p_pickup_id VARCHAR(50),
    IN p_confirmed_koli INT,
    IN p_photo_base64 LONGTEXT,
    IN p_driver_name VARCHAR(100)
)
proc: BEGIN
    DECLARE v_pickup_exists INT DEFAULT 0;
    DECLARE v_current_status VARCHAR(20);
    DECLARE v_confirmed_at DATETIME;

    /* ================= CEK PICKUP EXISTS ================= */
    SELECT COUNT(*), pr.status
    INTO v_pickup_exists, v_current_status
    FROM pickup_requests pr
    WHERE pr.request_number = p_pickup_id;

    /* Pickup tidak ditemukan */
    IF v_pickup_exists = 0 THEN
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    /* Pickup belum in_progress atau sudah done */
    IF v_current_status = 'done' THEN
        SELECT JSON_OBJECT('error', 'already_confirmed') AS json;
        LEAVE proc;
    END IF;

    IF v_current_status = 'pending' THEN
        SELECT JSON_OBJECT('error', 'not_accepted') AS json;
        LEAVE proc;
    END IF;

    /* ================= UPDATE PICKUP ================= */
    SET v_confirmed_at = NOW();

    UPDATE pickup_requests
    SET status = 'done',
        confirmed_koli = p_confirmed_koli,
        pickup_photo = p_photo_base64,
        confirmed_at = v_confirmed_at,
        driver_name = IFNULL(p_driver_name, driver_name)
    WHERE request_number = p_pickup_id;

    /* ================= OUTPUT JSON ================= */
    SELECT JSON_OBJECT(
        'id', p_pickup_id,
        'status', 'done',
        'confirmed_koli', p_confirmed_koli,
        'pickup_photo', IFNULL(p_photo_url, ''),
        'confirmed_at', DATE_FORMAT(v_confirmed_at, '%d %b %Y, %H:%i')
    ) AS json;
END//

-- SP: Driver Packages
DROP PROCEDURE IF EXISTS sp_driver_packages_json//
CREATE PROCEDURE sp_driver_packages_json(
    IN p_user_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
proc: BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;
    DECLARE v_driver_id INT;

    /* ================= SAFETY ================= */
    IF p_page IS NULL OR p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN SET p_limit = 20; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= GET DRIVER ID ================= */
    SELECT d.id INTO v_driver_id
    FROM drivers d
    WHERE d.user_id = p_user_id
    LIMIT 1;

    /* ================= COUNT TOTAL ================= */
    SELECT COUNT(DISTINCT t.trip_number)
    INTO v_total
    FROM trips t
    WHERE t.driver_id = v_driver_id
      AND (p_status IS NULL OR p_status = '' OR t.status = p_status);

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ================= MAIN QUERY ================= */
    SELECT JSON_OBJECT(
        'trips', IFNULL((
            SELECT JSON_ARRAYAGG(trip_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', t.trip_number,
                    'route', CONCAT(
                        IFNULL((SELECT c.city_name FROM cities c WHERE c.id = t.origin LIMIT 1), '-'),
                        ' → ',
                        IFNULL((SELECT c.city_name FROM cities c WHERE c.id = t.destination LIMIT 1), '-')
                    ),
                    'status', t.status,
                    'driverName', IFNULL((
                        SELECT d.driver_name 
                        FROM drivers d 
                        WHERE d.id = t.driver_id 
                        LIMIT 1
                    ), '-'),
                    'truckType', IFNULL(t.truck_type, '-'),
                    'plateNumber', IFNULL(t.plate_number, '-'),
                    'tripDate', DATE_FORMAT(t.trip_date, '%d %b %Y'),
                    'manifests', IFNULL((
                        SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                                'id', m.id,
                                'manifestCode', m.manifest_number,
                                'city', IFNULL((SELECT c.city_name FROM cities c WHERE c.id = m.destination LIMIT 1), '-'),
                                'lastLocation', IFNULL(t.last_location, '-'),
                                'lastCity', IFNULL((SELECT c.city_name FROM cities c WHERE c.id = t.current_city_id LIMIT 1), '-'),
                                'lastUpdate', IFNULL(DATE_FORMAT(t.last_update, '%d %b %Y, %H:%i'), '-')
                            )
                        )
                        FROM manifests m
                        JOIN trip_details td ON td.manifest_number = m.manifest_number
                        WHERE td.trip_number = t.trip_number
                    ), JSON_ARRAY())
                ) AS trip_data
                FROM trips t
                WHERE t.driver_id = v_driver_id
                  AND (p_status IS NULL OR p_status = '' OR t.status = p_status)
                ORDER BY 
                    CASE t.status 
                        WHEN 'in_progress' THEN 1 
                        WHEN 'pending' THEN 2 
                        ELSE 3 
                    END,
                    t.trip_date DESC
                LIMIT v_offset, p_limit
            ) AS trips_sub
        ), JSON_ARRAY()),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json;
END//

-- SP: Driver Scan Koli
DROP PROCEDURE IF EXISTS sp_driver_scan_koli_json//
CREATE PROCEDURE sp_driver_scan_koli_json(
    IN p_user_id VARCHAR(50),
    IN p_koli_id VARCHAR(50),
    IN p_city_name VARCHAR(255),
    IN p_last_location TEXT
)
proc: BEGIN
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_trip_number VARCHAR(50);
    DECLARE v_awb_no VARCHAR(50);
    DECLARE v_koli_exists INT DEFAULT 0;
    DECLARE v_is_scanned INT DEFAULT 0;
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_completed BOOLEAN DEFAULT FALSE;

    /* ================= CEK KOLI EXISTS ================= */
    SELECT os.order_number, os.is_scanned, o.awb_no
    INTO v_order_number, v_is_scanned, v_awb_no
    FROM order_scan_loadings os
    JOIN orders o ON o.order_number = os.order_number
    WHERE os.colly_number = p_koli_id
    LIMIT 1;

    /* Koli tidak ditemukan */
    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    /* ================= GET TRIP NUMBER ================= */
    SELECT td.trip_number INTO v_trip_number
    FROM manifest_details md
    JOIN trip_details td ON td.manifest_number = md.manifest_number
    WHERE md.order_number = v_order_number
    LIMIT 1;

    /* ================= UPDATE SCAN STATUS ================= */
    UPDATE order_scan_loadings
    SET is_scanned = 1,
        scanned_at = NOW(),
        scanned_by = p_user_id,
        scan_city = p_city_name,
        scan_location = p_last_location
    WHERE colly_number = p_koli_id;

    /* ================= UPDATE TRIP LOCATION ================= */
    UPDATE trips
    SET last_location = p_last_location,
        last_city = p_city_name,
        last_update = NOW()
    WHERE trip_number = v_trip_number;

    /* ================= HITUNG STATISTIK ================= */
    SELECT 
        COUNT(*),
        SUM(CASE WHEN os.is_scanned = 1 THEN 1 ELSE 0 END)
    INTO v_total_koli, v_scanned_koli
    FROM order_scan_loadings os
    WHERE os.order_number = v_order_number;

    /* Cek apakah semua sudah di-scan */
    IF v_scanned_koli >= v_total_koli THEN
        SET v_all_completed = TRUE;
    END IF;

    /* ================= OUTPUT JSON ================= */
    SELECT JSON_OBJECT(
        'koli_id', p_koli_id,
        'stt_number', v_awb_no,
        'trip_id', IFNULL(v_trip_number, '-'),
        'scanned_count', v_scanned_koli,
        'total_count', v_total_koli,
        'all_completed', v_all_completed,
        'location', JSON_OBJECT(
            'city', p_city_name,
            'address', p_last_location
        )
    ) AS json;
END//

-- SP: Driver STT Hold
DROP PROCEDURE IF EXISTS sp_driver_stt_hold_json//
CREATE PROCEDURE sp_driver_stt_hold_json(
    IN p_user_id VARCHAR(50),
    IN p_trip_id VARCHAR(50),
    IN p_stt_number VARCHAR(50),
    IN p_reason VARCHAR(500)
)
BEGIN
    SELECT JSON_OBJECT(
        'stt_number', p_stt_number,
        'is_hold', true,
        'hold_reason', p_reason
    ) as json;
END//

-- SP: Driver Location Update
DROP PROCEDURE IF EXISTS sp_driver_location_update_json//
CREATE PROCEDURE sp_driver_location_update_json(
    IN p_user_id VARCHAR(50),
    IN p_trip_id VARCHAR(50),
    IN p_latitude DECIMAL(10,6),
    IN p_longitude DECIMAL(10,6),
    IN p_address TEXT,
    IN p_city VARCHAR(100),
    IN p_region VARCHAR(100),
    IN p_timestamp DATETIME
)
BEGIN
    DECLARE v_city_id INT;
    DECLARE v_updated_stts JSON;
    
    -- Ambil city_id berdasarkan nama kota
    SELECT id INTO v_city_id FROM cities WHERE city_name LIKE CONCAT('%', p_city, '%') LIMIT 1;
    
    -- Update lokasi terakhir di tabel trips
    UPDATE trips 
    SET last_location = p_address,
        last_city = p_city,
        last_update = p_timestamp,
        updated_at = NOW()
    WHERE trip_number = p_trip_id;
    
    -- Insert tracking baru "On Process Delivery" untuk semua order dalam trip tersebut
    INSERT INTO order_trackings (
        order_number, 
        status_date, 
        status_name, 
        city_id, 
        description, 
        user_id, 
        created_at, 
        updated_at
    )
    SELECT 
        md.order_number, 
        p_timestamp, 
        'On Process Delivery', 
        v_city_id, 
        CONCAT(p_address, ' (', p_latitude, ', ', p_longitude, ')'), 
        p_user_id, 
        NOW(), 
        NOW()
    FROM trip_details td
    JOIN manifest_details md ON td.manifest_number = md.manifest_number
    WHERE td.trip_number = p_trip_id;
    
    -- Update status terakhir di tabel orders
    UPDATE orders o
    JOIN manifest_details md ON o.order_number = md.order_number
    JOIN trip_details td ON md.manifest_number = td.manifest_number
    SET o.last_status = 'On Process Delivery',
        o.updated_at = NOW()
    WHERE td.trip_number = p_trip_id;

    -- Ambil daftar STT (awb_no) yang diupdate untuk dikembalikan dalam response
    SELECT JSON_ARRAYAGG(awb_no) INTO v_updated_stts
    FROM (
        SELECT DISTINCT o.awb_no
        FROM orders o
        JOIN manifest_details md ON o.order_number = md.order_number
        JOIN trip_details td ON md.manifest_number = td.manifest_number
        WHERE td.trip_number = p_trip_id
    ) AS tmp;

    -- Return response sesuai format dokumentasi
    SELECT JSON_OBJECT(
        'success', true,
        'responseCode', '2000300',
        'responseMessage', 'Location berhasil diupdate',
        'data', JSON_OBJECT(
            'trip_id', p_trip_id,
            'location', JSON_OBJECT(
                'latitude', p_latitude,
                'longitude', p_longitude,
                'address', p_address,
                'city', p_city,
                'region', p_region,
                'timestamp', DATE_FORMAT(p_timestamp, '%Y-%m-%dT%H:%i:%sZ')
            ),
            'updated_stts', IFNULL(v_updated_stts, JSON_ARRAY())
        )
    ) as json;
END//

-- SP: Driver Notifications
DELIMITER //

DROP  PROCEDURE IF EXISTS sp_driver_notifications_json;
CREATE PROCEDURE sp_driver_notifications_json  (
    IN p_user_id INT,
    IN p_is_read TINYINT(1),
    IN p_type VARCHAR(50),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;
    DECLARE v_unread_count INT DEFAULT 0;

    SET p_page = IF(p_page < 1, 1, p_page);
    SET p_limit = IF(p_limit < 1, 10, p_limit);
    SET v_offset = (p_page - 1) * p_limit;

    /* ===== TOTAL DATA ===== */
    SELECT COUNT(*)
    INTO v_total
    FROM notification_androids na
    WHERE na.user_id = p_user_id
      AND na.role = 'driver'
      AND na.notif_date >= CURDATE() - INTERVAL 30 DAY
      AND (p_is_read IS NULL OR na.is_read = p_is_read)
              AND (p_type IS NULL OR na.notif_type = p_type);

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ===== UNREAD COUNT ===== */
    SELECT COUNT(*)
    INTO v_unread_count
    FROM notification_androids
    WHERE user_id = p_user_id
      AND role = 'driver'
      AND is_read = 0
      AND notif_date >= CURDATE() - INTERVAL 30 DAY;

    /* ===== MAIN JSON ===== */
    SELECT JSON_OBJECT(
        'notifications',
        COALESCE((
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'id', n.id,
                    'type', n.notif_type,
                    'title', n.title,
                    'content', n.message,
                    'timestamp', DATE_FORMAT(n.notif_date, '%Y-%m-%dT%H:%i:%sZ'),
                    'is_read', IF(n.is_read = 1, TRUE, FALSE),
                    'pickup_id', n.content_id,
                    'metadata', JSON_OBJECT(
                        'pickup_code', p.request_number,
                        'schedule_date', DATE_FORMAT(p.request_date, '%d %M %Y'),
                        'schedule_time', DATE_FORMAT(p.request_time, '%H:%i')
                    )
                )
            )
            FROM notification_androids n
            LEFT JOIN pickup_requests p ON p.id = n.content_id
            WHERE n.user_id = p_user_id
              AND n.role = 'driver'
              AND n.notif_date >= CURDATE() - INTERVAL 30 DAY
              AND (p_is_read IS NULL OR n.is_read = p_is_read)
              AND (p_type IS NULL OR n.notif_type = p_type)
            ORDER BY n.notif_date DESC
            LIMIT v_offset, p_limit
        ), JSON_ARRAY()),

        'unread_count', v_unread_count,

        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json_result;
END//

DELIMITER ;


-- SP: Driver Notification Read
DROP PROCEDURE IF EXISTS sp_driver_notification_read_json//
CREATE PROCEDURE sp_driver_notification_read_json(
    IN p_user_id INT,
    IN p_notification_id INT
)
BEGIN
    UPDATE notification_androids 
    SET is_read = 1
    WHERE id = p_notification_id 
      AND user_id = p_user_id 
      AND role = 'driver';

    SELECT JSON_OBJECT(
        'id', CAST(p_notification_id AS CHAR),
        'is_read', TRUE
    ) as json;
END//

-- SP: Driver Notification Read All
DROP PROCEDURE IF EXISTS sp_driver_notification_read_all_json//
CREATE PROCEDURE sp_driver_notification_read_all_json(
    IN p_user_id INT
)
BEGIN
    DECLARE v_count INT DEFAULT 0;

    UPDATE notification_androids 
    SET is_read = 1
    WHERE user_id = p_user_id 
      AND role = 'driver'
      AND is_read = 0;
    
    SET v_count = ROW_COUNT();

    SELECT JSON_OBJECT(
        'count', v_count
    ) as json;
END//

-- SP: Driver Profile Get
DROP PROCEDURE IF EXISTS sp_driver_profile_get_json//
CREATE PROCEDURE sp_driver_profile_get_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_user_id,
        'username', 'driver1',
        'name', 'Joko Anwar',
        'email', 'budi.driver@deliverypro.com',
        'avatar', 'https://ui-avatars.com/api/?name=Joko+Anwar',
        'phone', '+6281234567890',
        'license_number', 'SIM A 1234567890',
        'truck_type', 'Fuso',
        'plate_number', 'B 1234 ABC'
    ) as json;
END//

-- =====================================================
-- LOADING MODULE (004)
-- =====================================================

-- SP: Loading Dashboard
DROP PROCEDURE IF EXISTS sp_loading_dashboard_json//
CREATE PROCEDURE sp_loading_dashboard_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'stats', JSON_ARRAY(
            JSON_OBJECT('label', 'Trip Aktif', 'value', '300'),
            JSON_OBJECT('label', 'Trip Selesai', 'value', '1,250')
        ),
        'recentOrders', JSON_ARRAY(
            JSON_OBJECT(
                'id', 'TRIP0001',
                'customer', '50 Koli',
                'destination', 'Jakarta → Medan',
                'estimatedTime', '2 hari',
                'lastLocation', '3 Destination'
            )
        )
    ) as json;
END//

-- SP: Loading Orders
DROP PROCEDURE IF EXISTS sp_loading_orders_json//
CREATE PROCEDURE sp_loading_orders_json(
    IN p_user_id VARCHAR(50),
    IN p_status VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    SELECT JSON_OBJECT(
        'trips', JSON_ARRAY(
            JSON_OBJECT(
                'id', 'TRIP0001',
                'route', 'Jakarta → Medan',
                'status', 'in_progress',
                'driverName', 'Rudi Hartono',
                'truckType', 'Fuso',
                'plateNumber', 'B 9123 KZN',
                'tripDate', '17 Okt 2025',
                'manifests', JSON_ARRAY(
                    JSON_OBJECT(
                        'id', 'MF001',
                        'city', 'Medan',
                        'manifestCode', 'MF-MDN-001',
                        'stts', JSON_ARRAY(
                            JSON_OBJECT(
                                'sttNumber', 'STT20251105',
                                'recipientName', 'Ahmad Sudrajat',
                                'recipientAddress', 'Jl. Merdeka No. 123, Medan',
                                'kolis', JSON_ARRAY(
                                    JSON_OBJECT(
                                        'id', 'STT20251105-1',
                                        'weight', 2.5,
                                        'dimensions', '30x20x15 cm'
                                    )
                                ),
                                'estimatedDelivery', '19 Okt 2025'
                            )
                        )
                    )
                )
            )
        ),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', 300
        )
    ) as json;
END//

-- SP LOADING MANIFEST LIST STT
DELIMITER //

DROP PROCEDURE IF EXISTS sp_loading_manifest_stts_json//

CREATE PROCEDURE sp_loading_manifest_stts_json(
    IN p_user_id VARCHAR(50),
    IN p_manifest_id VARCHAR(50),
    IN p_trip_id VARCHAR(50),
    IN p_search VARCHAR(100),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    DECLARE v_offset INT;
    DECLARE v_total INT;
    DECLARE v_total_pages INT;
    DECLARE v_manifest_exists INT DEFAULT 0;
    DECLARE v_trip_valid INT DEFAULT 0;
    
    -- Calculate offset
    SET v_offset = (p_page - 1) * p_limit;
    
    -- Check if manifest exists
    SELECT COUNT(*) INTO v_manifest_exists
    FROM manifests
    WHERE id = p_manifest_id;
    
    IF v_manifest_exists = 0 THEN
        SELECT JSON_OBJECT('error', 'manifest_not_found') AS json;
        -- Perlu return untuk keluar dari procedure
    ELSE
        -- Check if manifest belongs to the trip
        SELECT COUNT(*) INTO v_trip_valid
        FROM manifests
        WHERE id = p_manifest_id AND trip_id = p_trip_id;
        
        IF v_trip_valid = 0 THEN
            SELECT JSON_OBJECT('error', 'invalid_trip') AS json;
        ELSE
            -- Get total count
            SELECT COUNT(*) INTO v_total
            FROM stts s
            WHERE s.manifest_id = p_manifest_id
              AND (p_search IS NULL OR p_search = '' 
                   OR s.stt_number LIKE CONCAT('%', p_search, '%')
                   OR s.recipient_name LIKE CONCAT('%', p_search, '%')
                   OR s.recipient_address LIKE CONCAT('%', p_search, '%'));
            
            -- Calculate total pages
            SET v_total_pages = CEIL(v_total / p_limit);
            
            -- Main query
            SELECT JSON_OBJECT(
                'manifest', (
                    SELECT JSON_OBJECT(
                        'id', m.id,
                        'city', m.city,
                        'manifestCode', m.manifest_code
                    )
                    FROM manifests m
                    WHERE m.id = p_manifest_id
                ),
                'stts', IFNULL((
                    SELECT JSON_ARRAYAGG(stt_data)
                    FROM (
                        SELECT JSON_OBJECT(
                            'sttNumber', s.stt_number,
                            'recipientName', s.recipient_name,
                            'recipientAddress', s.recipient_address,
                            'koliCount', IFNULL((SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id), 0),
                            'scannedKoliCount', IFNULL((SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id AND k.is_scanned = 1), 0),
                            'totalWeight', IFNULL((SELECT SUM(weight) FROM kolis k WHERE k.stt_id = s.id), 0),
                            'scannedWeight', IFNULL((SELECT SUM(weight) FROM kolis k WHERE k.stt_id = s.id AND k.is_scanned = 1), 0),
                            'estimatedDelivery', DATE_FORMAT(s.estimated_delivery, '%d %b %Y')
                        ) AS stt_data
                        FROM stts s
                        WHERE s.manifest_id = p_manifest_id
                          AND (p_search IS NULL OR p_search = '' 
                               OR s.stt_number LIKE CONCAT('%', p_search, '%')
                               OR s.recipient_name LIKE CONCAT('%', p_search, '%')
                               OR s.recipient_address LIKE CONCAT('%', p_search, '%'))
                        ORDER BY s.stt_number ASC
                        LIMIT v_offset, p_limit
                    ) AS stts_sub
                ), JSON_ARRAY()),
                'stats', JSON_OBJECT(
                    'totalSTT', (SELECT COUNT(*) FROM stts WHERE manifest_id = p_manifest_id),
                    'completeSTT', (
                        SELECT COUNT(*) FROM stts s 
                        WHERE s.manifest_id = p_manifest_id 
                        AND (SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id) = 
                            (SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id AND k.is_scanned = 1)
                        AND (SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id) > 0
                    ),
                    'totalKoli', IFNULL((
                        SELECT SUM(koli_count) FROM (
                            SELECT (SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id) as koli_count
                            FROM stts s WHERE s.manifest_id = p_manifest_id
                        ) kc
                    ), 0),
                    'scannedKoli', IFNULL((
                        SELECT SUM(scanned_count) FROM (
                            SELECT (SELECT COUNT(*) FROM kolis k WHERE k.stt_id = s.id AND k.is_scanned = 1) as scanned_count
                            FROM stts s WHERE s.manifest_id = p_manifest_id
                        ) sc
                    ), 0),
                    'totalWeight', IFNULL((
                        SELECT SUM(total_weight) FROM (
                            SELECT (SELECT IFNULL(SUM(weight), 0) FROM kolis k WHERE k.stt_id = s.id) as total_weight
                            FROM stts s WHERE s.manifest_id = p_manifest_id
                        ) tw
                    ), 0),
                    'scannedWeight', IFNULL((
                        SELECT SUM(scanned_weight) FROM (
                            SELECT (SELECT IFNULL(SUM(weight), 0) FROM kolis k WHERE k.stt_id = s.id AND k.is_scanned = 1) as scanned_weight
                            FROM stts s WHERE s.manifest_id = p_manifest_id
                        ) sw
                    ), 0)
                ),
                'pagination', JSON_OBJECT(
                    'page', p_page,
                    'limit', p_limit,
                    'total', v_total,
                    'totalPages', v_total_pages
                )
            ) AS json;
        END IF;
    END IF;
END//

DELIMITER ;

DELIMITER //

-- SP manifest list stt
DROP PROCEDURE IF EXISTS sp_manifest_stt_list_json//
CREATE PROCEDURE sp_manifest_stt_list_json(
    IN p_manifest_id VARCHAR(50),
    IN p_trip_id VARCHAR(50),
    IN p_search VARCHAR(100),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;

    /* ================= SAFETY ================= */
    IF p_page IS NULL OR p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN SET p_limit = 50; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= TOTAL STT ================= */
    SELECT COUNT(DISTINCT o.order_number)
    INTO v_total
    FROM trip_details td
    JOIN manifest_details md
        ON md.manifest_number = td.manifest_number
    JOIN orders o
        ON o.order_number = md.order_number
    WHERE td.trip_number = p_trip_id
      AND md.manifest_number = p_manifest_id
      AND (
          p_search IS NULL OR p_search = '' OR
          o.awb_no LIKE CONCAT('%', p_search, '%') OR
          o.recipient_name LIKE CONCAT('%', p_search, '%') OR
          o.recipient_address LIKE CONCAT('%', p_search, '%')
      );

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'success', TRUE,
        'responseCode', '2000400',
        'responseMessage', 'Daftar STT berhasil diambil',
        'data', JSON_OBJECT(

            /* ===== MANIFEST INFO ===== */
            'manifest', (
                SELECT JSON_OBJECT(
                    'id', m.id,
                    'city', c.city_name,
                    'manifestCode', m.manifest_number
                )
                FROM manifests m
                LEFT JOIN cities c ON c.id = m.origin
                WHERE m.manifest_number = p_manifest_id
                LIMIT 1
            ),

            /* ===== STTS LIST ===== */
            'stts', IFNULL((
                SELECT JSON_ARRAYAGG(stt_data)
                FROM (
                    SELECT JSON_OBJECT(
                        'sttNumber', o.awb_no,
                        'recipientName', o.recipient_name,
                        'recipientAddress', o.recipient_address,
                        'koliCount', o.total_colly,
                        'scannedKoliCount', o.scanned_colly,
                        'totalWeight', o.total_weight,
                        'scannedWeight', o.scanned_weight,
                        'estimatedDelivery',
                            IF(
                                o.estimated_delivery IS NULL,
                                NULL,
                                DATE_FORMAT(o.estimated_delivery, '%d %b %Y')
                            )
                    ) AS stt_data
                    FROM trip_details td
                    JOIN manifest_details md
                        ON md.manifest_number = td.manifest_number
                    JOIN orders o
                        ON o.order_number = md.order_number
                    WHERE td.trip_number = p_trip_id
                      AND md.manifest_number = p_manifest_id
                      AND (
                          p_search IS NULL OR p_search = '' OR
                          o.awb_no LIKE CONCAT('%', p_search, '%') OR
                          o.recipient_name LIKE CONCAT('%', p_search, '%') OR
                          o.recipient_address LIKE CONCAT('%', p_search, '%')
                      )
                    ORDER BY o.awb_no
                    LIMIT v_offset, p_limit
                ) x
            ), JSON_ARRAY()),

            /* ===== STATS ===== */
            'stats', (
                SELECT JSON_OBJECT(
                    'totalSTT', COUNT(DISTINCT o.order_number),
                    'completeSTT', SUM(o.scanned_colly >= o.total_colly),
                    'totalKoli', IFNULL(SUM(o.total_colly), 0),
                    'scannedKoli', IFNULL(SUM(o.scanned_colly), 0),
                    'totalWeight', IFNULL(SUM(o.total_weight), 0),
                    'scannedWeight', IFNULL(SUM(o.scanned_weight), 0)
                )
                FROM trip_details td
                JOIN manifest_details md
                    ON md.manifest_number = td.manifest_number
                JOIN orders o
                    ON o.order_number = md.order_number
                WHERE td.trip_number = p_trip_id
                  AND md.manifest_number = p_manifest_id
            ),

            /* ===== PAGINATION ===== */
            'pagination', JSON_OBJECT(
                'page', p_page,
                'limit', p_limit,
                'total', v_total,
                'totalPages', v_total_pages
            )
        )
    ) AS json_result;

END//

DELIMITER ;


-- SP: Loading History
DROP PROCEDURE IF EXISTS sp_loading_history_json//
CREATE PROCEDURE sp_loading_history_json(
    IN p_user_id VARCHAR(50),
    IN p_date_from VARCHAR(20),
    IN p_date_to VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
proc: BEGIN
    DECLARE v_offset INT DEFAULT 0;
    DECLARE v_total INT DEFAULT 0;
    DECLARE v_total_pages INT DEFAULT 0;
    DECLARE v_date_from DATE;
    DECLARE v_date_to DATE;

    /* ================= SAFETY ================= */
    IF p_page IS NULL OR p_page < 1 THEN SET p_page = 1; END IF;
    IF p_limit IS NULL OR p_limit < 1 THEN SET p_limit = 20; END IF;

    SET v_offset = (p_page - 1) * p_limit;

    /* ================= DATE PARSING ================= */
    IF p_date_from IS NOT NULL AND p_date_from != '' THEN
        SET v_date_from = STR_TO_DATE(p_date_from, '%Y-%m-%d');
    ELSE
        SET v_date_from = NULL;
    END IF;

    IF p_date_to IS NOT NULL AND p_date_to != '' THEN
        SET v_date_to = STR_TO_DATE(p_date_to, '%Y-%m-%d');
    ELSE
        SET v_date_to = NULL;
    END IF;

    /* ================= TOTAL TRIPS COMPLETED ================= */
    SELECT COUNT(DISTINCT t.trip_number)
    INTO v_total
    FROM trips t
    WHERE t.status = 'Closed'
      AND (v_date_from IS NULL OR DATE(t.trip_date) >= v_date_from)
      AND (v_date_to IS NULL OR DATE(t.trip_date) <= v_date_to);

    SET v_total_pages = CEIL(v_total / p_limit);

    /* ================= MAIN JSON ================= */
    SELECT JSON_OBJECT(
        'trips', IFNULL((
            SELECT JSON_ARRAYAGG(trip_data)
            FROM (
                SELECT JSON_OBJECT(
                    'id', t.trip_number,
                    'route', CONCAT(
                        IFNULL((SELECT c.city_name FROM cities c WHERE c.id = t.origin LIMIT 1), '-'),
                        ' → ',
                        IFNULL((SELECT c.city_name FROM cities c WHERE c.id = t.destination LIMIT 1), '-')
                    ),
                    'status', t.status,
                    'driverName', IFNULL((
                        SELECT d.driver_name 
                        FROM drivers d 
                        WHERE d.id = t.driver_id 
                        LIMIT 1
                    ), '-'),
                    'truckType', IFNULL(t.truck_type, '-'),
                    'plateNumber', IFNULL(t.plate_number, '-'),
                    'tripDate', DATE_FORMAT(t.trip_date, '%d %b %Y'),
                    'completedDate', IFNULL(DATE_FORMAT(t.completed_date, '%d %b %Y'), '-'),
                    'manifests', IFNULL((
                        SELECT JSON_ARRAYAGG(
                            JSON_OBJECT(
                                'id', m.id,
                                'manifestCode', m.manifest_number,
                                'city', IFNULL((SELECT c.city_name FROM cities c WHERE c.id = m.destination LIMIT 1), '-'),
                                'totalSTT', IFNULL((
                                    SELECT COUNT(DISTINCT md.order_number)
                                    FROM manifest_details md
                                    WHERE md.manifest_number = m.manifest_number
                                ), 0)
                            )
                        )
                        FROM manifests m
                        JOIN trip_details td ON td.manifest_number = m.manifest_number
                        WHERE td.trip_number = t.trip_number
                    ), JSON_ARRAY())
                ) AS trip_data
                FROM trips t
                WHERE t.status = 'Closed'
                  AND (v_date_from IS NULL OR DATE(t.trip_date) >= v_date_from)
                  AND (v_date_to IS NULL OR DATE(t.trip_date) <= v_date_to)
                ORDER BY t.completed_date DESC, t.trip_date DESC
                LIMIT v_offset, p_limit
            ) AS trips_sub
        ), JSON_ARRAY()),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', v_total,
            'totalPages', v_total_pages
        )
    ) AS json;
END//

-- SP: Loading Scan Koli
DROP PROCEDURE IF EXISTS sp_loading_scan_koli_json//
CREATE PROCEDURE sp_loading_scan_koli_json(
    IN p_user_id VARCHAR(50),
    IN p_trip_id VARCHAR(50),
    IN p_manifest_id VARCHAR(50),
    IN p_stt_number VARCHAR(50),
    IN p_koli_id VARCHAR(50)
)
proc: BEGIN
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_koli_exists INT DEFAULT 0;
    DECLARE v_is_scanned INT DEFAULT 0;
    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_all_scanned BOOLEAN DEFAULT FALSE;

    /* ================= VALIDASI STT ================= */
    SELECT o.order_number
    INTO v_order_number
    FROM orders o
    JOIN manifest_details md
        ON md.order_number = o.order_number
       AND md.manifest_number = p_manifest_id
    JOIN trip_details td
        ON td.manifest_number = md.manifest_number
       AND td.trip_number = p_trip_id
    WHERE o.awb_no = p_stt_number
    LIMIT 1;

    /* STT tidak ditemukan */
    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'stt_not_found') AS json;
        LEAVE proc;
    END IF;

    /* ================= CEK KOLI EXISTS ================= */
    SELECT COUNT(*), IFNULL(MAX(os.is_scanned), 0)
    INTO v_koli_exists, v_is_scanned
    FROM order_scan_loadings os
    WHERE os.order_number = v_order_number
      AND os.colly_number = p_koli_id;

    /* Koli tidak ditemukan */
    IF v_koli_exists = 0 THEN
        SELECT JSON_OBJECT('error', 'not_found') AS json;
        LEAVE proc;
    END IF;

    /* Koli sudah di-scan */
    IF v_is_scanned = 1 THEN
        SELECT JSON_OBJECT('error', 'already_scanned') AS json;
        LEAVE proc;
    END IF;

    /* ================= UPDATE SCAN STATUS ================= */
    UPDATE order_scan_loadings
    SET is_scanned = 1,
        scanned_at = NOW(),
        scanned_by = p_user_id
    WHERE order_number = v_order_number
      AND colly_number = p_koli_id;

    /* ================= HITUNG STATISTIK ================= */
    SELECT 
        COUNT(*),
        SUM(CASE WHEN os.is_scanned = 1 THEN 1 ELSE 0 END)
    INTO v_total_koli, v_scanned_koli
    FROM order_scan_loadings os
    WHERE os.order_number = v_order_number;

    /* Cek apakah semua sudah di-scan */
    IF v_scanned_koli >= v_total_koli THEN
        SET v_all_scanned = TRUE;
    END IF;

    /* ================= OUTPUT JSON ================= */
    SELECT JSON_OBJECT(
        'koliId', p_koli_id,
        'sttNumber', p_stt_number,
        'scannedCount', v_scanned_koli,
        'totalCount', v_total_koli,
        'allScanned', v_all_scanned
    ) AS json;
END//

-- SP: Loading Profile Get
DROP PROCEDURE IF EXISTS sp_loading_profile_get_json//
CREATE PROCEDURE sp_loading_profile_get_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_user_id,
        'username', 'loading1',
        'name', 'Dani',
        'email', 'dani.loading@aml.com',
        'avatar', 'https://ui-avatars.com/api/?name=Dani',
        'phone', '+6281234567890'
    ) as json;
END//

-- SP: Loading STT Kolis (Detail koli dari STT tertentu)
DROP PROCEDURE IF EXISTS sp_loading_stt_kolis_json//
CREATE PROCEDURE sp_loading_stt_kolis_json(
    IN p_stt_number   VARCHAR(50),
    IN p_trip_id      VARCHAR(50),
    IN p_manifest_id  VARCHAR(50)
)
proc: BEGIN
    /* ================= VARIABLE ================= */
    DECLARE v_order_number VARCHAR(50);
    DECLARE v_awb_no VARCHAR(50);
    DECLARE v_branch_name VARCHAR(255);
    DECLARE v_branch_address TEXT;
    DECLARE v_total_kg DECIMAL(10,2) DEFAULT 0;

    DECLARE v_total_koli INT DEFAULT 0;
    DECLARE v_scanned_koli INT DEFAULT 0;
    DECLARE v_scanned_weight DECIMAL(10,2) DEFAULT 0;

    /* ================= VALIDASI & HEADER STT ================= */
    SELECT
        o.order_number,
        o.awb_no,
        IFNULL(cb.branch_name, '-'),
        IFNULL(cb.address, '-'),
        IFNULL(o.total_kg, 0)
    INTO
        v_order_number,
        v_awb_no,
        v_branch_name,
        v_branch_address,
        v_total_kg
    FROM orders o
    JOIN manifest_details md
        ON md.order_number = o.order_number
       AND md.manifest_number = p_manifest_id
    JOIN trip_details td
        ON td.manifest_number = md.manifest_number
       AND td.trip_number = p_trip_id
    LEFT JOIN customer_branchs cb
        ON cb.id = o.customer_branch_id
    WHERE o.awb_no = p_stt_number
    LIMIT 1;

    /* ================= STT TIDAK DITEMUKAN ================= */
    IF v_order_number IS NULL THEN
        SELECT JSON_OBJECT('error', 'stt_not_found') AS json;
        LEAVE proc;
    END IF;

    /* ================= HITUNG STATISTIK ================= */
    SELECT
        COUNT(*),
        IFNULL(SUM(os.is_scanned), 0)
    INTO
        v_total_koli,
        v_scanned_koli
    FROM order_scan_loadings os
    WHERE os.order_number = v_order_number;

    IF v_total_koli > 0 THEN
        SET v_scanned_weight =
            ROUND((v_scanned_koli / v_total_koli) * v_total_kg, 2);
    ELSE
        SET v_scanned_weight = 0;
    END IF;

    /* ================= OUTPUT JSON ================= */
    SELECT JSON_OBJECT(
        'stt', JSON_OBJECT(
            'sttNumber', v_awb_no,
            'recipientName', v_branch_name,
            'recipientAddress', v_branch_address,
            'estimatedDelivery', '-'
        ),
        'kolis', IFNULL((
            SELECT JSON_ARRAYAGG(
                JSON_OBJECT(
                    'id', os.colly_number,
                    'weight', '-',
                    'dimensions', '-',
                    'isScanned', os.is_scanned,
                    'scannedAt',
                        IF(os.scanned_at IS NULL, NULL,
                           DATE_FORMAT(os.scanned_at, '%Y-%m-%dT%H:%i:%sZ')),
                    'scannedBy', os.scanned_by
                )
                ORDER BY os.colly_number
            )
            FROM order_scan_loadings os
            WHERE os.order_number = v_order_number
        ), JSON_ARRAY()),
        'stats', JSON_OBJECT(
            'totalKoli', v_total_koli,
            'scannedKoli', v_scanned_koli,
            'remainingKoli', v_total_koli - v_scanned_koli,
            'totalWeight', v_total_kg,
            'scannedWeight', v_scanned_weight,
            'remainingWeight', ROUND(v_total_kg - v_scanned_weight, 2)
        )
    ) AS json;

END//

-- =====================================================
-- AGENT MODULE (005)
-- =====================================================

--View : order agent
CREATE OR REPLACE VIEW v_order_agents AS
SELECT
    o.awb_no,
    oa.order_number,
    o.pickup_date,
    oa.agent_id,
    oa.sequence,
    o.last_status
FROM order_agents oa
LEFT JOIN orders o
    ON oa.order_number = o.order_number;


-- SP: Agent Dashboard
DELIMITER //

DROP PROCEDURE IF EXISTS sp_agent_dashboard_json//
CREATE PROCEDURE sp_agent_dashboard_json (
    IN p_agent_id INT
)
BEGIN
    DECLARE v_diterima INT DEFAULT 0;
    DECLARE v_dikirim INT DEFAULT 0;

    /* ===== DITERIMA (30 HARI TERAKHIR) ===== */
    SELECT COUNT(*)
    INTO v_diterima
    FROM v_order_agents
    WHERE agent_id = p_agent_id
      AND last_status = 'On Process Delivery'
      AND pickup_date >= CURDATE() - INTERVAL 30 DAY;

    /* ===== DIKIRIM (30 HARI TERAKHIR) ===== */
    SELECT COUNT(*)
    INTO v_dikirim
    FROM v_order_agents
    WHERE agent_id = p_agent_id
      AND last_status = 'Delivered'
      AND pickup_date >= CURDATE() - INTERVAL 30 DAY;

    /* ===== FINAL JSON ===== */
    SELECT JSON_OBJECT(
        'success', TRUE,
        'responseCode', '2000500',
        'responseMessage', 'Data dashboard agent berhasil diambil',
        'data', JSON_OBJECT(
            'stats', JSON_ARRAY(
                JSON_OBJECT(
                    'label', 'Diterima',
                    'value', CAST(v_diterima AS CHAR)
                ),
                JSON_OBJECT(
                    'label', 'Dikirim',
                    'value', CAST(v_dikirim AS CHAR)
                )
            )
        )
    ) AS json_result;

END//

DELIMITER ;


-- SP: Agent Tasks
DROP PROCEDURE IF EXISTS sp_agent_tasks_json//
CREATE PROCEDURE sp_agent_tasks_json(
    IN p_user_id VARCHAR(50),
    IN p_type VARCHAR(20),
    IN p_status VARCHAR(20),
    IN p_priority VARCHAR(20),
    IN p_page INT,
    IN p_limit INT
)
BEGIN
    SELECT JSON_OBJECT(
        'tasks', JSON_ARRAY(
            JSON_OBJECT(
                'id', 'TASK001',
                'type', 'pickup',
                'title', 'Pickup dari Gudang A',
                'description', 'Ambil paket dari gudang untuk dikirim',
                'address', 'Jl. Contoh No. 123, Jakarta',
                'time', '09:00 - 10:00',
                'estimatedPackages', 5,
                'status', 'pending',
                'priority', 'high'
            ),
            JSON_OBJECT(
                'id', 'TASK002',
                'type', 'delivery',
                'title', 'Delivery ke Customer B',
                'description', 'Kirim paket ke alamat customer',
                'address', 'Jl. Merdeka No. 456, Jakarta',
                'time', '11:00 - 12:00',
                'estimatedPackages', 3,
                'status', 'pending',
                'priority', 'medium'
            )
        ),
        'pagination', JSON_OBJECT(
            'page', p_page,
            'limit', p_limit,
            'total', 8
        )
    ) as json;
END//

-- SP: Agent Task Start
DROP PROCEDURE IF EXISTS sp_agent_task_start_json//
CREATE PROCEDURE sp_agent_task_start_json(
    IN p_user_id VARCHAR(50),
    IN p_task_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_task_id,
        'status', 'in_progress',
        'started_at', DATE_FORMAT(NOW(), '%Y-%m-%dT%H:%i:%sZ')
    ) as json;
END//

-- SP: Agent Task Complete
DROP PROCEDURE IF EXISTS sp_agent_task_complete_json//
CREATE PROCEDURE sp_agent_task_complete_json(
    IN p_user_id VARCHAR(50),
    IN p_task_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_task_id,
        'status', 'completed',
        'completed_at', DATE_FORMAT(NOW(), '%Y-%m-%dT%H:%i:%sZ')
    ) as json;
END//

-- SP: Agent Scan
DROP PROCEDURE IF EXISTS sp_agent_scan_json//
CREATE PROCEDURE sp_agent_scan_json(
    IN p_user_id VARCHAR(50),
    IN p_barcode VARCHAR(100),
    IN p_scan_type VARCHAR(20),
    IN p_latitude DECIMAL(10,6),
    IN p_longitude DECIMAL(10,6)
)
BEGIN
    SELECT JSON_OBJECT(
        'barcode', p_barcode,
        'scan_type', p_scan_type,
        'package_id', p_barcode,
        'status', IF(p_scan_type = 'receive', 'received', 'sent'),
        'timestamp', DATE_FORMAT(NOW(), '%Y-%m-%dT%H:%i:%sZ'),
        'location', JSON_OBJECT(
            'address', 'Jl. Contoh No. 123',
            'city', 'Jakarta'
        )
    ) as json;
END//

-- SP: Agent Monitoring
DROP PROCEDURE IF EXISTS sp_agent_monitoring_json//
CREATE PROCEDURE sp_agent_monitoring_json(
    IN p_user_id VARCHAR(50),
    IN p_period VARCHAR(20),
    IN p_date VARCHAR(20)
)
BEGIN
  SELECT JSON_OBJECT(
        'period', IFNULL(p_period, 'today'),
        'stats', JSON_OBJECT(
            'packagesReceived', 24,
            'packagesSent', 18,
            'estimatedEarnings', 450000,
            'completedTasks', 12
        ),
        'chartData', JSON_ARRAY(
            JSON_OBJECT('hour', '08:00', 'received', 5, 'sent', 3),
            JSON_OBJECT('hour', '09:00', 'received', 8, 'sent', 6),
            JSON_OBJECT('hour', '10:00', 'received', 11, 'sent', 9)
        ),
        'recentPackages', JSON_ARRAY(
            JSON_OBJECT(
                'id', 'PKG001',
                'type', 'received',
                'barcode', 'PKG123456789',
                'timestamp', DATE_FORMAT(NOW(), '%Y-%m-%dT%H:%i:%sZ')
            )
        )
    ) as json;
END//

-- SP: Agent Profile Get
DROP PROCEDURE IF EXISTS sp_agent_profile_get_json//
CREATE PROCEDURE sp_agent_profile_get_json(
    IN p_user_id VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'id', p_user_id,
        'username', 'agent1',
        'name', 'Siti Nurhaliza',
        'email', 'siti.agent@deliverypro.com',
        'avatar', 'https://ui-avatars.com/api/?name=Siti+Nurhaliza',
        'phone', '+6281234567890',
        'location', 'Jakarta'
    ) as json;
END//

-- =====================================================
-- TRACKING MODULE (006)
-- =====================================================

-- SP: Tracking Detail
DROP PROCEDURE IF EXISTS sp_tracking_detail_json//
CREATE PROCEDURE sp_tracking_detail_json(
    IN p_stt_number VARCHAR(50)
)
BEGIN
    SELECT JSON_OBJECT(
        'sttNumber', p_stt_number,
        'tripId', 'TRIP0001',
        'status', 'in_transit',
        'currentLocation', 'Jl. Gatot Subroto, Jakarta',
        'estimatedArrival', '19 Okt 2025, 10:00',
        'driver', 'Rudi Hartono',
        'driverPhone', '+6281234567890',
        'timeline', JSON_ARRAY(
            JSON_OBJECT(
                'status', 'picked_up',
                'title', 'Paket Diambil',
                'description', 'Paket telah diambil dari gudang',
                'time', '14:30',
                'date', '15 Okt 2025',
                'location', 'Gudang Jakarta',
                'completed', true
            ),
            JSON_OBJECT(
                'status', 'in_transit',
                'title', 'Dalam Perjalanan',
                'description', 'Paket sedang dalam perjalanan ke tujuan',
                'time', '15:00',
                'date', '15 Okt 2025',
                'location', 'Jl. Gatot Subroto, Jakarta',
                'completed', true
            ),
            JSON_OBJECT(
                'status', 'out_for_delivery',
                'title', 'Sedang Dikirim',
                'description', 'Paket sedang dalam perjalanan ke alamat tujuan',
                'time', NULL,
                'date', NULL,
                'location', NULL,
                'completed', false
            ),
    JSON_OBJECT(
                'status', 'delivered',
                'title', 'Terkirim',
                'description', 'Paket telah diterima oleh penerima',
                'time', NULL,
                'date', NULL,
                'location', NULL,
                'completed', false
            )
        ),
        'recipient', JSON_OBJECT(
            'name', 'Ahmad Sudrajat',
            'address', 'Jl. Merdeka No. 123, Medan',
            'phone', '+6281234567890'
        )
    ) as json;
END//

DELIMITER ;

-- =====================================================
-- END OF STORED PROCEDURES
-- =====================================================
