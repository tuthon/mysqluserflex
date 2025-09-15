#!/bin/bash

#!/bin/bash

SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(cd "$(dirname "$0")" && pwd)

echo "▶️ Стартиран е $SCRIPT_NAME от $SCRIPT_PATH"
echo "📌 Версия на скрипта: v1.0.16"

# Скрипт за архивиране и възстановяване на MySQL потребители
# Поддържа MySQL 5.6, 5.7 и 8.0+
# Поддържа експортиране от 8.0 към по-стари версии чрез --target-version
# Използва SHOW GRANTS за безопасно генериране на CREATE USER и GRANT
# По подразбиране системните потребители се пропускат, освен ако не се подаде --include-system-users
# Архивиране от MySQL 8.0 към MySQL 8.0 (по подразбиране): ./backup_users.sh -m backup -h localhost -u root -f users.sql
# Архивиране от MySQL 8.0 към MySQL 5.6: ./backup_users.sh -m backup -h localhost -u root -f users_56.sql --target-version 5.6
# Архивиране от MySQL 8.0 към MySQL 5.7: ./backup_users.sh -m backup -h localhost -u root -f users_57.sql --target-version 5.7
# Възстановяване: ./backup_users.sh -m restore -h localhost -u root -f users_56.sql


# --------- Променливи по подразбиране -----------
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
  echo "Използване:"
  echo "  $0 -m [backup|restore] -h host -u user [-p pass] -f файл.sql [--target-version 5.6|5.7|8.0] [--include-system-users] [--downgrade-passwords legacy] [--force-convert-plugin] [--port] [--socket] [--user=username] [--generate-passwords]"
  echo ""
  echo "Аргументи:"
  echo "  -m  backup или restore"
  echo "  -h  MySQL хост (по подразбиране: localhost)"
  echo "  -u  MySQL потребител"
  echo "  -p  MySQL парола (ако не е подадена, ще се изиска интерактивно)"
  echo "  -P  MySQL Порт за връзка с MySQL (по подразбиране: 3306)"  
  echo "  -f  Файл за архив/възстановяване"
  echo "  --target-version  Целева версия на MySQL при backup (по подразбиране: текущата версия)"
  echo "  --include-system-users  Включва системните потребители в архива (по подразбиране се пропускат)"
  echo "  --downgrade-passwords legacy  Преобразува новите пароли от 8.0 към SHA1 формат (изисква ALTER USER преди това)"
  echo "  --force-convert-plugin  Насилствена конверсия към mysql_native_password, ако целевата версия е 5.6"
  echo "  --port  Порт за връзка с MySQL (пример: 3306)"
  echo "  --socket Път до socket файл за локална връзка (пример: /var/run/mysqld/mysqld.sock)"
  echo "  --user=username  Създава архив само за конкретния потребител (при режим backup)"
  echo "  --generate-passwords  Създава произволни сигурни пароли за MYSQL потребителите"
  
  exit 1
}

# Четене на параметрите
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


# Изграждаме базовия mysql клиент команден низ с параметрите
# Това осигурява пълна съвместимост със socket/port при backup и restore
build_mysql_command() {
  local cmd=(mysql -u"$MYSQL_USER")
  [[ -n "$MYSQL_PASS" ]] && cmd+=( -p"$MYSQL_PASS" )
  [[ -n "$MYSQL_HOST" ]] && cmd+=( -h "$MYSQL_HOST" )
  [[ -n "$MYSQL_PORT" ]] && cmd+=( -P "$MYSQL_PORT" )
  [[ -n "$MYSQL_SOCKET" ]] && cmd+=( --socket="$MYSQL_SOCKET" )
  echo "${cmd[@]}"
}


# Списък със системни потребители, които да изключим от архивирането
SYSTEM_USERS=(
  'mysql.session'
  'mysql.sys'
  'mysql.infoschema'
  'mysqlxsys'
  'root'
)

# Функция за проверка дали даден потребител е системен
is_system_user() {
  local user="$1"
  for sys_user in "${SYSTEM_USERS[@]}"; do
    if [[ "$user" == "$sys_user" ]]; then
      return 0
    fi
  done
  return 1
}

