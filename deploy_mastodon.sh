#!/bin/bash

# Mastodon Deployment Script
MASTODON_VERSION="v4.2.10"

# Function to run docker-compose commands with sudo
docker_compose_sudo() {
    sudo docker-compose "$@"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required tools
for cmd in docker docker-compose curl certbot; do
    if ! command_exists $cmd; then
        echo "❌ $cmd is not installed. Please install it and run this script again."
        exit 1
    fi
done

# Function to generate a random string
generate_random_string() {
    openssl rand -base64 32 | tr -d /=+ | cut -c -"$1"
}

# Main script starts here
echo "🚀 Welcome to the Mastodon Deployment Script"
echo "This script will guide you through setting up a Mastodon instance."
echo ""
# Gather necessary information
read -p "Enter your domain name (e.g., mastodon.example.com): " DOMAIN_NAME
read -p "Enter your server's public IP address: " IP_ADDRESS
echo ""
# Check for required environment variables
if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$REDIS_PASSWORD" ]; then
    echo ""
    echo "❌ Error: POSTGRES_PASSWORD and REDIS_PASSWORD must be set as environment variables."
    echo "Please set these variables before running the script. For example:"
    echo "export POSTGRES_PASSWORD='your_secure_db_password'"
    echo "export REDIS_PASSWORD='your_secure_redis_password'"
    echo "Then run this script again."
    echo ""
    exit 1
fi

# Clone Mastodon repository
echo "Cloning Mastodon repository..."
git clone https://github.com/mastodon/mastodon.git
cd mastodon
git checkout $MASTODON_VERSION

# Create necessary directories
mkdir -p public/system
mkdir -p public/assets
mkdir -p public/packs
mkdir -p tmp/pids
mkdir -p tmp/sockets

# Create .env.production file
cat << EOF > .env.production
# Federation
LOCAL_DOMAIN=$DOMAIN_NAME
SINGLE_USER_MODE=true
ENABLE_REGISTRATIONS=false

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_URL=redis://:${$REDIS_PASSWORD}@redis:6379/0
# PostgreSQL
DB_HOST=db
DB_PORT=5432
POSTGRES_DB=mastodon
POSTGRES_USER=mastodon
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Secrets (generated automatically)
SECRET_KEY_BASE=$(generate_random_string 128)
OTP_SECRET=$(generate_random_string 128)

# VAPID keys (generated automatically)
VAPID_PRIVATE_KEY=$(openssl ecparam -name prime256v1 -genkey -noout -out /dev/null 2>&1 | openssl ec -in /dev/stdin -outform DER 2>/dev/null | tail -c +8 | head -c 32 | base64)
VAPID_PUBLIC_KEY=$(echo -n "$VAPID_PRIVATE_KEY" | openssl ec -in /dev/stdin -inform DER -pubout -outform DER 2>/dev/null | tail -c 65 | base64)


# Kafka settings
KAFKA_ADVERTISED_HOST=$IP_ADDRESS
KAFKA_BROKER_ID=1
KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181
KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://${IP_ADDRESS}:9092
KAFKA_BROKER=kafka:9092
KAFKA_TOPIC=activitypub_events

ZOOKEEPER_CLIENT_PORT=2181
ZOOKEEPER_TICK_TIME=2000
ZOO_ENABLE_AUTH=true


# IP and session retention
IP_RETENTION_PERIOD=31556952
SESSION_RETENTION_PERIOD=31556952
EOF






# Create Caddyfile file with ACME support
cat << EOF > Caddyfile
# file: 'Caddyfile'

{
        email {$LETS_ENCRYPT_EMAIL}
}

{$LOCAL_DOMAIN} {
        log {
                # format single_field common_log
                output file /logs/access.log
        }

        root * /opt/mastodon/public

        encode gzip

        @static file

        handle @static {
                file_server
        }

        handle /api/v1/streaming* {
                reverse_proxy mastodon-streaming-1:4000
        }

        handle {
                reverse_proxy mastodon-web-1:3000
        }

        header {
                Strict-Transport-Security "max-age=31536000;"
        }

        handle /inbox* {
                reverse_proxy mastodon-kafka_sender-1:3001
        }

        header /sw.js  Cache-Control "public, max-age=0";
        header /emoji* Cache-Control "public, max-age=31536000, immutable"
        header /packs* Cache-Control "public, max-age=31536000, immutable"
        header /system/accounts/avatars* Cache-Control "public, max-age=31536000, immutable"
        header /system/media_attachments/files* Cache-Control "public, max-age=31536000, immutable"

        handle_errors {
                @5xx expression `{http.error.status_code} >= 500 && {http.error.status_code} < 600`
                rewrite @5xx /500.html
                file_server
        }
}
EOF

# Create docker-compose.yml file
cat << EOF > docker-compose.yml
version: '3'
services:
  db:
    restart: always
    image: postgres:14-alpine
    shm_size: 256mb
    healthcheck:
      test: ['CMD', 'pg_isready', '-U', 'postgres']
    volumes:
      - ./postgres14:/var/lib/postgresql/data
    env_file:
      - .env.production
    ports:
      - "5432:5432"
  redis:
    restart: always
    image: redis:7-alpine
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
    volumes:
      - ./redis:/data
    command: ["redis-server", "--requirepass", "123456"]
    ports:
      - "6379:6379"
    env_file:
      - .env.production
  web:
    image: tootsuite/mastodon:v4.2.10
    restart: always
    user: '1001:1001'
    env_file:
      - .env.production
    command: bundle exec puma -C config/puma.rb
    healthcheck:
      test: ['CMD-SHELL', 'wget -q --spider --proxy=off localhost:3000/health || exit 1']
    ports:
      - '3000:3000'
    depends_on:
      - db
      - redis
    volumes:
      - ./public/system:/opt/mastodon/public/system
    env_file:
      - .env.production
  streaming:
    image: tootsuite/mastodon:v4.2.10
    restart: always
    user: '1001:1001'
    env_file:
      - .env.production
    command: ["node", "streaming/index.js"]
    healthcheck:
      test: ['CMD-SHELL', 'wget -q --spider --proxy=off localhost:4000/api/v1/streaming/health || exit 1']
    volumes:
      - ./public/system:/opt/mastodon/public/system
    ports:
      - '4000:4000'
    depends_on:
      - db
      - redis
  sidekiq:
    image: tootsuite/mastodon:v4.2.10
    restart: always
    user: '1001:1001'
    env_file:
      - .env.production
    command: bundle exec sidekiq
    depends_on:
      - db
      - redis
    volumes:
      - ./public/system:/opt/mastodon/public/system
    healthcheck:
      test: ['CMD-SHELL', "ps aux | grep '[s]idekiq\ 6' || false"]
  zookeeper:
    image: bitnami/zookeeper:latest
    ports:
      - "2181:2181"
    env_file:
      - .env.production

  kafka:
    image: bitnami/kafka:latest
    ports:
      - "9092:9092"
    env_file:
      - .env.production
    depends_on:
      - zookeeper

  kafka_sender:
    image: ghcr.io/rss3-network/mastodon-instance-kit:main-04b2b41a70753d3c4a1dcde70de4ddc7abf5cd79
    restart: always
    ports:
      - '3001:3001'
    depends_on:
      - kafka
    env_file:
      - .env.production
  caddy:
    image: caddy:2-alpine
    container_name: caddy
    restart: always
    ports:
      - 80:80
      - 443:443
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./caddy/config:/config
      - ./caddy/data:/data
    env_file:
      - .env.production
EOF

# Create necessary directories
sudo mkdir -p /opt/mastodon/public/system/cache
sudo mkdir -p /opt/mastodon/tmp

# Set ownership (adjust UID:GID if necessary)
sudo chown -R 1001:1001 /opt/mastodon/public/system/cache
sudo chown -R 1001:1001 ./public/system
sudo chown -R 1001:1001 /opt/mastodon/public
sudo chown -R 1001:1001 /opt/mastodon/public/system
sudo chown -R 1001:1001 /opt/mastodon/tmp

# Set permissions
sudo chmod -R 755 /opt/mastodon/public/system
sudo chmod -R 775 /opt/mastodon/public/system/cache
sudo chmod -R 775 /opt/mastodon/tmp


# Ensure the changes were applied successfully
if [ $? -ne 0 ]; then
    echo "❌ Failed to set up directories and permissions. Please check your permissions and try again."
    exit 1
fi

# Start Docker containers
echo "Starting Docker containers..."
docker_compose_sudo up -d
if [ $? -ne 0 ]; then
    echo "❌ Failed to start Docker containers. Please check Docker installation and permissions."
    exit 1
fi


# Ensure the database is created and the user has the correct permissions
echo "Waiting for PostgreSQL to start and be ready..."
  sleep 15


# Create the 'postgres' superuser role and ensure the 'mastodon' user exists, grant necessary privileges
sudo docker exec -it $(sudo docker-compose ps -q db) psql -U mastodon -d mastodon -c "
DO \$\$
BEGIN
    -- Create 'postgres' role if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'postgres') THEN
        CREATE ROLE postgres WITH SUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '$POSTGRES_PASSWORD';
    END IF;

    -- Ensure 'mastodon' role exists (it should be already created by docker-compose)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mastodon') THEN
        CREATE ROLE mastodon WITH LOGIN PASSWORD '$POSTGRES_PASSWORD';
    END IF;

    -- Ensure the 'mastodon' database exists
    IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'mastodon') THEN
        CREATE DATABASE mastodon OWNER mastodon;
    END IF;

    -- Grant all privileges on the database 'mastodon' to the 'mastodon' user
    GRANT ALL PRIVILEGES ON DATABASE mastodon TO mastodon;
