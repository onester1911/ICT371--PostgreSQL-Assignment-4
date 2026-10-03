DROP TABLE IF EXISTS tool_loans;
DROP TABLE IF EXISTS tools;
CREATE TABLE tools (
    tool_id            SERIAL PRIMARY KEY,
    tool_name          VARCHAR(100) NOT NULL,
    available_quantity INT NOT NULL CHECK (available_quantity >= 0)
);
CREATE TABLE tool_loans (
    loan_id        SERIAL PRIMARY KEY,
    tool_id        INT NOT NULL REFERENCES tools(tool_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    status         VARCHAR(20) NOT NULL DEFAULT 'ISSUED'
                   CHECK (status IN ('ISSUED', 'RETURNED'))
);
INSERT INTO tools (tool_name, available_quantity) VALUES
    ('Vernier Caliper', 12),
    ('Digital Multimeter', 3),
    ('Soldering Iron', 0);

SELECT * FROM tools ORDER BY tool_id;
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT tool_id, tool_name, available_quantity FROM tools ORDER BY tool_id LOOP
        IF rec.available_quantity = 0 THEN
            status := 'UNAVAILABLE';
        ELSIF rec.available_quantity <= 3 THEN
            status := 'LOW ON STOCK';
        ELSE
            status := 'READILY AVAILABLE';
        END IF;
        RAISE NOTICE 'Tool: % (% available) -> %', rec.tool_name, rec.available_quantity, status;
    END LOOP;
END;
$$;
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Workshop safety reminder %', counter;
        counter := counter + 1;
    END LOOP;

    FOR n IN 1..3 LOOP
        RAISE NOTICE 'Tool inspection number %', n;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE issue_tool(
    p_tool_id        INT,
    p_student_number VARCHAR,
    p_quantity       INT
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_available INT;
BEGIN
    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'Invalid quantity: %. Quantity must be greater than zero.', p_quantity;
    END IF;

    SELECT available_quantity INTO v_available
    FROM tools
    WHERE tool_id = p_tool_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tool % does not exist.', p_tool_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Tool loan REJECTED for student %: requested %, only % in stock (tool %).',
                     p_student_number, p_quantity, v_available, p_tool_id;
        RETURN;
    END IF;

    UPDATE tools
    SET available_quantity = available_quantity - p_quantity
    WHERE tool_id = p_tool_id;

    INSERT INTO tool_loans (tool_id, student_number, quantity, status)
    VALUES (p_tool_id, p_student_number, p_quantity, 'ISSUED');

    RAISE NOTICE 'Tool loan RECORDED for student %: % unit(s) of tool %.',
                 p_student_number, p_quantity, p_tool_id;
END;
$$;
CALL issue_tool(1, 'S2001', 4);   -- valid (12 in stock)
CALL issue_tool(2, 'S2002', 1);   -- valid (3 in stock)
CALL issue_tool(2, 'S2003', 5);   -- exceeds (only 2 left) -> rejected

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;
CREATE OR REPLACE PROCEDURE return_tool(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_tool_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT tool_id, quantity, status
    INTO v_tool_id, v_qty, v_status
    FROM tool_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tool loan % does not exist.', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Tool loan % was already returned. No stock added.', p_loan_id;
        RETURN;
    END IF;

    UPDATE tool_loans SET status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE tools SET available_quantity = available_quantity + v_qty WHERE tool_id = v_tool_id;

    RAISE NOTICE 'Tool loan % returned. % unit(s) added back to tool %.', p_loan_id, v_qty, v_tool_id;
END;
$$;
CALL return_tool(1);   -- first call: restores stock
CALL return_tool(1);   -- second call: must NOT add stock again

SELECT * FROM tools ORDER BY tool_id;
SELECT * FROM tool_loans ORDER BY loan_id;
DO $$
DECLARE
    threshold INT := 3;
    cur_low CURSOR FOR
        SELECT tool_id, tool_name, available_quantity
        FROM tools
        WHERE available_quantity <= threshold
        ORDER BY available_quantity, tool_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Low availability -> %: % available', rec.tool_name, rec.available_quantity;
    END LOOP;
    CLOSE cur_low;
END;
$$;
DO $$
BEGIN
    CALL issue_tool(1, 'S2004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END;
$$;
SELECT tool_id, tool_name, available_quantity AS final_quantity
FROM tools
ORDER BY tool_id;

SELECT loan_id, tool_id, student_number, quantity, status
FROM tool_loans
ORDER BY loan_id;