# Функция за откриване на основната версия на MySQL
detect_mysql_version() {
  if ! command -v mysql >/dev/null 2>&1; then
    echo "❌ Грешка: Командата 'mysql' не е налична в PATH. Уверете се, че MySQL клиентът е инсталиран."
    exit 1
  fi
 
  local version
  version=$(eval "$(build_mysql_command) -N -e 'SELECT VERSION();'" 2>/dev/null)
  

  if [[ -z "$version" ]]; then
    echo "❌ Неуспешно извличане на версията на MySQL. Проверете дали имате достъп до сървъра и дали параметрите са коректни."
    exit 1
  fi

  if [[ $version =~ ^5\.6 ]]; then
    MYSQL_MAJOR_VERSION="5.6"
  elif [[ $version =~ ^5\.7 ]]; then
    MYSQL_MAJOR_VERSION="5.7"
  elif [[ $version =~ ^8\. ]]; then
    MYSQL_MAJOR_VERSION="8.0"
  else
    echo "⚠️ Неподдържана или неразпозната MySQL версия: $version"
    exit 1
  fi
}

# Филтрира неподдържани в MySQL 5.6 глобални привилегии
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

# Генерира DROP USER блок, съвместим с MySQL 5.6
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

 # Генерира парола от 12-16 символа, съдържаща главни, малки, цифри и специални символи
generate_strong_password() {
  LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()-_=+[]{}<>?' </dev/urandom | head -c 14
}

if [[ "$GENERATE_PASSWORDS" -eq 1 ]]; then
	PASSWORD_FILE="${FILE%.*}.txt"
	> "$PASSWORD_FILE"  # Това ще създаде/нулира файла с потребителите и паролите
fi

[[ -z "$MODE" || -z "$MYSQL_HOST" || -z "$MYSQL_USER" || -z "$MYSQL_PORT" || -z "$FILE" ]] && usage


# Подготовка на WHERE клаузата, ако е подаден --user
if [[ -n "$FILTER_USER" ]]; then
  IFS=',' read -ra USERS <<< "$FILTER_USER"
  USER_CONDITIONS=""
  for u in "${USERS[@]}"; do
    USER_CONDITIONS+="'$u',"
  done
  USER_CONDITIONS="${USER_CONDITIONS%,}"  # махаме последната запетая
  WHERE_CLAUSE="WHERE User IN ($USER_CONDITIONS)"
else
  WHERE_CLAUSE=""
fi


if [[ $PROMPT_PASS -eq 1 ]]; then
  read -s -p "Въведи парола за MySQL потребителя '$MYSQL_USER': " MYSQL_PASS
  echo
fi

# Проверка дали всички избрани потребители съществуват (поддържа user и user@host)
if [[ -n "$FILTER_USER" ]]; then
  IFS=',' read -ra USERS <<< "$FILTER_USER"
  for u in "${USERS[@]}"; do
    # Поддържа формати "dba" и "dba@localhost"
    if [[ "$u" == *"@"* ]]; then
      username="${u%@*}"
      hostname="${u#*@}"
    else
      username="$u"
      hostname="%"
    fi

    # Явно задаваме timeout, -B/-N за безшумен изход и трием whitespace
    exists=$($(build_mysql_command) --connect-timeout=8 -B -N \
      -e "SELECT COUNT(*) FROM mysql.user WHERE User='${username}' AND Host='${hostname}';" 2>/dev/null \
      | tr -d '[:space:]')

    # Ако заявката се провали, $exists може да е празно → третираме като 0
    [[ -z "$exists" ]] && exists=0

    if [[ "$exists" -lt 1 ]]; then
      echo "❌ Грешка: Потребителят '${username}'@'${hostname}' не съществува в MySQL сървъра."
      exit 1
    fi
  done
fi

# Определяне на версията на MySQL
detect_mysql_version
[[ -z "$TARGET_VERSION" ]] && TARGET_VERSION="$MYSQL_MAJOR_VERSION"

# Проверка дали даден потребител съществува
user_exists() {
  local user="$1"
  local host="$2"
  local count
  count=$(eval "$(build_mysql_command) -N -e \"SELECT COUNT(*) FROM mysql.user WHERE user='$user' AND host='$host';\"" 2>/dev/null)  
  
  [[ "$count" -gt 0 ]]
}

