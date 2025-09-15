# MySQLUserFlex

**MySQLUserFlex** is a Bash-based tool for backing up and restoring MySQL user accounts and privileges across multiple versions of MySQL (5.6, 5.7, 8.0+).  
It is designed to handle cross-version migrations, filtering out unsupported privileges and adapting SQL syntax automatically, ensuring safe and reliable restoration.

---

## ✨ Features

- ✅ Supports MySQL 5.6, 5.7, and 8.0+
- ✅ Cross-version backups (e.g. from 8.0 → 5.6)
- ✅ Skips system accounts by default (optional include)
- ✅ Uses `SHOW GRANTS` for safe privilege extraction
- ✅ Automatically adapts `CREATE USER` and `GRANT` syntax
- ✅ Optional strong password generation (`--generate-passwords`)
- ✅ Safe `DROP USER` handling for older versions without `IF EXISTS`

---

## ⚙️ Installation

Clone the repository and make the script executable:

```bash
git clone https://github.com/yourusername/mysqluserflex.git
cd mysqluserflex
chmod +x mysqluserflex.sh
```

---

## 📖 Usage

MySQLUserFlex allows you to back up and restore MySQL users across versions (5.6, 5.7, 8.0+).  
By default, system accounts are skipped unless explicitly included.

---

## 💾 Backup Examples

**Backup from MySQL 8.0 to MySQL 8.0 (default):**
```bash
./mysqluserflex.sh -m backup -h localhost -u root -f users.sql
```

**Backup from MySQL 8.0 to MySQL 5.6:**
```bash
./mysqluserflex.sh -m backup -h localhost -u root -f users_56.sql --target-version 5.6
```

**Backup from MySQL 8.0 to MySQL 5.7:**
```bash
./mysqluserflex.sh -m backup -h localhost -u root -f users_57.sql --target-version 5.7
```

---

## 🔄 Restore Example

**Restore users from an existing backup:**
```bash
./mysqluserflex.sh -m restore -h localhost -u root -f users_56.sql
```

---

## 📌 Arguments

| Argument                       | Description                                                     |
|--------------------------------|-----------------------------------------------------------------|
| `-m`                           | backup or restore                                               |
| `-h`                           | MySQL host (default: localhost)                                 |
| `-u`                           | MySQL user                                                      |
| `-p`                           | MySQL password (if not provided, requested interactively)       |
| `-P`                           | MySQL port (default: 3306)                                      |
| `-f`                           | Backup/restore file                                             |
| `--target-version`             | Target MySQL version for backup (default: current version)      |
| `--include-system-users`       | Includes system accounts in backup (skipped by default)         |
| `--downgrade-passwords legacy` | Converts 8.0+ passwords to SHA1 (requires prior `ALTER USER`)   |
| `--force-convert-plugin`       | Force conversion to `mysql_native_password` (useful for 5.6)    |
| `--socket`                     | Path to MySQL socket file (e.g., `/var/run/mysqld/mysqld.sock`) |
| `--user=username`              | Backup only a specific user                                     |
| `--generate-passwords`         | Generates new random passwords for MySQL users                  |

---

## 📝 Example Output

When backing up a user from MySQL 8.0, MySQLUserFlex generates a compatible SQL script:

```sql
DROP USER IF EXISTS 'testuser'@'localhost';
CREATE USER 'testuser'@'localhost' IDENTIFIED WITH 'mysql_native_password' AS '*94BDCEBE19083CE2A1F959FD02F964C7AF4CFC29';
GRANT SELECT, INSERT ON `mydb`.* TO 'testuser'@'localhost';
FLUSH PRIVILEGES;
```

If `--generate-passwords` is enabled, an additional `.txt` file will contain random passwords:

```
testuser@localhost -> A8f!p9xzr2MKd
```

---

## 🧪 Example SQL Test File

You can generate test users with:

```sql
CREATE USER 'readonly_user'@'%' IDENTIFIED BY 'readonly123';
GRANT SELECT ON *.* TO 'readonly_user'@'%';

CREATE USER 'readwrite_user'@'localhost' IDENTIFIED BY 'rwpass123';
GRANT SELECT, INSERT, UPDATE, DELETE ON testdb.* TO 'readwrite_user'@'localhost';
```

---

## 📊 Results & Diagrams

### Migration Results
![Migration Results](docs/mysqluserflex_migration_results.png)

### Backup & Restore Process
![Backup & Restore Process](docs/backup_restore_process.png)

### MySQLUserFlex Workflow
![MySQLUserFlex Workflow](docs/mysqluserflex_workflow.jpg)

### Privilege Changes Between Versions
![Privileges](docs/mysql_privileges_vertical.svg)

---

## 📋 Tables

### Table 1. Comparative overview of existing methods and MySQLUserFlex

| Criterion             | mysqldump | mysqlpump | pt-show-grants | MySQLUserFlex |
|-----------------------|-----------|-----------|----------------|---------------|
| Version compatibility | No        | No        | Partial        | Yes           |
| Privilege filtering   | No        | No        | No             | Yes           |
| Intelligent formatting| No        | No        | Partial        | Yes           |
| Safe extraction       | Yes       | Yes       | Yes            | Yes           |
| Migration readiness   | No        | No        | Partial        | Yes           |

---

### Table 2. Key Differences in Privileges
![Table 2](docs/table2.jpg)

---

### Table 3. MySQL commands used in MySQLUserFlex

| Command | Description | Role in MySQLUserFlex |
|---------|-------------|-----------------------|
| SHOW GRANTS | Displays all privileges associated with a given user. | Extracts current rights and adapts them for migration. |
| SELECT … FROM mysql.user (and system tables) | Reads info from system tables (`mysql.user`, `mysql.db`, etc.). | Provides details for password hashes, SSL parameters, and adapts to schema changes. |
| CREATE USER | Creates a new account. | Recreates identical accounts in the target DB. |
| GRANT | Assigns privileges. | Restores original rights, adapted for target version. |
| ALTER USER | Modifies parameters of existing accounts. | Safer than recreating users in some migrations. |
| DROP USER | Deletes existing accounts. | Ensures no duplicates during restore. |
| FLUSH PRIVILEGES | Reloads privilege tables. | Ensures changes are applied immediately. |

---

### Table 4. Core Functions of MySQLUserFlex

| Function | Description | Role in MySQLUserFlex |
|----------|-------------|------------------------|
| `usage()` | Displays help/syntax and options | Invoked when params missing or invalid |
| `build_mysql_command()` | Builds MySQL CLI command | Centralizes mysql calls, avoids duplication |
| `is_system_user()` | Checks if account is system | Skips default accounts unless included |
| `detect_mysql_version()` | Detects server version | Sets compatibility (5.6 / 5.7 / 8.0+) |
| `filter_grants_for_target_version()` | Normalizes GRANT output | Removes unsupported privileges |
| `generate_safe_drop_user()` | Generates safe DROP USER | Ensures compatibility with older MySQL |
| `generate_strong_password()` | Creates random strong passwords | Enables controlled password rotation |
| `user_exists()` | Verifies account presence | Auxiliary check for diagnostics |
| `is_valid_sha1_hash()` | Validates legacy SHA1 | Ensures fallback for MySQL 5.6 passwords |

---

### Table 8. Results
![Table 8](docs/table8.jpg)

---

## 📜 License

This project is licensed under the MIT License – see the [LICENSE](LICENSE) file for details.
