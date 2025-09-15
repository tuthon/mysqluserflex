#!/bin/bash

#!/bin/bash

SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)

echo "▶️ $SCRIPT_NAME started from $SCRIPT_PATH"
echo "📌 Script version: v1.0.16"

# Script for backing up and restoring MySQL users
# Supports MySQL 5.6, 5.7, and 8.0+
# Allows exporting from 8.0 to older versions using --target-version
# Uses SHOW GRANTS for safe generation of CREATE USER and GRANT statements
# By default, system users are skipped unless --include-system-users is specified
# Backup from MySQL 8.0 to MySQL 8.0 (default): ./backup_users.sh -m backup -h localhost -u root -f users.sql
# Backup from MySQL 8.0 to MySQL 5.6: ./backup_users.sh -m backup -h localhost -u root -f users_56.sql --target-version 5.6
# Backup from MySQL 8.0 to MySQL 5.7: ./backup_users.sh -m backup -h localhost -u root -f users_57.sql --target-version 5.7
# Restore: ./backup_users.sh -m restore -h localhost -u root -f users_56.sql


# --------- Default variables -----------
FILTER_USER=""
MYSQL_HOST=""
MYSQL_USER=""
MYSQL_PASS=""
MYSQL_PORT=3306
MODE=""
FILE=""
PROMPT_PASS=1
INCLUDE_SYSTEM_USERS=0
MYSQL_MAJOR_VERSION=""
TARGET_VERSION=""
DOWNGRADE_PASSWORDS=0
FORCE_CONVERT_PLUGIN=0
GENERATE_PASSWORDS=0
# -----------------------------------------------

usage() {
  echo "Usage:"
  echo "  $0 -m [backup|restore] -h host -u user [-p pass] -f file.sql [--target-version 5.6|5.7|8.0] [--include-system-users] [--downgrade-passwords legacy] [--force-convert-plugin] [--port] [--socket] [--user=username] [--generate-passwords]"
  echo ""
  echo "Arguments:"
  echo "  -m  backup or restore"
  echo "  -h  MySQL host (default: localhost)"
  echo "  -u  MySQL user"
  echo "  -p  MySQL password (if not provided, will be requested interactively)"
  echo "  -P  MySQL port for connection (default: 3306)"  
  echo "  -f  File for backup/restore"
  echo "  --target-version  Target MySQL version for backup (default: current version)"
  echo "  --include-system-users  Includes system users in the backup (skipped by default)"
  echo "  --downgrade-passwords legacy  Converts new 8.0+ passwords to SHA1 format (requires ALTER USER beforehand)"
  echo "  --force-convert-plugin  Force conversion to mysql_native_password if the target version is 5.6"
  echo "  --port  MySQL connection port (example: 3306)"
  echo "  --socket Path to the socket file for local connection (example: /var/run/mysqld/mysqld.sock)"
  echo "  --user=username  Creates a backup only for the specified user (backup mode)"
  echo "  --generate-passwords  Generates random strong passwords for MySQL users"
  
  exit 1
}


# Reading the parameters
while [[ $# -gt 0 ]]; do
  case "$1" in
    --user=*)
      FILTER_USER="${1#*=}"
      shift
      ;;

    -m) MODE="$2"; shift 2;;
    -h) MYSQL_HOST="$2"; shift 2;;
    -u) MYSQL_USER="$2"; shift 2;;
    -p) MYSQL_PASS="$2"; PROMPT_PASS=0; shift 2;;
    -P) MYSQL_PORT="$2"; shift 2;;
    -f) FILE="$2"; shift 2;;
    --target-version) TARGET_VERSION="$2"; shift 2;;
    --include-system-users) INCLUDE_SYSTEM_USERS=1; shift;;
    --downgrade-passwords) DOWNGRADE_PASSWORDS=1; shift 2;;
    --force-convert-plugin) FORCE_CONVERT_PLUGIN=1; shift;;
    --port) MYSQL_PORT="$2"; shift 2;;
    --socket) MYSQL_SOCKET="$2"; shift 2;;    
    --generate-passwords) GENERATE_PASSWORDS=1; shift;;
    *) usage;;
  esac
done