# Проверка дали е валиден стар SHA1 хеш
is_valid_sha1_hash() {
  [[ "$1" =~ ^\*[A-F0-9]{40}$ ]]
}

if [[ "$MODE" == "backup" ]]; then
    echo "▶️ Стартиране на архивиране на MySQL потребители..."

    if [[ -f "$FILE" ]]; then
      read -p "⚠️ Файлът $FILE вече съществува. Презаписване? (y/n): " confirm
      [[ "$confirm" != "y" ]] && exit 1
    fi

    echo "-- Архив на потребители и привилегии" > "$FILE"
    echo "-- Източник: MySQL $MYSQL_MAJOR_VERSION, Целева версия: $TARGET_VERSION" >> "$FILE"

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

# echo "ДЕБЪГ: Стойността на променливите е \$user: '$user'" echo "ДЕБЪГ: Стойността на променливите е \$host: '$host'" echo "ДЕБЪГ: Стойността на променливите е \$plugin: '$plugin'" echo "ДЕБЪГ: Стойността на променливите е \$auth: '$auth'" echo "ДЕБЪГ: Стойността на променливите е \$auth_hex: '$auth_hex'" echo "ДЕБЪГ: Стойността на променливите е \$pass_expired: '$pass_expired'" echo "ДЕБЪГ: Стойността на променливите е \$pass_changed: '$pass_changed'" 
 
   if [[ $INCLUDE_SYSTEM_USERS -eq 0 ]] && is_system_user "$user"; then
      echo "⏭ Пропускане на системен потребител: '$user'@'$host'"
      continue
   fi

   echo "-- Потребител: '$user'@'$host'" >> "$FILE"

   if [[ "$TARGET_VERSION" == "5.6" ]]; then

      generate_safe_drop_user "$user" "$host" >> "$FILE"
        
      if [[ "$GENERATE_PASSWORDS" -eq 1 ]]; then
         rand_pass=$(generate_strong_password)
         echo "CREATE USER '$user'@'$host' IDENTIFIED BY '$rand_pass';" >> "$FILE"
         echo "👤 Създаден потребител: '$user'@'$host' с парола: $rand_pass" >> "$PASSWORD_FILE"
      else
         if [[ "$auth" == "__EMPTY__" ]]; then
             echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '';" >> "$FILE"
         elif is_valid_sha1_hash "$auth"; then   
             echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '$auth';" >> "$FILE"
         else
            echo "-- ⚠️ Паролата не е съвместима с MySQL 5.6 (plugin: $plugin)." >> "$FILE"
            if [[ $DOWNGRADE_PASSWORDS -eq 1 ]]; then
               echo "-- 🔁 Очаква се паролата да е предварително преобразувана чрез ALTER USER ... IDENTIFIED WITH mysql_native_password BY 'парола'" >> "$FILE"
               echo "CREATE USER '$user'@'$host' IDENTIFIED BY PASSWORD '$auth';" >> "$FILE"
            elif [[ $FORCE_CONVERT_PLUGIN -eq 1 ]]; then
               echo "-- 🔁 Принудителна конверсия към mysql_native_password с празна парола" >> "$FILE"
               echo "CREATE USER '$user'@'$host' IDENTIFIED WITH 'mysql_native_password' BY '';" >> "$FILE"
            else
               if [[ "$MYSQL_MAJOR_VERSION" == "5.6" ]]; then
                  echo "CREATE USER '$user'@'$host' IDENTIFIED BY '$auth';" >> "$FILE"
               else
                  echo "-- ⚠️ Може да избереш между създаване с празна парола или смяна на типа на паролата чрез ALTER USER." >> "$FILE"
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
         echo "👤 Създаден потребител: '$user'@'$host' с парола: $rand_pass" >> "$PASSWORD_FILE"
      else

         # ако не генерираме нови пароли
         if [[ "$auth" == "__EMPTY__" ]]; then
            # празна парола
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS '';" >> "$FILE"
         elif [[ "$plugin" == "mysql_native_password" && "$auth" == \** ]]; then
            # ASCII хеш '*....' е безопасен като текст
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS '$auth';" >> "$FILE"
         else
            # бинарните стойности (напр. caching_sha2_password) подаваме като 0xHEX
            echo "CREATE USER \`$user\`@\`$host\` IDENTIFIED WITH '$plugin' AS 0x$auth_hex;" >> "$FILE"
         fi
      fi
	  
      # Ако има акаунта е заключен
      if [[ "$locked" == "Y" ]]; then
         echo "ALTER USER '$user'@'$host' ACCOUNT LOCK;" >> "$FILE"
      fi
	  
      # Ако е конфигуриран да не може да се преизползва никоя от последните 5 пароли.
      if [[ "$Pass_reuse_history" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD HISTORY $Pass_reuse_history;" >> "$FILE"
      fi	  

      # Ако е конфигуриран да не може една и съща парола не може да се ползва по-често от веднъж годишно.
      if [[ "$Pass_reuse_time" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD REUSE INTERVAL $Pass_reuse_time DAY;" >> "$FILE"
      fi

      # Ако има конфигуриран максимален брой конекции 
      if [[ "$max_user_connections" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' WITH MAX_USER_CONNECTIONS $max_user_connections;" >> "$FILE"
      fi

      # Ако има конфигуриран Акаунтът да се заключва след определен брой неуспешни опита за вход.
      if [[ "$failed_login_attempts" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' FAILED_LOGIN_ATTEMPTS $failed_login_attempts;" >> "$FILE"
      fi

      # Ако има конфигуриран Заключването е за неопределено/определено време (изисква ръчно отключване).
      if [[ "$password_lock_time_days" -eq -1 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD_LOCK_TIME UNBOUNDED;" >> "$FILE"
      elif [[ "$password_lock_time_days" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD_LOCK_TIME password_lock_time_days DAY;" >> "$FILE"
      fi

      # Ако има дефинирани определени дни в които паролата да е валидна 
      if [[ "$pass_lifetime" -gt 0 ]]; then
         echo "ALTER USER '$user'@'$host' PASSWORD EXPIRE INTERVAL $pass_lifetime DAY;" >> "$FILE"

         if [[ -n "$pass_changed" ]]; then
            echo "-- Последна промяна на паролата за '$user'@'$host': $pass_changed" >> "$FILE"
         fi
      fi

	fi
	
   # Ако паролата трябва да се смени при първо влизане
   if [[ "$pass_expired" == "Y" || "$pass_expired" == "1" ]]; then
      echo "ALTER USER '$user'@'$host' PASSWORD EXPIRE;" >> "$FILE"
   fi

   if grants=$(eval "$(build_mysql_command) -N -e \"SHOW GRANTS FOR \\\`$user\\\`@\\\`$host\\\`\"" 2>/dev/null); then

      if [[ $? -eq 0 ]]; then
         filtered_grants=$(filter_grants_for_target_version "$grants")

         # Премахни IDENTIFIED BY PASSWORD
         filtered_grants=$(echo "$filtered_grants" | sed -E "s/[[:space:]]*IDENTIFIED BY PASSWORD '[^']+'//g" | sed -E 's/[[:space:]]+WITH GRANT OPTION/ WITH GRANT OPTION/')

      while read -r grant; do
         echo "$grant;" >> "$FILE"
      done <<< "$filtered_grants"
      else
         echo "-- ⚠️ Грешка при извличане на привилегии за '$user'@'$host'" >> "$FILE"
      fi

		filtered_grants=$(filter_grants_for_target_version "$grants")

		# Премахни IDENTIFIED BY PASSWORD
		filtered_grants=$(echo "$filtered_grants" | sed -E "s/[[:space:]]*IDENTIFIED BY PASSWORD '[^']+'//g" | sed -E 's/[[:space:]]+WITH GRANT OPTION/ WITH GRANT OPTION/')

   else
      echo "-- ⚠️ Неуспешно извличане на GRANTS за $user@$host" >> "$FILE"
   fi
    
   echo "FLUSH PRIVILEGES;" >> "$FILE"
   done

   echo "✅ Архивирането приключи: $FILE"

   elif [[ "$MODE" == "restore" ]]; then
      echo "▶️ Възстановяване на потребителите от $FILE..."
      mysql -u"$MYSQL_USER" -p"$MYSQL_PASS" -h "$MYSQL_HOST" -P "$MYSQL_PORT" < "$FILE"
      echo "✅ Възстановяването приключи."
   else
      echo "⚠️ Невалиден режим! Използвай -m [backup|restore]"
      usage
fi