END
\$\$;
"


# Run database migrations
echo "Running database migrations..."
docker_compose_sudo run --rm web rails db:migrate

## Precompile assets
echo "Precompiling assets...(This step could take several minutes to complete)"
# docker_compose_sudo run --rm web rails assets:precompile

# Create first default admin user
ADMIN_EMAIL="superadmin@$DOMAIN_NAME"
ADMIN_USERNAME="superadmin"
ROLE="Admin"

# Before creating the admin user, check if it already exists
# Create the admin user without email confirmation
  echo "Creating admin user $ADMIN_USERNAME without email service..."
  sudo docker-compose exec web tootctl accounts create $ADMIN_USERNAME --email $ADMIN_EMAIL --confirmed

  echo "Remember to keep the generated admin password displayed here to log in for the first time."
  sleep 5

  # Check if the user creation succeeded
  #USER_EXISTS=$(sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --confirm --approve 2>&1)

  echo "Admin user $ADMIN_USERNAME created successfully."

  # Assign the Admin role to the user
  echo "Assigning the $ROLE role to $ADMIN_USERNAME..."
  sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --role $ROLE

  # Disable 2FA and skip sign-in token (since there's no email service)
  echo "Disabling 2FA and skipping sign-in token for $ADMIN_USERNAME..."
  sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --disable-2fa

  echo "Admin user $ADMIN_USERNAME has been successfully created and assigned the $ROLE role!"