# Build the base mysql client command string with parameters
# Ensures full compatibility with socket/port in both backup and restore
build_mysql_command() {
  local cmd=(mysql -u"$MYSQL_USER")
  [[ -n "$MYSQL_PASS" ]] && cmd+=( -p"$MYSQL_PASS" )
  [[ -n "$MYSQL_HOST" ]] && cmd+=( -h "$MYSQL_HOST" )
  [[ -n "$MYSQL_PORT" ]] && cmd+=( -P "$MYSQL_PORT" )
  [[ -n "$MYSQL_SOCKET" ]] && cmd+=( --socket="$MYSQL_SOCKET" )
  echo "${cmd[@]}"
}


# List of system users to exclude from backup
SYSTEM_USERS=(
  'mysql.session'
  'mysql.sys'
  'mysql.infoschema'
  'mysqlxsys'
  'root'
)

# Function to check if a given user is a system account
is_system_user() {
  local user="$1"
  for sys_user in "${SYSTEM_USERS[@]}"; do
    if [[ "$user" == "$sys_user" ]]; then
      return 0
    fi
  done
  return 1
}

# Function to detect the major MySQL version
detect_mysql_version() {
  if ! command -v mysql >/dev/null 2>&1; then
    echo "❌ Error: The 'mysql' command is not available in PATH. Please ensure that the MySQL client is installed."

    exit 1
  fi
 
  local version
  version=$(eval "$(build_mysql_command) -N -e 'SELECT VERSION();'" 2>/dev/null)
  

  if [[ -z "$version" ]]; then
    echo "❌ Failed to retrieve the MySQL version. Check if you have access to the server and if the parameters are correct."
    exit 1
  fi

  if [[ $version =~ ^5\.6 ]]; then
    MYSQL_MAJOR_VERSION="5.6"
  elif [[ $version =~ ^5\.7 ]]; then
    MYSQL_MAJOR_VERSION="5.7"
  elif [[ $version =~ ^8\. ]]; then
    MYSQL_MAJOR_VERSION="8.0"
  else
    echo "⚠️ Unsupported or unrecognized MySQL version: $version"
    exit 1
  fi
}

# Filter out global privileges not supported in MySQL 5.6
filter_grants_for_target_version() {
  local input_grants="$1"
  if [[ "$TARGET_VERSION" == "5.6" ]]; then
    echo "$input_grants" \
      | sed -E 's/([ ,]*)CREATE ROLE([ ,]*)//g' \
      | sed -E 's/([ ,]*)DROP ROLE([ ,]*)//g' \
      | sed -E 's/,[[:space:]]*ON/ ON/' \
      | sed -E 's/\bTRIGGERON\b/TRIGGER ON/g' \
      | grep -vE '(APPLICATION_PASSWORD_ADMIN|AUDIT_|AUTHENTICATION_POLICY_ADMIN|BACKUP_ADMIN|BINLOG_|CLONE_ADMIN|CONNECTION_ADMIN|ENCRYPTION_KEY_ADMIN|FIREWALL_EXEMPT|GROUP_REPLICATION_|INNODB_REDO_|PERSIST_RO_VARIABLES_ADMIN|REPLICATION_APPLIER|REPLICATION_SLAVE_ADMIN|RESOURCE_GROUP_|ROLE_ADMIN|SENSITIVE_VARIABLES_OBSERVER|SERVICE_CONNECTION_ADMIN|SESSION_VARIABLES_ADMIN|SET_USER_ID|SHOW_ROUTINE|SYSTEM_USER|SYSTEM_VARIABLES_ADMIN|TABLE_ENCRYPTION_ADMIN|TELEMETRY_LOG_ADMIN|XA_RECOVER_ADMIN)'
  else
    echo "$input_grants"
  fi
}

# Generate DROP USER block compatible with MySQL 5.6
generate_safe_drop_user() {
  local user="$1"
  local host="$2"
  echo "-- Премахване на потребител: '$user'@'$host' (safe DROP)"
  echo "SET @user_exists := (SELECT COUNT(*) FROM mysql.user WHERE user = '$user' AND host = '$host');"
  echo "SET @drop_sql := IF(@user_exists > 0, 'DROP USER \'$user\'@\'$host\'', 'SELECT \"Потребителят не съществува\"');"
  echo "PREPARE stmt FROM @drop_sql;"
  echo "EXECUTE stmt;"
  echo "DEALLOCATE PREPARE stmt;"
}

