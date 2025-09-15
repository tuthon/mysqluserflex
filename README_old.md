# MySQLUserFlex

**MySQLUserFlex** is a Bash-based tool for backing up and restoring MySQL user accounts and privileges across multiple versions of MySQL (5.6, 5.7, 8.0+).  
It is designed to handle cross-version migrations, filtering out unsupported privileges and adapting SQL syntax automatically, ensuring safe and reliable restoration.

---

## Features

- ✅ Supports MySQL 5.6, 5.7, and 8.0+  
- ✅ Cross-version backups (e.g., from 8.0 → 5.6)  
- ✅ Skips system accounts by default (optional include)  
- ✅ Uses `SHOW GRANTS` for safe privilege extraction  
- ✅ Automatically adapts `CREATE USER` and `GRANT` syntax  
- ✅ Optional strong password generation (`--generate-passwords`)  
- ✅ Safe `DROP USER` handling for older versions without `IF EXISTS`  

---

## Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/yourusername/mysqluserflex.git
cd mysqluserflex
chmod +x backup_users.sh



Usage

MySQLUserFlex allows you to back up and restore MySQL users across versions (5.6, 5.7, 8.0+).
By default, system accounts are skipped unless explicitly included.

Backup Examples

Backup from MySQL 8.0 to MySQL 8.0 (default):

./backup_users.sh -m backup -h localhost -u root -f users.sql


Backup from MySQL 8.0 to MySQL 5.6:

./backup_users.sh -m backup -h localhost -u root -f users_56.sql --target-version 5.6


Backup from MySQL 8.0 to MySQL 5.7:

./backup_users.sh -m backup -h localhost -u root -f users_57.sql --target-version 5.7

Restore Example

Restore users from an existing backup:

./backup_users.sh -m restore -h localhost -u root -f users_56.sql

Arguments
Option	Description
-m	Mode: backup or restore
-h	MySQL host (default: localhost)
-u	MySQL user
-p	MySQL password (if not provided, requested interactively)
-P	MySQL port (default: 3306)
-f	Backup/restore file
--target-version	Target MySQL version for backup (default: current version)
--include-system-users	Include system accounts in backup (skipped by default)
--downgrade-passwords legacy	Convert MySQL 8.0 passwords to SHA1 (requires prior ALTER USER)
--force-convert-plugin	Force conversion to mysql_native_password (useful for 5.6)
--port	MySQL connection port (example: 3306)
--socket	Path to local socket file (example: /var/run/mysqld/mysqld.sock)
--user=username	Backup only a specific user
--generate-passwords	Generate random strong passwords for MySQL users
Example Output

When backing up a user from MySQL 8.0, MySQLUserFlex generates a compatible SQL script:

DROP USER IF EXISTS 'testuser'@'localhost';
CREATE USER 'testuser'@'localhost' IDENTIFIED WITH 'mysql_native_password' AS '*94BDCEBE19083CE2A1F959FD02F964C7AF4CFC29';
GRANT SELECT, INSERT ON `mydb`.* TO 'testuser'@'localhost';
FLUSH PRIVILEGES;


If --generate-passwords is enabled, an additional .txt file will contain new random passwords:

testuser@localhost = A8f!pQz#Xr2mKd

Example SQL Test File

You can generate test users with the following script:

CREATE USER 'readonly_user'@'%' IDENTIFIED BY 'readonly123';
GRANT SELECT ON *.* TO 'readonly_user'@'%';

CREATE USER 'readwrite_user'@'localhost' IDENTIFIED BY 'rwpass123';
GRANT SELECT, INSERT, UPDATE, DELETE ON testdb.* TO 'readwrite_user'@'localhost';