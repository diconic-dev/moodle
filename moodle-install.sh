#!/bin/sh
set -eu

if [ ! -f .env.example ]; then
    echo ".env.example not found. Run this script from the repository root." >&2
    exit 1
fi

printf "Environment (dev/prod) [dev]: "
read -r environment
environment=${environment:-dev}

case "$environment" in
    dev|development)
        environment=dev
        compose_file=compose.yaml
        default_wwwroot=http://localhost:8080
        ;;
    prod|production)
        environment=prod
        compose_file=compose.production.yaml
        default_wwwroot=https://moodle.example.com
        ;;
    *)
        echo "Environment must be 'dev' or 'prod'." >&2
        exit 1
        ;;
esac

if docker volume inspect moodle_dbdata >/dev/null 2>&1; then
    cat >&2 <<'EOF'
Database volume moodle_dbdata already exists.
The installer will not change database credentials or run database
initialization against an existing volume.

Use the original database credentials in .env and run:
  docker compose up -d --force-recreate app web cron

If this is an intentionally empty local volume, remove it manually before
running this installer again.
EOF
    exit 1
fi

if [ ! -f .env ]; then
    cp .env.example .env
    echo "Created .env from .env.example."
else
    echo "Using existing .env."
fi

set_env() {
    key=$1
    value=$2
    temporary=$(mktemp)
    KEY=$key VALUE=$value awk '
        $0 ~ "^" ENVIRON["KEY"] "=" {
            print ENVIRON["KEY"] "=" ENVIRON["VALUE"]
            found = 1
            next
        }
        { print }
        END {
            if (!found) {
                print ENVIRON["KEY"] "=" ENVIRON["VALUE"]
            }
        }
    ' .env > "$temporary"
    mv "$temporary" .env
}

printf "Moodle database name [moodle]: "
read -r db_name
db_name=${db_name:-moodle}

printf "Moodle database user [moodle]: "
read -r db_user
db_user=${db_user:-moodle}

prompt_secret() {
    label=$1
    printf "%s: " "$label"
    stty -echo
    read -r secret
    stty echo
    printf "\n"
    PROMPT_SECRET=$secret
}

prompt_secret "Moodle database password"
db_password=$PROMPT_SECRET
if [ -z "$db_password" ]; then
    echo "Database password cannot be empty." >&2
    exit 1
fi

prompt_secret "Moodle database root password"
db_root_password=$PROMPT_SECRET
if [ -z "$db_root_password" ]; then
    echo "Database root password cannot be empty." >&2
    exit 1
fi

printf "Moodle URL [%s]: " "$default_wwwroot"
read -r wwwroot
wwwroot=${wwwroot:-$default_wwwroot}

set_env MOODLE_DB_NAME "$db_name"
set_env MOODLE_DB_USER "$db_user"
set_env MOODLE_DB_PASSWORD "$db_password"
set_env MOODLE_DB_ROOT_PASSWORD "$db_root_password"
set_env MOODLE_WWWROOT "$wwwroot"

if [ "$environment" = prod ]; then
    set_env MOODLE_REVERSEPROXY 1
    set_env MOODLE_SSLPROXY 1
    printf "Production image tag [5.3.1]: "
    read -r image_tag
    set_env MOODLE_IMAGE_TAG "${image_tag:-5.3.1}"
else
    set_env MOODLE_REVERSEPROXY 1
    set_env MOODLE_SSLPROXY 0
    set_env MOODLE_IMAGE_TAG 5.3.1
fi

echo "Starting $environment environment..."
if [ "$environment" = dev ]; then
    docker compose -f "$compose_file" up -d --build
else
    docker compose -f "$compose_file" pull
    docker compose -f "$compose_file" up -d
fi

printf "Moodle admin username [admin]: "
read -r adminuser
adminuser=${adminuser:-admin}

printf "Moodle admin email [admin@example.com]: "
read -r adminemail
adminemail=${adminemail:-admin@example.com}

prompt_secret "Moodle admin password"
adminpass=$PROMPT_SECRET
if [ -z "$adminpass" ]; then
    echo "Admin password cannot be empty." >&2
    exit 1
fi

echo "Installing Moodle database..."
docker compose -f "$compose_file" exec -T app php admin/cli/install_database.php \
    --adminuser="$adminuser" \
    --adminpass="$adminpass" \
    --adminemail="$adminemail" \
    --agree-license

echo "Moodle installation completed. Open $wwwroot"
