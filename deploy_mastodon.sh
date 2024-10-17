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
for cmd in docker docker-compose curl; do
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
echo ""
echo ""
# Gather necessary information
read -p "Enter your domain name (e.g., mastodon.example.com): " DOMAIN_NAME
read -p "Enter your server's public IP address: " IP_ADDRESS
echo ""
# Check for required environment variables
if [ -z "$POSTGRES_PASSWORD" ] || [ -z "$REDIS_PASSWORD" ] || [-Z "$LETS_ENCRYPT_EMAIL"]; then
    echo ""
    echo "❌ Error: POSTGRES_PASSWORD and REDIS_PASSWORD must be set as environment variables."
    echo "Please set these variables before running the script. For example:"
    echo "export POSTGRES_PASSWORD='your_secure_db_password'"
    echo "export REDIS_PASSWORD='your_secure_redis_password'"
    echo "export LETS_ENCRYPT_EMAIL='your_certificate_management_email'"
    echo "Then run this script again."
    echo ""
    exit 1
fi

echo ""
echo ""
echo ""

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
LETS_ENCRYPT_EMAIL=$LETS_ENCRYPT_EMAIL
# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379/0
# PostgreSQL
DB_HOST=db
DB_PORT=5432
DB_NAME=mastodon
DB_USER=mastodon
POSTGRES_DB=mastodon
POSTGRES_USER=mastodon
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
DB_PASS=$POSTGRES_PASSWORD





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
        email $LETS_ENCRYPT_EMAIL
}

