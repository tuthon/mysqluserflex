-- ====================================================================================
-- ADVANCED SCRIPT FOR CREATING TEST USERS IN MYSQL 8.0
-- Includes different authentication plugins and password policies.
-- ====================================================================================

-- --- PART 0: Preparation ---
-- It is recommended to delete the users if they already exist,
-- so that the script can be executed repeatedly for testing.

DROP USER IF EXISTS 'readonly_user'@'%';
DROP USER IF EXISTS 'readwrite_user'@'localhost';
DROP USER IF EXISTS 'app_user'@'%';
DROP USER IF EXISTS 'db_admin'@'localhost';
DROP USER IF EXISTS 'sha2_cache_user'@'%';
DROP USER IF EXISTS 'native_user'@'localhost';
DROP USER IF EXISTS 'sha256_user'@'localhost';
DROP USER IF EXISTS 'testuser'@'localhost'; -- За auth_socket
DROP USER IF EXISTS 'expired_user'@'localhost';
DROP USER IF EXISTS 'expiring_soon'@'localhost';
DROP USER IF EXISTS 'locked_user'@'%';
DROP USER IF EXISTS 'policy_user'@'localhost';

-- also create a test database
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- ====================================================================================
-- --- PART 1: USERS WITH DIFFERENT AUTHENTICATION PLUGINS ---
-- ====================================================================================
-- ---------------------------------------------------------------------
-- 1. Read-Only User
-- This user can only execute SELECT queries on all tables
-- in the 'test_db' database from any host (%).
-- ---------------------------------------------------------------------
CREATE USER 'readonly_user'@'%' IDENTIFIED BY 'ReadOnlyPass123!';
GRANT SELECT ON `test_db`.* TO 'readonly_user'@'%';

-- 2. Read/Write User
-- This user can read, insert, update, and delete data,
-- but only when connecting from the same machine (localhost).
-- ---------------------------------------------------------------------
CREATE USER 'readwrite_user'@'localhost' IDENTIFIED BY 'ReadWritePass456!';
GRANT SELECT, INSERT, UPDATE, DELETE ON `test_db`.* TO 'readwrite_user'@'localhost';

-- 3. Application User (Typical application user)
-- This user has rights to manage both the data (DML) and the structure (DDL)
-- of the 'test_db' database. Access is allowed from anywhere (%).
-- ---------------------------------------------------------------------
CREATE USER 'app_user'@'%' IDENTIFIED BY 'AppUserPass789!';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES ON `test_db`.* TO 'app_user'@'%';

-- 4. Admin User (Administrator for a specific database)
-- This user has all privileges on 'test_db', including the right
-- to grant privileges to other users (WITH GRANT OPTION).
-- ---------------------------------------------------------------------
CREATE USER 'db_admin'@'localhost' IDENTIFIED BY 'AdminPass!@#';
GRANT ALL PRIVILEGES ON `test_db`.* TO 'db_admin'@'localhost' WITH GRANT OPTION;

-- 5. User with caching_sha2_password (default in MySQL 8.0)
-- This is the default plugin. You don’t need to specify it explicitly.
CREATE USER 'sha2_cache_user'@'%' IDENTIFIED BY 'CacheSha2Pass1!';
GRANT SELECT ON test_db.* TO 'sha2_cache_user'@'%';
-- COMMENT: The most secure and recommended method for new applications.

-- 6. User with mysql_native_password (the old method from MySQL 5.x)
-- It must be explicitly specified with `IDENTIFIED WITH`.
CREATE USER 'native_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'NativePass57!';
GRANT SELECT, INSERT ON test_db.* TO 'native_user'@'localhost';
-- COMMENT: Useful for compatibility with older applications and drivers that do not support caching_sha2_password.

-- 7. User with sha256_password
-- More secure than native, but less commonly used compared to caching_sha2_password.
CREATE USER 'sha256_user'@'localhost' IDENTIFIED WITH sha256_password BY 'SHA256Pass!';
GRANT USAGE ON *.* TO 'sha256_user'@'localhost'; -- USAGE means "no privileges", only the right to connect.
-- COMMENT: By default requires an SSL/TLS connection or a socket connection. Otherwise, the password is sent in plain text.

-- 8. User with auth_socket (Linux/Unix only)
-- This user has NO password. Authentication is performed based on the operating system user.
-- To make it work, you must connect to MySQL from an OS user named 'testuser'.
CREATE USER 'testuser'@'localhost' IDENTIFIED WITH auth_socket;
GRANT SELECT ON test_db.* TO 'testuser'@'localhost';
-- COMMENT: Very secure method for local scripts and system tasks.
-- TO TEST: Log into the terminal as the 'testuser' user (or `sudo -u testuser mysql`) and run `mysql -u testuser`.


-- ====================================================================================
-- --- PART 2: USERS WITH PASSWORD POLICIES ---
-- ====================================================================================

-- 9. User with an immediately expiring password
-- At the first login, the user will be forced to change their password.
CREATE USER 'expired_user'@'localhost' IDENTIFIED BY 'MustChangeThis1!';
ALTER USER 'expired_user'@'localhost' PASSWORD EXPIRE;
GRANT SELECT ON test_db.* TO 'expired_user'@'localhost';

-- 10. User with a password that expires after a specific period
-- The password will be valid for 90 days, after which it must be changed.
CREATE USER 'expiring_soon'@'localhost' IDENTIFIED BY 'ExpiresIn90Days!';
ALTER USER 'expiring_soon'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
GRANT SELECT ON test_db.* TO 'expiring_soon'@'localhost';

-- 11. Locked User (Locked Account)
-- This user cannot log in until the account is manually unlocked.
CREATE USER 'locked_user'@'%' IDENTIFIED BY 'CannotLogin1!';
ALTER USER 'locked_user'@'%' ACCOUNT LOCK;
GRANT SELECT ON test_db.* TO 'locked_user'@'%';
-- To unlock: ALTER USER 'locked_user'@'localhost' ACCOUNT UNLOCK;

-- 12. User with a complex password policy
-- A combination of several security rules.
CREATE USER 'policy_user'@'localhost' IDENTIFIED BY 'ComplexPolicyPass1!';
ALTER USER 'policy_user'@'localhost'
    PASSWORD HISTORY 5                 -- None of the last 5 passwords can be reused.
    PASSWORD REUSE INTERVAL 365 DAY    -- The same password cannot be used more than once per year.
    FAILED_LOGIN_ATTEMPTS 3            -- The account is locked after 3 failed login attempts.
    PASSWORD_LOCK_TIME UNBOUNDED;      -- The lock is indefinite (requires manual unlocking).
GRANT SELECT ON test_db.* TO 'policy_user'@'localhost';


-- ====================================================================================
-- --- PART 3: Finalization and verification ---
-- ====================================================================================
FLUSH PRIVILEGES;

SELECT 'Разширеният списък с тестови потребители е създаден успешно!' AS Status;

-- Query to check the created users and their settings
SELECT
    user,
    host,
    plugin,
    password_expired,
    account_locked
FROM
    mysql.user
WHERE
    user IN (
        'readonly_user', 'readwrite_user', 'app_user', 'db_admin', 
        'readonly_user', 'app_user', 'sha2_cache_user', 'native_user',
        'sha256_user', 'testuser', 'expired_user',
        'expiring_soon', 'locked_user', 'policy_user'
    );