## Approve the admin account
echo "Approving admin account..."
sudo docker-compose exec -T web bin/tootctl accounts approve $ADMIN_USERNAME

# Add relay services to the mastodon instance for receiving mastodon data
echo "Adding relay services directly to the database..."
# SQL command to add relay services
SQL_COMMANDS="
INSERT INTO relays (inbox_url, follow_activity_id, created_at, updated_at, state)
VALUES
  ('https://relay.fedi.buzz/instance/fediscience.org', NULL, NOW(), NOW(), 2),
  ('https://relay.fedi.buzz/instance/mas.to', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/indieweb.social', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/wetdry.world', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/good.news', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/mastodon.online', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/mastodon.social', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/universeodon.com', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/tapbots.social', NULL, NOW(), NOW(), 2),
  ('https://relay.fedi.buzz/instance/infosec.exchange', NULL, NOW(), NOW(), 2),
   ('https://relay.fedi.buzz/instance/mediapart.social', NULL, NOW(), NOW(), 2),
   ('https://relay.fedi.buzz/instance/journa.host', NULL, NOW(), NOW(), 2),
   ('https://relay.fedi.buzz/instance/ard.social', NULL, NOW(), NOW(), 2),
    ('https://relay.fedi.buzz/instance/w3c.social', NULL, NOW(), NOW(), 2),
    ('https://relay.fedi.buzz/instance/edi.social', NULL, NOW(), NOW(), 2),
    ('https://relay.fedi.buzz/instance/mstdn.social', NULL, NOW(), NOW(), 2),
     ('https://relay.fedi.buzz/instance/twit.social', NULL, NOW(), NOW(), 2),
     ('https://relay.fedi.buzz/instance/qoto.org', NULL, NOW(), NOW(), 2),
   ('https://relay.fedi.buzz/instance/mastodon.xyz', NULL, NOW(), NOW(), 2),
 ('https://relay.fedi.buzz/instance/masto.ai', NULL, NOW(), NOW(), 2);
 "

# Execute the SQL commands in the Mastodon PostgreSQL database
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$SQL_COMMANDS"

# Verify that the relays were added successfully
VERIFY_SQL="SELECT * FROM relays LIMIT 10;"
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$VERIFY_SQL"
echo "Relay services have been successfully added!"


# Final messages
echo ""
echo "✅ Mastodon deployment completed successfully!"
echo "🌐 Your Mastodon instance is now available at https://$DOMAIN_NAME"
echo "👤 An admin user has been created with the following credentials:"
echo "   Username: $ADMIN_USERNAME"
echo "   Email: $ADMIN_EMAIL"
echo "⚠️ Please log in and change the generated admin password!"
echo ""
echo "🔌 Please use '$IP_ADDRESS:9092' as the Mastodon endpoint to complete the RSS3 Node deployment with a Mastodon worker at https://explorer.rss3.io/"
echo "📡 Your instance will receive messages from major Mastodon instances due to the configured relay server subscriptions."
echo "📚 For more information on managing your Mastodon instance, visit: https://docs.joinmastodon.org/"

