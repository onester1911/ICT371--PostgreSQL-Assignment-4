DROP TABLE IF EXISTS book_loans;
DROP TABLE IF EXISTS books;
CREATE TABLE books (
    book_id          SERIAL PRIMARY KEY,
    title            VARCHAR(100) NOT NULL,
    available_copies INT NOT NULL CHECK (available_copies >= 0)
);
CREATE TABLE book_loans (
    loan_id        SERIAL PRIMARY KEY,
    book_id        INT NOT NULL REFERENCES books(book_id),
    student_number VARCHAR(20) NOT NULL,
    quantity       INT NOT NULL CHECK (quantity > 0),
    loan_status    VARCHAR(20) NOT NULL DEFAULT 'BORROWED'
                   CHECK (loan_status IN ('BORROWED', 'RETURNED'))
);
INSERT INTO books (title, available_copies) VALUES
    ('Database Systems', 5),
    ('Computer Networks', 2),
    ('Operating Systems', 10),
    ('Software Engineering', 0);

SELECT * FROM books ORDER BY book_id;
DO $$
DECLARE
    rec    RECORD;
    status TEXT;
BEGIN
    FOR rec IN SELECT book_id, title, available_copies FROM books ORDER BY book_id LOOP
        IF rec.available_copies = 0 THEN
            status := 'UNAVAILABLE';
        ELSIF rec.available_copies <= 3 THEN
            status := 'LOW ON COPIES';
        ELSE
            status := 'SUFFICIENTLY STOCKED';
        END IF;
        RAISE NOTICE 'Book: % (% copies) -> %', rec.title, rec.available_copies, status;
    END LOOP;
END;
$$;
DO $$
DECLARE
    counter INT := 1;
BEGIN
    WHILE counter <= 3 LOOP
        RAISE NOTICE 'Overdue reminder number: %', counter;
        counter := counter + 1;
    END LOOP;

    FOR shelf IN 1..3 LOOP
        RAISE NOTICE 'Library shelf number: %', shelf;
    END LOOP;
END;
$$;
CREATE OR REPLACE PROCEDURE borrow_book(
    p_book_id        INT,
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

    SELECT available_copies INTO v_available
    FROM books
    WHERE book_id = p_book_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Book % does not exist.', p_book_id;
    END IF;

    IF v_available < p_quantity THEN
        RAISE NOTICE 'Loan REJECTED for student %: requested %, only % available (book %).',
                     p_student_number, p_quantity, v_available, p_book_id;
        RETURN;
    END IF;

    UPDATE books
    SET available_copies = available_copies - p_quantity
    WHERE book_id = p_book_id;

    INSERT INTO book_loans (book_id, student_number, quantity, loan_status)
    VALUES (p_book_id, p_student_number, p_quantity, 'BORROWED');

    RAISE NOTICE 'Loan RECORDED for student %: % copy(ies) of book %.',
                 p_student_number, p_quantity, p_book_id;
END;
$$;
CALL borrow_book(1, 'S1001', 2);    -- valid  (5 available)
CALL borrow_book(3, 'S1002', 3);    -- valid  (10 available)
CALL borrow_book(2, 'S1003', 5);    -- exceeds (only 2 available) -> rejected

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
CREATE OR REPLACE PROCEDURE return_book(p_loan_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_book_id INT;
    v_qty     INT;
    v_status  VARCHAR(20);
BEGIN
    SELECT book_id, quantity, loan_status
    INTO v_book_id, v_qty, v_status
    FROM book_loans
    WHERE loan_id = p_loan_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan % does not exist.', p_loan_id;
    END IF;

    IF v_status = 'RETURNED' THEN
        RAISE NOTICE 'Loan % was already returned. No copies restored.', p_loan_id;
        RETURN;
    END IF;

    UPDATE book_loans SET loan_status = 'RETURNED' WHERE loan_id = p_loan_id;
    UPDATE books SET available_copies = available_copies + v_qty WHERE book_id = v_book_id;

    RAISE NOTICE 'Loan % returned. % copy(ies) restored to book %.', p_loan_id, v_qty, v_book_id;
END;
$$;
CALL return_book(1);   -- first call: restores copies
CALL return_book(1);   -- second call: must NOT restore again

SELECT * FROM books ORDER BY book_id;
SELECT * FROM book_loans ORDER BY loan_id;
DO $$
DECLARE
    threshold  INT := 3;
    cur_low CURSOR FOR
        SELECT book_id, title, available_copies
        FROM books
        WHERE available_copies <= threshold
        ORDER BY available_copies, book_id;
    rec RECORD;
BEGIN
    OPEN cur_low;
    LOOP
        FETCH cur_low INTO rec;
        EXIT WHEN NOT FOUND;
        RAISE NOTICE 'Few copies left -> Book %: % (% copies)', rec.book_id, rec.title, rec.available_copies;
    END LOOP;
    CLOSE cur_low;
END;
$$;
DO $$
BEGIN
    CALL borrow_book(1, 'S1004', 0);
EXCEPTION
    WHEN raise_exception THEN
        RAISE NOTICE 'Error handled: %', SQLERRM;
END;
$$;
SELECT book_id, title, available_copies AS final_available_copies
FROM books
ORDER BY book_id;

SELECT loan_id, book_id, student_number, quantity, loan_status
FROM book_loans
ORDER BY loan_id;