# Generate a password of 12–16 characters, containing uppercase, lowercase, digits, and special symbols
generate_strong_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}<>?' </dev/urandom | head -c 14
}

if [[ "$GENERATE_PASSWORDS" -eq 1 ]]; then
	PASSWORD_FILE="${FILE%.*}.txt"
	> "$PASSWORD_FILE"  # This will create/reset the file with users and passwords
fi

[[ -z "$MODE" || -z "$MYSQL_HOST" || -z "$MYSQL_USER" || -z "$MYSQL_PORT" || -z "$FILE" ]] && usage


# Prepare the WHERE clause if --user is provided
if [[ -n "$FILTER_USER" ]]; then
  IFS=',' read -ra USERS <<< "$FILTER_USER"
  USER_CONDITIONS=""
  for u in "${USERS[@]}"; do
    USER_CONDITIONS+="'$u',"
  done
  USER_CONDITIONS="${USER_CONDITIONS%,}"  # remove the trailing comma
  WHERE_CLAUSE="WHERE User IN ($USER_CONDITIONS)"
else
  WHERE_CLAUSE=""
fi


if [[ $PROMPT_PASS -eq 1 ]]; then
  read -s -p "Enter password for MySQL user '$MYSQL_USER': " MYSQL_PASS
  echo
fi

# Check if all selected users exist (supports user and user@host)
if [[ -n "$FILTER_USER" ]]; then
  IFS=',' read -ra USERS <<< "$FILTER_USER"
  for u in "${USERS[@]}"; do
    # Supports formats "dba" and "dba@localhost"
    if [[ "$u" == *"@"* ]]; then
      username="${u%@*}"
      hostname="${u#*@}"
    else
      username="$u"
      hostname="%"
    fi

    # Explicitly set timeout, -B/-N for silent output, and trim whitespace
    exists=$($(build_mysql_command) --connect-timeout=8 -B -N \
      -e "SELECT COUNT(*) FROM mysql.user WHERE User='${username}' AND Host='${hostname}';" 2>/dev/null \
      | tr -d '[:space:]')

    # If the query fails, $exists may be empty → treat as 0
    [[ -z "$exists" ]] && exists=0

    if [[ "$exists" -lt 1 ]]; then
      echo "❌ Error: User '${username}'@'${hostname}' does not exist on the MySQL server."
      exit 1
    fi
  done
fi

# Determine MySQL version
detect_mysql_version
[[ -z "$TARGET_VERSION" ]] && TARGET_VERSION="$MYSQL_MAJOR_VERSION"

# Check if a given user exists
user_exists() {
  local user="$1"
  local host="$2"
  local count
  count=$(eval "$(build_mysql_command) -N -e \"SELECT COUNT(*) FROM mysql.user WHERE user='$user' AND host='$host';\"" 2>/dev/null)  
  
  [[ "$count" -gt 0 ]]
}

# Check if it is a valid old SHA1 hash
is_valid_sha1_hash() {
  [[ "$1" =~ ^\*[A-F0-9]{40}$ ]]
}

