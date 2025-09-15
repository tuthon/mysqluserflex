-- ====================================================================================
-- РАЗШИРЕН СКРИПТ ЗА СЪЗДАВАНЕ НА ТЕСТОВИ ПОТРЕБИТЕЛИ В MYSQL 8.0
-- Включва различни плъгини за автентикация и политики за пароли.
-- ====================================================================================

-- --- ЧАСТ 0: Подготовка ---
-- Препоръчително е да се изтрият потребителите, ако вече съществуват,
-- за да може скриптът да се изпълнява отново и отново за тестове.
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

-- Създаваме и тестова база данни
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- ====================================================================================
-- --- ЧАСТ 1: ПОТРЕБИТЕЛИ С РАЗЛИЧНИ ПЛЪГИНИ ЗА АВТЕНТИКАЦИЯ ---
-- ====================================================================================
-- ---------------------------------------------------------------------
-- 1. Потребител Read-Only (Само за четене)
-- Този потребител може само да изпълнява SELECT заявки към всички таблици
-- в базата 'test_db' от всякакъв хост (%).
-- ---------------------------------------------------------------------
CREATE USER 'readonly_user'@'%' IDENTIFIED BY 'ReadOnlyPass123!';
GRANT SELECT ON `test_db`.* TO 'readonly_user'@'%';

-- 2. Потребител Read/Write (За четене и писане)
-- Този потребител може да чете, вмъква, обновява и трие данни,
-- но само когато се свързва от същата машина (localhost).
-- ---------------------------------------------------------------------
CREATE USER 'readwrite_user'@'localhost' IDENTIFIED BY 'ReadWritePass456!';
GRANT SELECT, INSERT, UPDATE, DELETE ON `test_db`.* TO 'readwrite_user'@'localhost';

-- 3. Потребител Application User (Типичен потребител за приложение)
-- Този потребител има права да управлява данните (DML) и структурата (DDL)
-- на базата данни 'test_db'. Достъпът е разрешен от всякъде (%).
-- ---------------------------------------------------------------------
CREATE USER 'app_user'@'%' IDENTIFIED BY 'AppUserPass789!';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, INDEX, REFERENCES ON `test_db`.* TO 'app_user'@'%';

-- 4. Потребител Admin User (Администратор за конкретна база данни)
-- Този потребител има всички права върху 'test_db', включително правото
-- да дава права на други потребители (WITH GRANT OPTION).
-- ---------------------------------------------------------------------
CREATE USER 'db_admin'@'localhost' IDENTIFIED BY 'AdminPass!@#';
GRANT ALL PRIVILEGES ON `test_db`.* TO 'db_admin'@'localhost' WITH GRANT OPTION;

-- 5. Потребител с caching_sha2_password (стандартен за MySQL 8.0)
-- Това е плъгинът по подразбиране. Не е нужно да го указвате изрично.
CREATE USER 'sha2_cache_user'@'%' IDENTIFIED BY 'CacheSha2Pass1!';
GRANT SELECT ON test_db.* TO 'sha2_cache_user'@'%';
-- КОМЕНТАР: Най-сигурният и препоръчителен метод за нови приложения.

-- 6. Потребител с mysql_native_password (старият метод от MySQL 5.x)
-- Необходимо е да се укаже изрично с `IDENTIFIED WITH`.
CREATE USER 'native_user'@'localhost' IDENTIFIED WITH mysql_native_password BY 'NativePass57!';
GRANT SELECT, INSERT ON test_db.* TO 'native_user'@'localhost';
-- КОМЕНТАР: Полезен за съвместимост със стари приложения и драйвери, които не поддържат caching_sha2_password.

-- 7. Потребител с sha256_password
-- По-сигурен от native, но по-рядко използван от caching_sha2_password.
CREATE USER 'sha256_user'@'localhost' IDENTIFIED WITH sha256_password BY 'SHA256Pass!';
GRANT USAGE ON *.* TO 'sha256_user'@'localhost'; -- USAGE означава "без права", само право за връзка.
-- КОМЕНТАР: По подразбиране изисква SSL/TLS връзка или връзка през сокет файл. В противен случай паролата се праща в чист текст.

-- 8. Потребител с auth_socket (само за Linux/Unix)
-- Този потребител НЯМА парола. Автентикацията се извършва на база потребителя на операционната система.
-- За да работи, трябва да се свържете към MySQL от ОС потребител с име 'testuser'.
CREATE USER 'testuser'@'localhost' IDENTIFIED WITH auth_socket;
GRANT SELECT ON test_db.* TO 'testuser'@'localhost';
-- КОМЕНТАР: Много сигурен метод за локални скриптове и системни задачи.
-- ЗА ДА ТЕСТВАТЕ: Влезте в терминала като потребител 'testuser' (или `sudo -u testuser mysql`) и изпълнете `mysql -u testuser`.


-- ====================================================================================
-- --- ЧАСТ 2: ПОТРЕБИТЕЛИ С ПОЛИТИКИ ЗА ПАРОЛИТЕ ---
-- ====================================================================================

-- 9. Потребител с незабавно изтичаща парола
-- При първото си влизане, потребителят ще бъде принуден да смени паролата си.
CREATE USER 'expired_user'@'localhost' IDENTIFIED BY 'MustChangeThis1!';
ALTER USER 'expired_user'@'localhost' PASSWORD EXPIRE;
GRANT SELECT ON test_db.* TO 'expired_user'@'localhost';

-- 10. Потребител с парола, която изтича след определен период
-- Паролата ще бъде валидна за 90 дни, след което ще трябва да се смени.
CREATE USER 'expiring_soon'@'localhost' IDENTIFIED BY 'ExpiresIn90Days!';
ALTER USER 'expiring_soon'@'localhost' PASSWORD EXPIRE INTERVAL 90 DAY;
GRANT SELECT ON test_db.* TO 'expiring_soon'@'localhost';

-- 11. Заключен потребител (Locked Account)
-- Този потребител не може да влезе в системата, докато акаунтът му не бъде отключен ръчно.
CREATE USER 'locked_user'@'%' IDENTIFIED BY 'CannotLogin1!';
ALTER USER 'locked_user'@'%' ACCOUNT LOCK;
GRANT SELECT ON test_db.* TO 'locked_user'@'%';
-- За да го отключите: ALTER USER 'locked_user'@'localhost' ACCOUNT UNLOCK;

-- 12. Потребител със сложна политика за паролата
-- Комбинация от няколко правила за сигурност.
CREATE USER 'policy_user'@'localhost' IDENTIFIED BY 'ComplexPolicyPass1!';
ALTER USER 'policy_user'@'localhost'
    PASSWORD HISTORY 5                 -- Не може да се преизползва никоя от последните 5 пароли.
    PASSWORD REUSE INTERVAL 365 DAY    -- Една и съща парола не може да се ползва по-често от веднъж годишно.
    FAILED_LOGIN_ATTEMPTS 3            -- Акаунтът се заключва след 3 неуспешни опита за вход.
    PASSWORD_LOCK_TIME UNBOUNDED;      -- Заключването е за неопределено време (изисква ръчно отключване).
GRANT SELECT ON test_db.* TO 'policy_user'@'localhost';


-- ====================================================================================
-- --- ЧАСТ 3: Финализиране и проверка ---
-- ====================================================================================
FLUSH PRIVILEGES;

SELECT 'Разширеният списък с тестови потребители е създаден успешно!' AS Status;

-- Заявка за проверка на създадените потребители и техните настройки
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