$DOMAIN_NAME {
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

        handle /.well-known/acme-challenge/* {
                root * /opt/mastodon/public
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
                @5xx expression {http.error.status_code} >= 500 && {http.error.status_code} < 600
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
    environment:
      - POSTGRES_USER=mastodon
      - POSTGRES_PASSWORD=$POSTGRES_PASSWORD
      - POSTGRES_DB=mastodon     
    ports:
      - "5432:5432"
  redis:
    restart: always
    image: redis:7-alpine
    healthcheck:
      test: ['CMD', 'redis-cli', 'ping']
    volumes:
      - ./redis:/data
    environment:
      - REDIS_PASSWORD=$REDIS_PASSWORD
    command: ["redis-server", "--requirepass", "$REDIS_PASSWORD"]
    ports:
      - "6379:6379"
  web:
    image: tootsuite/mastodon:${MASTODON_VERSION}    
    restart: always
    user: '1001:1001'
    env_file: .env.production
    command: bundle exec puma -C config/puma.rb
    healthcheck:
      test: ['CMD-SHELL', 'wget -q --spider --proxy=off localhost:3000/health || exit 1']
    ports:
      - '127.0.0.1:3000:3000'
    depends_on:
      - db
      - redis
    volumes:
      - ./public/system:/opt/mastodon/public/system
    environment:
      - REDIS_PASSWORD=$REDIS_PASSWORD
      - REDIS_URL=redis://:$REDIS_PASSWORD@redis:6379/0
  streaming:
    image: tootsuite/mastodon:${MASTODON_VERSION}    
    restart: always
    user: '1001:1001'
    env_file: .env.production
    command: ["node", "streaming/index.js"]
    healthcheck:
      test: ['CMD-SHELL', 'wget -q --spider --proxy=off localhost:4000/api/v1/streaming/health || exit 1']
    volumes:
      - ./public/system:/opt/mastodon/public/system
    ports:
      - '127.0.0.1:4000:4000'
    depends_on:
      - db
      - redis
  sidekiq:
    image: tootsuite/mastodon:${MASTODON_VERSION}    
    restart: always
    user: '1001:1001'
    env_file: .env.production
    environment:
      - REDIS_PASSWORD=$REDIS_PASSWORD
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
echo ""
echo ""
echo ""
echo "Starting Docker containers..."
docker_compose_sudo up -d
if [ $? -ne 0 ]; then
    echo "❌ Failed to start Docker containers. Please check Docker installation and permissions."
    exit 1
fi

# Ensure the database is created and the user has the correct permissions
echo "Waiting for Docker services like PostgreSQL to start and be ready..."
  sleep 30

echo "Proxy server Caddy may take a few minutes to complete automatic SSL certificate provisioning"
echo "During this time, the Mastodon web interface may not be immediately accessible."

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
docker_compose_sudo run --rm web rails db:seed
docker_compose_sudo down
docker_compose_sudo up -d


# Create first default admin user
ADMIN_EMAIL=$LETS_ENCRYPT_EMAIL
ADMIN_USERNAME="superadmin"
ROLE="Admin"


echo ""
echo ""
echo ""
echo "We'll create an admin account for you while waiting for the SSL setup."
# Create the admin user without email confirmation
  echo "Creating admin user $ADMIN_USERNAME without email service..."
  echo "   Username: $ADMIN_USERNAME"
  echo "   Email: $ADMIN_EMAIL"
  sudo docker-compose exec web tootctl accounts create $ADMIN_USERNAME --email $ADMIN_EMAIL --confirmed

  echo "✅ Admin user created successfully."
  echo "⚠️ IMPORTANT: The password for this account will be displayed shortly. Make sure to save it securely!"
  sleep 5
  echo ""
  echo ""
  echo ""
  echo ""

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
echo ""
echo ""
echo ""
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
     ('https://relay.fedi.buzz/instance/qoto.org', NULL, NOW(), NOW(), 2);
 "

# Execute the SQL commands in the Mastodon PostgreSQL database
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$SQL_COMMANDS"

# Verify that the relays were added successfully
VERIFY_SQL="SELECT * FROM relays LIMIT 10;"
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$VERIFY_SQL"
echo "Relay services have been successfully added!"





echo ""
echo ""
echo ""
echo "Let's have your instance gets federated relationships with other domains in the Fediverse"
echo "We first follow some popular users from those domains!"
# Mastodon instance URL and admin credentials
MASTODON_INSTANCE=$DOMAIN_NAME
ADMIN_USERNAME=$LETS_ENCRYPT_EMAIL # Replace with your actual admin username/email
ADMIN_PASSWORD="4e3ed713a38f12021f79a05a5ba38148"
CLIENT_NAME="FollowUsersApp"
REDIRECT_URI="urn:ietf:wg:oauth:2.0:oob"

# Array of user handles to follow
users=(
  "mastodon@mastodon.social"  # Domain: mastodon.social
  "georgetakei@universeodon.com"  # Domain: universeodon.com
  "rbreich@masto.ai"  # Domain: masto.ai
  "FediTips@social.growyourown.services"  # Domain: social.growyourown.services
  "_kokt@simkey.net"  # Domain: simkey.net
  "ProPublica@newsie.social"  # Domain: newsie.social
  "APoD@botsin.space"  # Domain: botsin.space
  "stephenfry@mastodonapp.uk"  # Domain: mastodonapp.uk
  "gretathunberg@mastodon.nu"  # Domain: mastodon.nu
  "EUCommission@ec.social-network.europa.eu"  # Domain: ec.social-network.europa.eu
  "molly0xfff@hachyderm.io"  # Domain: hachyderm.io
  "auschwitzmuseum@mastodon.world"  # Domain: mastodon.world
  "ralphruthe@troet.cafe"  # Domain: troet.cafe
  "SwiftOnSecurity@infosec.exchange"  # Domain: infosec.exchange
  "afelia@chaos.social"  # Domain: chaos.social
  "MarcElias@mas.to"  # Domain: mas.to
  "primalmotion@antisocial.ly"  # Domain: antisocial.ly
  "erictopol@mstdn.social"  # Domain: mstdn.social
  "pluralistic@mamot.fr"  # Domain: mamot.fr
  "internetarchive@mastodon.archive.org"  # Domain: mastodon.archive.org
  "tagesschau@ard.social"  # Domain: ard.social
  "ct_bergstrom@fediscience.org"  # Domain: fediscience.org
  "omakano@omaka.nr1a.inc"  # Domain: omaka.nr1a.inc
  "evacide@hachyderm.io"  # Domain: hachyderm.io
  "kuketzblog@social.tchncs.de"  # Domain: social.tchncs.de
  "viticci@macstories.net"  # Domain: macstories.net
  "freemo@qoto.org"  # Domain: qoto.org
  "timnitGebru@dair-community.social"  # Domain: dair-community.social
  "ralf@rottmann.social"  # Domain: rottmann.social
  "GreatDismal@mastodon.social"  # Domain: mastodon.social
  "techconnectify@mas.to"  # Domain: mas.to
  "aral@mastodon.ar.al"  # Domain: mastodon.ar.al
  "wonderofscience@mastodon.social"  # Domain: mastodon.social
  "godpod@universeodon.com"  # Domain: universeodon.com
  "neilhimself@mastodon.social"  # Domain: mastodon.social
  "scalzi@mastodon.social"  # Domain: mastodon.social
  "tazgetroete@mastodon.social"  # Domain: mastodon.social
  "Sheril@mastodon.social"  # Domain: mastodon.social
  "signalapp@mastodon.world"  # Domain: mastodon.world
  "mattblaze@federate.social"  # Domain: federate.social
  "Mozilla@mozilla.social"  # Domain: mozilla.social
  "foone@digipres.club"  # Domain: digipres.club
  "LaQuadrature@mamot.fr"  # Domain: mamot.fr
  "tapbots@tapbots.social"  # Domain: tapbots.social
  "trumpet@mas.to"  # Domain: mas.to
  "abandonedamerica@mastodon.social"  # Domain: mastodon.social
  "ralphruthe@troet.cafe"  # Domain: troet.cafe
  "bfdi@social.bund.de"  # Domain: social.bund.de
  "ralph@rottmann.social"  # Domain: rottmann.social
  "socraticethics@mastodon.online"  # Domain: mastodon.online
  "micahflee@infosec.exchange"  # Domain: infosec.exchange
  "DerPostillon@mastodon.social"  # Domain: mastodon.social
  "mrloverstein@mastodon.social"  # Domain: mastodon.social
  "eff@mastodon.social"  # Domain: mastodon.social
  "zdfmagazin@edi.social"  # Domain: edi.social
  "elonjet@mastodon.social"  # Domain: mastodon.social
  "gossithedog@cyberplace.social"  # Domain: cyberplace.social
  "torproject@mastodon.social"  # Domain: mastodon.social
  "Jennifer@hachyderm.io"  # Domain: hachyderm.io
  "AbandonedAmerica@mastodon.social"  # Domain: mastodon.social
  "arstechnica@mastodon.social"  # Domain: mastodon.social
  "MattBinder@mastodon.social"  # Domain: mastodon.social
  "taylorlorenz@mastodon.social"  # Domain: mastodon.social
  "JeffJarvis@mastodon.social"  # Domain: mastodon.social
  "davidallengreen@mastodon.green"  # Domain: mastodon.green
  "Trumpet@mas.to"  # Domain: mas.to
  "katiekatie@mastodon.social"  # Domain: mastodon.social
  "dangillmor@mastodon.social"  # Domain: mastodon.social
  "LinusTorvalds@social.kernel.org"  # Domain: social.kernel.org
  "jamesgunn@c.im"  # Domain: c.im
  "MarcElias@mas.to"  # Domain: mas.to
  "God@universeodon.com"  # Domain: universeodon.com
  "ElonMuskJet@mastodon.social"  # Domain: mastodon.social
  "chiefTwit@twit.social"  # Domain: twit.social
)

# Ensure jq is installed
if ! command -v jq &> /dev/null; then
    echo "jq is required but not installed. Please install jq."
    exit 1
fi

# Step 1: Register a new application (OAuth client)
echo "Registering a new application..."
RESPONSE=$(curl -s -X POST "$MASTODON_INSTANCE/api/v1/apps" \
    -F "client_name=$CLIENT_NAME" \
    -F "redirect_uris=$REDIRECT_URI" \
    -F "scopes=read write follow admin:read" \
    -F "website=$MASTODON_INSTANCE")

# Extract client_id and client_secret
CLIENT_ID=$(echo "$RESPONSE" | jq -r '.client_id')
CLIENT_SECRET=$(echo "$RESPONSE" | jq -r '.client_secret')

if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Failed to register the application. Response: $RESPONSE"
    exit 1
fi

echo "Application registered successfully with client_id: $CLIENT_ID"

# Step 2: Get an access token using the client credentials
echo "Requesting access token..."
TOKEN_RESPONSE=$(curl -s -X POST "$MASTODON_INSTANCE/oauth/token" \
    -F "client_id=$CLIENT_ID" \
    -F "client_secret=$CLIENT_SECRET" \
    -F "grant_type=password" \
    -F "username=$ADMIN_USERNAME" \
    -F "password=$ADMIN_PASSWORD" \
    -F "scope=read write follow admin:read")

ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')

if [ -z "$ACCESS_TOKEN" ] || [ "$ACCESS_TOKEN" == "null" ]; then
    echo "Failed to get access token. Response: $TOKEN_RESPONSE"
    exit 1
fi

echo "Access token received: $ACCESS_TOKEN"

# Function to follow a user based on their handle using federated search
follow_user() {
    local user_handle=$1

    # Step 1: Search for the user in the federated network
    echo "Searching for user: $user_handle..."
    search_result=$(curl -s --header "Authorization: Bearer $ACCESS_TOKEN" \
        "$MASTODON_INSTANCE/api/v2/search?q=$user_handle&resolve=true")

    # Step 2: Extract the user ID from the search result
    user_id=$(echo "$search_result" | jq -r '.accounts[0].id')

    if [[ "$user_id" == "null" || -z "$user_id" ]]; then
        echo "Failed to find user with handle $user_handle. Skipping..."
        return
    fi

    echo "Found user: $user_handle with ID: $user_id"

    # Step 3: Follow the user using the user ID
    follow_response=$(curl -s --header "Authorization: Bearer $ACCESS_TOKEN" \
        -X POST "$MASTODON_INSTANCE/api/v1/accounts/$user_id/follow")

    if [[ "$follow_response" == *"error"* ]]; then
        echo "Failed to follow $user_handle. Response: $follow_response"
    else
        echo "Successfully followed $user_handle!"
    fi
}

# Loop through the users and follow each one
for user in "${users[@]}"; do
    follow_user "$user"
    sleep 5  # Optional delay to avoid rate limiting
done


echo "All users have been processed!"
echo "Federated connections are being established with the specified users.
You should start seeing updates from them in your instance."
echo""
echo""
echo""







# Final messages
echo ""
echo ""
echo ""
echo "🎉 Setup Complete! 🎉"
echo "✅ Mastodon deployment completed successfully!"
echo "🌐 Your Mastodon instance will be available at https://$DOMAIN_NAME"
echo "🕒 Waiting for Caddy to finish SSL setup (this may take up to 10 minutes)..."
echo "Then you can restart your Docker services to run your Mastodon Instance"
echo "If you encounter any issues accessing the site, please check the Caddy logs:
   docker-compose logs caddy"
echo ""
echo ""
echo ""
echo "👤 An admin user has been created with the following credentials:"
echo "🔑 Admin Account Details:"
echo "   Username: $ADMIN_USERNAME"
echo "   Email: $ADMIN_EMAIL"
echo "   Password was generated earlier. Please go back and check."
echo "⚠️ Please log in and change the generated admin password!"
echo ""
echo ""
echo ""

echo "🔌 When your server is ready to use, please use '$IP_ADDRESS:9092' as the Mastodon endpoint to complete the RSS3 Node deployment with a Mastodon worker at https://explorer.rss3.io/"
echo "📡 Your instance will receive messages from major Mastodon instances due to the configured relay server subscriptions."
echo "📚 For more information on managing your Mastodon instance, visit: https://docs.joinmastodon.org/"