if [[ "$MODE" == "backup" ]]; then
    echo "▶️ Starting backup of MySQL users..."

    if [[ -f "$FILE" ]]; then
      read -p "⚠️ The file $FILE already exists. Overwrite? (y/n): " confirm
      [[ "$confirm" != "y" ]] && exit 1
    fi

    echo "-- Backup of users and privileges" > "$FILE"
    echo "-- Source: MySQL $MYSQL_MAJOR_VERSION, Target version: $TARGET_VERSION" >> "$FILE"

	if [[ "$MYSQL_MAJOR_VERSION" == "5.6" ]]; then
		QUERY="SELECT User, Host, plugin, 														 
                 IF(password='', '__EMPTY__', password) AS authentication_string,							 
					  'N' AS auth_hex, 
					  password_expired, 
					  'N' as password_last_changed, 							 
					  'N' AS password_lifetime, 
					  'N' AS account_locked,
					  
					  0 AS Pass_reuse_history, 
					  0 AS Pass_reuse_time, 
			-- Password locking
					  0 AS failed_login_attempts,
					  0 AS password_lock_time_days,
			-- Resource limits
					  0 AS max_user_connections
						FROM mysql.user $WHERE_CLAUSE;"
	else
		QUERY="SELECT User, Host, plugin, 
					  IF(authentication_string='', '__EMPTY__', authentication_string) as authentication_string, 
					  IFNULL(HEX(authentication_string), '') AS auth_hex, 
					  password_expired, 
					  IFNULL(password_last_changed, '') as password_last_changed, 
					  password_lifetime - IFNULL(DATEDIFF(NOW(), password_lifetime), 0) as password_lifetime, 
					  account_locked,		  
					  
					  IFNULL(Password_reuse_history, 0) AS Pass_reuse_history, 
					  IFNULL(Password_reuse_time, 0) AS Pass_reuse_time,
			 -- Password locking
					  IFNULL(JSON_UNQUOTE(JSON_EXTRACT(User_attributes, '$.Password_locking.failed_login_attempts')), 0) AS failed_login_attempts,
					  IFNULL(JSON_UNQUOTE(JSON_EXTRACT(User_attributes, '$.Password_locking.password_lock_time_days')), 0) AS password_lock_time_days,
			 -- Resource limits
					  IFNULL(JSON_UNQUOTE(JSON_EXTRACT(User_attributes, '$.resource_limits.MAX_USER_CONNECTIONS')), 0) AS max_user_connections
						FROM mysql.user $WHERE_CLAUSE;"
	fi  

   eval "$(build_mysql_command) -N -e \"$QUERY\"" | \

   while IFS=$'\t' read -r user host plugin auth auth_hex pass_expired pass_changed pass_lifetime locked Pass_reuse_history Pass_reuse_time failed_login_attempts password_lock_time_days max_user_connections; do
 
   if [[ $INCLUDE_SYSTEM_USERS -eq 0 ]] && is_system_user "$user"; then
      echo "⏭ Skipping system user: '$user'@'$host'"
      continue
   fi

   echo "-- User: '$user'@'$host'" >> "$FILE"

   if [[ "$TARGET_VERSION" == "5.6" ]]; then

      generate_safe_drop_user "$user" "$host" >> "$FILE"
        
      if [[ "$GENERATE_PASSWORDS" -eq 1 ]]; then
         rand_pass=$(generate_strong_password)
         echo "CREATE USER '$user'@'$host' IDENTIFIED BY '$rand_pass';" >> "$FILE"
         echo "👤 Created user: '$user'@'$host' with password: $rand_pass" >> "$PASSWORD_FILE"
      else
         if [[ "$auth" == "__EMPTY__" ]]; then
             echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '';" >> "$FILE"
         elif is_valid_sha1_hash "$auth"; then   
             echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '$auth';" >> "$FILE"
         else
            echo "-- ⚠️ Password is not compatible with MySQL 5.6 (plugin: $plugin)." >> "$FILE"
            if [[ $DOWNGRADE_PASSWORDS -eq 1 ]]; then
               echo "-- 🔁 The password is expected to be pre-converted using ALTER USER ... IDENTIFIED WITH mysql_native_password BY 'password'" >> "$FILE"
               echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '$auth';" >> "$FILE"
            elif [[ $FORCE_CONVERT_PLUGIN -eq 1 ]]; then
               echo "-- 🔁 Forced conversion to mysql_native_password with an empty password" >> "$FILE"
               echo "CREATE USER '$user'@'$host' IDENTIFIED WITH 'mysql_native_password' BY '';" >> "$FILE"
            else
               if [[ "$MYSQL_MAJOR_VERSION" == "5.6" ]]; then
                  echo "CREATE USER '$user'@'$host' IDENTIFIED BY '$auth';" >> "$FILE"
               else
                  echo "-- ⚠️ You may choose between creating the user with an empty password or changing the password type via ALTER USER." >> "$FILE"
                  echo "CREATE USER '$user'@'$host' IDENTIFIED BY 'ADD NEW PASSWORD';" >> "$FILE"
               fi
            fi
         fi
      fi
  
	else

      echo "DROP USER IF EXISTS '$user'@'$host';" >> "$FILE"
      if [[ "$GENERATE_PASSWORDS" -eq 1 ]]; then
         rand_pass=$(generate_strong_password)
         echo "CREATE USER '$user'@'$host' IDENTIFIED BY '$rand_pass';" >> "$FILE"
         echo "👤 Created user: '$user'@'$host' with password: $rand_pass" >> "$PASSWORD_FILE"
      else

         # if are not generating new passwords
         if [[ "$auth" == "__EMPTY__" ]]; then
            # empty password
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS '';" >> "$FILE"
         elif [[ "$plugin" == "mysql_native_password" && "$auth" == \** ]]; then
            # ASCII hash '*....' is safe as plain text
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS '$auth';" >> "$FILE"
         else
            # binary values (e.g. caching_sha2_password) are provided as 0xHEX
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS 0x$auth_hex;" >> "$FILE"
         fi
      fi
	  
      # If the account is locked
      if [[ "$locked" == "Y" ]]; then
         echo "ALTER USER '$user'@'$host' ACCOUNT LOCK;" >> "$FILE"
      fi
	  
      # If configured so none of the last 5 passwords can be reused
      if [[ "$Pass_reuse_history" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD HISTORY $Pass_reuse_history;" >> "$FILE"
      fi	  

      # If configured so the same password cannot be used more often than once per year
      if [[ "$Pass_reuse_time" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD REUSE INTERVAL $Pass_reuse_time DAY;" >> "$FILE"
      fi

      # If a maximum number of connections is configured
      if [[ "$max_user_connections" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' WITH MAX_USER_CONNECTIONS $max_user_connections;" >> "$FILE"
      fi

      # If the account is configured to lock after a certain number of failed login attempts
      if [[ "$failed_login_attempts" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' FAILED_LOGIN_ATTEMPTS $failed_login_attempts;" >> "$FILE"
      fi

      # If configured so the lock is indefinite/for a fixed time (requires manual unlock).
      if [[ "$password_lock_time_days" -eq -1 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD_LOCK_TIME UNBOUNDED;" >> "$FILE"
      elif [[ "$password_lock_time_days" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD_LOCK_TIME password_lock_time_days DAY;" >> "$FILE"
      fi

      # If certain days are defined during which the password is valid
      if [[ "$pass_lifetime" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD EXPIRE INTERVAL $pass_lifetime DAY;" >> "$FILE"

         if [[ -n "$pass_changed" ]]; then
            echo "-- Last password change for '$user'@'$host': $pass_changed" >> "$FILE"
         fi
      fi

	fi
	
   # If the password must be changed at first login
   if [[ "$pass_expired" == "Y" || "$pass_expired" == "1" ]]; then
      echo "ALTER USER '$user'@'$host' PASSWORD EXPIRE;" >> "$FILE"
   fi

   if grants=$(eval "$(build_mysql_command) -N -e \"SHOW GRANTS FOR \\\`$user\\\`@\\\`$host\\\`\"" 2>/dev/null); then

      if [[ $? -eq 0 ]]; then
         filtered_grants=$(filter_grants_for_target_version "$grants")

         # Remove IDENTIFIED BY PASSWORD
         filtered_grants=$(echo "$filtered_grants" | sed -E "s/[[:space:]]*IDENTIFIED BY PASSWORD '[^']+'//g" | sed -E 's/[[:space:]]+WITH GRANT OPTION/ WITH GRANT OPTION/')

      while read -r grant; do
         echo "$grant;" >> "$FILE"
      done <<< "$filtered_grants"
      else
         echo "-- ⚠️ Error retrieving privileges for '$user'@'$host'" >> "$FILE"
      fi

		filtered_grants=$(filter_grants_for_target_version "$grants")

		# Remove IDENTIFIED BY PASSWORD
		filtered_grants=$(echo "$filtered_grants" | sed -E "s/[[:space:]]*IDENTIFIED BY PASSWORD '[^']+'//g" | sed -E 's/[[:space:]]+WITH GRANT OPTION/ WITH GRANT OPTION/')

   else
      echo "-- ⚠️ Failed to retrieve GRANTS for $user@$host" >> "$FILE"
   fi
    
   echo "FLUSH PRIVILEGES;" >> "$FILE"
   done

   echo "✅ Backup completed: $FILE"

   elif [[ "$MODE" == "restore" ]]; then
      echo "▶️ Restoring users from $FILE..."
      mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT" < "$FILE"
      echo "✅ Restore completed."
   else
      echo "⚠️ Invalid mode! Use -m [backup|restore]"
      usage
fi
