-- 09_auth_procedures.sql
-- HQTCSDL-41: stored procedure cho dang nhap JWT. Chay lai nhieu lan an toan (CREATE OR ALTER).

USE AR_IMMS;
GO

-- SP: Lay thong tin dang nhap theo username cua user dang hoat dong.
-- Flask tu kiem tra hash va cap JWT; SP khong tra mat khau goc (DB khong luu mat khau goc).
-- Test case: 'admin' -> 1 dong, role_name = ADMINISTRATOR;
--            username khong ton tai hoac is_active = 0 -> 0 dong.
CREATE OR ALTER PROCEDURE usp_authenticate_user
    @username NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;

    SELECT u.id AS user_id,
           u.username,
           u.password_hash,
           u.full_name,
           u.role_id,
           r.name AS role_name
    FROM users u
    INNER JOIN roles r ON r.id = u.role_id
    WHERE u.username = @username
      AND u.is_active = 1;
END;
GO

-- SP: Dat password hash cho user (dung boi script quan tri/dev, hash do werkzeug tao).
-- Chi nhan hash dung dinh dang scrypt: hoac pbkdf2: de khong luu nham mat khau goc.
-- Test case: hash 'abc' -> loi 51050; user khong ton tai -> loi 51051;
--            hash 'scrypt:...' cho 'admin' -> cap nhat 1 dong.
CREATE OR ALTER PROCEDURE usp_set_user_password_hash
    @username NVARCHAR(50),
    @password_hash NVARCHAR(255)
AS
BEGIN
    SET NOCOUNT ON;

    IF @password_hash IS NULL
       OR (@password_hash NOT LIKE N'scrypt:%' AND @password_hash NOT LIKE N'pbkdf2:%')
        THROW 51050, N'Password hash khong dung dinh dang (scrypt: hoac pbkdf2:).', 1;

    UPDATE users
    SET password_hash = @password_hash
    WHERE username = @username;

    IF @@ROWCOUNT = 0
        THROW 51051, N'User khong ton tai.', 1;
END;
GO

PRINT N'=== Tao procedure dang nhap thanh cong ===';
GO