DROP TABLE IF EXISTS reservations;
DROP TABLE IF EXISTS lab_sessions;
CREATE TABLE lab_sessions (
    session_id             SERIAL PRIMARY KEY,
    session_name           VARCHAR(100) NOT NULL,
    available_workstations INT NOT NULL CHECK (available_workstations >= 0)
);
CREATE TABLE reservations (
    reservation_id   SERIAL PRIMARY KEY,
    session_id       INT NOT NULL REFERENCES lab_sessions(session_id),
    lecturer         VARCHAR(100) NOT NULL,
    num_workstations INT NOT NULL CHECK (num_workstations > 0),
    status           VARCHAR(20) NOT NULL DEFAULT 'RESERVED'
                     CHECK (status IN ('RESERVED', 'CANCELLED'))
);
INSERT INTO lab_sessions (session_name, available_workstations) VALUES
    ('Monday 08:00 - Programming Lab', 30),
    ('Tuesday 10:00 - Networking Lab', 4),
    ('Wednesday 14:00 - Database Lab', 0);

SELECT * FROM lab_sessions ORDER BY session_id;
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT session_id, session_name, available_workstations
               FROM lab_sessions ORDER BY session_id LOOP
        IF rec.available_workstations = 0 THEN
            status := 'FULL';
        ELSIF rec.available_workstations <= 5 THEN
            status := 'NEARLY FULL';
        ELSE
            status := 'ENOUGH WORKSTATIONS';
        END IF;
        RAISE NOTICE 'Session: % (% free) -> %', rec.session_name, rec.available_workstations, status;
    END LOOP;
END;
$$;
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Session preparation reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Workstation check number %', n;
    END LOOP;
END;
$$;
DROP PROCEDURE IF EXISTS reserve_workstations(integer, character varying, integer);
CREATE OR REPLACE PROCEDURE reserve_workstations(
    p_session_id INT,
    p_lecturer   VARCHAR,
    p_quantity   INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid number of workstations: %. It must be greater than zero.', p_quantity;
    END IF;

    SELECT available_workstations INTO v_available
    FROM lab_sessions
    WHERE session_id = p_session_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Session % does not exist.', p_session_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Reservation REJECTED for %: requested %, only % available (session %).',
                     p_lecturer, p_quantity, v_available, p_session_id;
        RETURN;
    END IF;

    UPDATE lab_sessions
    SET available_workstations = available_workstations - p_quantity
    WHERE session_id = p_session_id;

    INSERT INTO reservations (session_id, lecturer, num_workstations, status)
    VALUES (p_session_id, p_lecturer, p_quantity, 'RESERVED');

    RAISE NOTICE 'Reservation RECORDED for %: % workstation(s) in session %.',
                 p_lecturer, p_quantity, p_session_id;
END;
$$;
CALL reserve_workstations(1, 'Dr. Banda', 10);   -- valid (30 available)
CALL reserve_workstations(2, 'Dr. Phiri', 3);    -- valid (4 available)
CALL reserve_workstations(2, 'Dr. Mumba', 5);    -- exceeds (only 1 left) -> rejected

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
CREATE OR REPLACE PROCEDURE cancel_reservation(p_reservation_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_session_id INT;
    v_qty        INT;
    v_status     VARCHAR(20);
BEGIN
    SELECT session_id, num_workstations, status
    INTO v_session_id, v_qty, v_status
    FROM reservations
    WHERE reservation_id = p_reservation_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reservation % does not exist.', p_reservation_id;
    END IF;

    IF v_status = 'CANCELLED' THEN
        RAISE NOTICE 'Reservation % is already cancelled. No workstations released.', p_reservation_id;
        RETURN;
    END IF;

    UPDATE reservations SET status = 'CANCELLED' WHERE reservation_id = p_reservation_id;
    UPDATE lab_sessions
    SET available_workstations = available_workstations + v_qty
    WHERE session_id = v_session_id;

    RAISE NOTICE 'Reservation % cancelled. % workstation(s) released to session %.',
                 p_reservation_id, v_qty, v_session_id;
END;
$$;
CALL cancel_reservation(1);   -- first call: releases workstations
CALL cancel_reservation(1);   -- second call: must NOT release again

SELECT * FROM lab_sessions ORDER BY session_id;
SELECT * FROM reservations ORDER BY reservation_id;
DO $$
DECLARE
    threshold INT := 5;
    cur_few CURSOR FOR
        SELECT session_id, session_name, available_workstations
        FROM lab_sessions
        WHERE available_workstations <= threshold
        ORDER BY available_workstations, session_id;
    rec RECORD;
BEGIN
    OPEN cur_few;
    LOOP
        FETCH cur_few INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few workstations left -> %: % free', rec.session_name, rec.available_workstations;
    END LOOP;
    CLOSE cur_few;
END;
$$;
DO $$
BEGIN
    CALL reserve_workstations(1, 'Dr. Zulu', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END;
$$;
SELECT session_id, session_name, available_workstations AS final_available_workstations
FROM lab_sessions
ORDER BY session_id;

SELECT reservation_id, session_id, lecturer, num_workstations, status
FROM reservations
ORDER BY reservation_id;