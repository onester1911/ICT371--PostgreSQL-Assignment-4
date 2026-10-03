DROP TABLE IF EXISTS bookings;
DROP TABLE IF EXISTS events;
CREATE TABLE events (
    event_id        SERIAL PRIMARY KEY,
    event_name      VARCHAR(100) NOT NULL,
    available_seats INT NOT NULL CHECK (available_seats >= 0)
);

CREATE TABLE bookings (
    booking_id      SERIAL PRIMARY KEY,
    event_id        INT NOT NULL REFERENCES events(event_id),
    student_number  VARCHAR(20) NOT NULL,
    number_of_seats INT NOT NULL CHECK (number_of_seats > 0),
    status          VARCHAR(20) NOT NULL DEFAULT 'BOOKED'
                    CHECK (status IN ('BOOKED', 'CANCELLED'))
);

INSERT INTO events (event_name, available_seats) VALUES
    ('Graduation Gala', 200),
    ('Career Fair', 8),
    ('Freshers Welcome Concert', 0);
SELECT * FROM events ORDER BY event_id;
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT event_id, event_name, available_seats FROM events ORDER BY event_id LOOP
        IF rec.available_seats = 0 THEN
            status := 'FULL';
        ELSIF rec.available_seats <= 10 THEN
            status := 'NEARLY FULL';
        ELSE
            status := 'PLENTY OF SEATS';
        END IF;
        RAISE NOTICE 'Event: % (% seats) -> %', rec.event_name, rec.available_seats, status;
    END LOOP;
END;
$$;
DO $$
DECLARE
    day_no INT := 1;
BEGIN
    WHILE day_no <= 3 LOOP
        RAISE NOTICE 'Booking reminder day %', day_no;
        day_no := day_no + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Entrance check number %', n;
    END LOOP;
END;
$$;
DROP PROCEDURE book_seats(integer,character varying,integer)
CREATE OR REPLACE PROCEDURE book_seats(
    p_event_id       INT,
    p_student_number VARCHAR,
    p_seats          INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_seats IS NULL OR p_seats <= 0 THEN
        RAISE EXCEPTION 'Invalid number of seats: %. It must be greater than zero.', p_seats;
    END IF;

    SELECT available_seats INTO v_available
    FROM events
    WHERE event_id = p_event_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Event % does not exist.', p_event_id;
    END IF;

    IF v_available < p_seats THEN
        RAISE NOTICE 'Booking REJECTED for student %: requested % seat(s), only % left (event %).',
                     p_student_number, p_seats, v_available, p_event_id;
        RETURN;
    END IF;

    UPDATE events
    SET available_seats = available_seats - p_seats
    WHERE event_id = p_event_id;

    INSERT INTO bookings (event_id, student_number, number_of_seats, status)
    VALUES (p_event_id, p_student_number, p_seats, 'BOOKED');

    RAISE NOTICE 'Booking RECORDED for student %: % seat(s) for event %.',
                 p_student_number, p_seats, p_event_id;
END;
$$;
CALL book_seats(1, 'S3001', 5);    -- valid (200 available)
CALL book_seats(2, 'S3002', 3);    -- valid (8 available)
CALL book_seats(2, 'S3003', 10);   -- exceeds (only 5 left) -> rejected

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;
CREATE OR REPLACE PROCEDURE cancel_booking(p_booking_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_event_id INT;
    v_seats    INT;
    v_status   VARCHAR(20);
BEGIN
    SELECT event_id, number_of_seats, status
    INTO v_event_id, v_seats, v_status
    FROM bookings
    WHERE booking_id = p_booking_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Booking % does not exist.', p_booking_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Booking % is already cancelled. No seats released.', p_booking_id;
        RETURN;
    END IF;

    UPDATE bookings SET status = 'CANCELLED' WHERE booking_id = p_booking_id;
    UPDATE events SET available_seats = available_seats + v_seats WHERE event_id = v_event_id;

    RAISE NOTICE 'Booking % cancelled. % seat(s) released to event %.', p_booking_id, v_seats, v_event_id;
END;
$$;
CALL cancel_booking(2);   -- first call: releases seats
CALL cancel_booking(2);   -- second call: must NOT release again

SELECT * FROM events ORDER BY event_id;
SELECT * FROM bookings ORDER BY booking_id;
DO $$
DECLARE
    threshold INT := 10;
    cur_full CURSOR FOR
        SELECT event_id, event_name, available_seats
        FROM events
        WHERE available_seats <= threshold
        ORDER BY available_seats, event_id;
    rec RECORD;
BEGIN
    OPEN cur_full;
    LOOP
        FETCH cur_full INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Full / nearly full -> %: % seat(s) left', rec.event_name, rec.available_seats;
    END LOOP;
    CLOSE cur_full;
END;
$$;
DO $$
BEGIN
    CALL book_seats(1, 'S3004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END;
$$;
SELECT event_id, event_name, available_seats AS final_available_seats
FROM events
ORDER BY event_id;

SELECT booking_id, event_id, student_number, number_of_seats, status
FROM bookings
ORDER BY booking_id;