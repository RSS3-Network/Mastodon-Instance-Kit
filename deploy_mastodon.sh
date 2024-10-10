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

# Function to check DNS propagation
# This ensures that the domain name is correctly pointing to the server's IP address
check_dns() {
    local domain="$1"
    local ip="$2"
    local dns_ip=$(dig +short $domain)

    if [ "$dns_ip" = "$ip" ]; then
        return 0
    else
        return 1
    fi
}

# Main script starts here
echo "🚀 Welcome to the Mastodon Deployment Script"
echo "This script will guide you through setting up a Mastodon instance."

# Gather necessary information
read -p "Enter your domain name (e.g., mastodon.example.com): " DOMAIN_NAME
read -p "Enter your server's public IP address: " IP_ADDRESS

# Check for required environment variables
if [ -z "$DB_PASSWORD" ] || [ -z "$REDIS_PASSWORD" ]; then
    echo "❌ Error: DB_PASSWORD and REDIS_PASSWORD must be set as environment variables."
    echo "Please set these variables before running the script. For example:"
    echo "export DB_PASSWORD='your_secure_db_password'"
    echo "export REDIS_PASSWORD='your_secure_redis_password'"
    echo "Then run this script again."
    exit 1
fi

# Check DNS setup
echo "Checking DNS setup..."
if check_dns "$DOMAIN_NAME" "$IP_ADDRESS"; then
    echo "✅ DNS is correctly set up."
else
    echo "❌ DNS is not set up correctly. Please ensure your domain points to your server's IP address."
    echo "You can check DNS propagation at https://www.whatsmydns.net/#A/$DOMAIN_NAME"
    read -p "Have you set up the DNS correctly now? (yes/no): " dns_setup
    if [[ $dns_setup != "yes" ]]; then
        echo "Please set up DNS and run this script again."
        exit 1
    fi
fi

# Set up SSL/TLS
echo "Setting up SSL/TLS certificate..."
sudo certbot certonly --standalone -d $DOMAIN_NAME

if [ $? -ne 0 ]; then
    echo "❌ Failed to obtain SSL/TLS certificate. Please ensure your domain is correctly set up and try again."
    exit 1
fi

# Clone Mastodon repository
echo "Cloning Mastodon repository..."
git clone https://github.com/mastodon/mastodon.git
cd mastodon
git checkout $MASTODON_VERSION

# Create necessary directories
# These directories are required for Mastodon's file storage and operation
mkdir -p public/system
mkdir -p public/assets
mkdir -p public/packs
mkdir -p tmp/pids
mkdir -p tmp/sockets

# Create .env.production file
# This file contains essential configuration for your Mastodon instance
cat << EOF > .env.production
# Federation
LOCAL_DOMAIN=$DOMAIN_NAME
SINGLE_USER_MODE=true
ENABLE_REGISTRATIONS=false

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=$REDIS_PASSWORD

# PostgreSQL
DB_HOST=db
DB_PORT=5432
DB_NAME=mastodon
DB_USER=mastodon
DB_PASS=$DB_PASSWORD

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

# IP and session retention
IP_RETENTION_PERIOD=31556952
SESSION_RETENTION_PERIOD=31556952
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
      - POSTGRES_PASSWORD=$DB_PASSWORD  # Postgres password
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
    image: wurstmeister/zookeeper
    ports:
      - "2181:2181"
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
  kafka:
    image: wurstmeister/kafka
    ports:
      - "9092:9092"
    env_file:
      - .env.production
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - zookeeper
  kafka_sender:
    image: ghcr.io/frankli123/mastodon-plugin-image:latest
    restart: always
    ports:
      - '3001:3001'
    depends_on:
      - kafka
    env_file:
      - .env.production
EOF




# Set up Nginx
echo "Setting up Nginx..."
sudo tee /etc/nginx/sites-available/mastodon << EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN_NAME;
    location /.well-known/acme-challenge/ {
        root /var/www/mastodon/live/public;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN_NAME;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384';
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN_NAME/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN_NAME/privkey.pem;

    keepalive_timeout    70;
    sendfile             on;
    client_max_body_size 80m;

    root /var/www/mastodon/live/public;

    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/javascript application/x-javascript text/xml application/xml application/xml+rss text/javascript;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Robots-Tag none;
    add_header X-Download-Options noopen;
    add_header X-Permitted-Cross-Domain-Policies none;

    location / {
        try_files \$uri @proxy;
    }

    location @proxy {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:3000;
        proxy_buffering off;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location /api/v1/streaming {
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_pass http://127.0.0.1:4000;
        proxy_buffering off;
        proxy_redirect off;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
    }

    location /inbox {
        proxy_pass http://127.0.0.1:3001;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$host;
    }
}
EOF



sudo ln -s /etc/nginx/sites-available/mastodon /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl start nginx



# Enable BuildKit for this build
echo "Enabling BuildKit for this build..."
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1

# Enable BuildKit in Docker daemon
echo "Enabling BuildKit in Docker daemon..."
sudo bash -c ' cat <<EOF > /etc/docker/daemon.json
{
  "features": {
    "buildkit": true
  }
}
EOF'


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
        CREATE ROLE postgres WITH SUPERUSER CREATEDB CREATEROLE LOGIN PASSWORD '$DB_PASSWORD';
    END IF;

    -- Ensure 'mastodon' role exists (it should be already created by docker-compose)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'mastodon') THEN
        CREATE ROLE mastodon WITH LOGIN PASSWORD '$DB_PASSWORD';
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

# Precompile assets
echo "Precompiling assets..."
docker_compose_sudo run --rm web rails assets:precompile

# Create first admin user
ADMIN_EMAIL="superadmin@$DOMAIN_NAME"  # Use a valid-formatted but non-functional email
ADMIN_USERNAME="superadmin"
ROLE="Admin"

# Before creating the admin user, check if it already exists
ADMIN_EXISTS=$(sudo docker-compose exec web tootctl accounts show $ADMIN_USERNAME 2>&1)
if [[ "$ADMIN_EXISTS" != *"No user with such username"* ]]; then
    echo "Admin user $ADMIN_USERNAME already exists. Skipping creation."
else
  # Create the admin user without email confirmation
  echo "Creating admin user $ADMIN_USERNAME without email service..."
  sudo docker-compose exec web tootctl accounts create $ADMIN_USERNAME --email $ADMIN_EMAIL --confirmed

  echo "Remember to keep the generated admin password displayed here to log in for the first time."
  # Check if the user creation succeeded
  USER_EXISTS=$(sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --confirm --approve 2>&1)

  if [[ "$USER_EXISTS" == *"No user with such username"* ]]; then
      echo "Error: Failed to create the admin user $ADMIN_USERNAME. Please check the logs for details."
      exit 1
  else
      echo "Admin user $ADMIN_USERNAME created successfully."

      # Assign the Admin role to the user
      echo "Assigning the $ROLE role to $ADMIN_USERNAME..."
      sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --role $ROLE

      # Disable 2FA and skip sign-in token (since there's no email service)
      echo "Disabling 2FA and skipping sign-in token for $ADMIN_USERNAME..."
      sudo docker-compose exec web tootctl accounts modify $ADMIN_USERNAME --disable-2fa

      echo "Admin user $ADMIN_USERNAME has been successfully created and assigned the $ROLE role!"

  fi
fi

# Create necessary directories
sudo mkdir -p /opt/mastodon/public/system/cache

# Set ownership (adjust UID:GID if necessary)
sudo chown -R 991:991 /opt/mastodon/public/system

# Set permissions
sudo chmod -R 755 /opt/mastodon/public/system
sudo chmod -R 775 /opt/mastodon/public/system/cache

# Ensure the changes were applied successfully
if [ $? -ne 0 ]; then
    echo "❌ Failed to set up directories and permissions. Please check your permissions and try again."
    exit 1
fi


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
 ON CONFLICT (inbox_url) DO NOTHING;
"

# Execute the SQL commands in the Mastodon PostgreSQL database
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$SQL_COMMANDS"

# Verify that the relays were added successfully
VERIFY_SQL="SELECT * FROM relays LIMIT 10;"
sudo docker-compose exec db psql -U mastodon -d mastodon -c "$VERIFY_SQL"

echo "Relay services have been successfully added!"

# Final messages
echo "✅ Mastodon deployment completed successfully!"
echo "🌐 Your Mastodon instance is now available at https://$DOMAIN_NAME"
echo "👤 An admin user has been created with the following credentials:"
echo "   Username: $ADMIN_USERNAME"
echo "   Email: $ADMIN_EMAIL"
echo "⚠️ Please log in and change the generated admin password!"
echo "🔌 Please use '$IP_ADDRESS:9092' as the Mastodon endpoint to complete the RSS3 Node deployment with a Mastodon worker at https://explorer.rss3.io/"
echo "📡 Your instance will receive messages from major Mastodon instances due to the configured relay server subscriptions."
echo "📚 For more information on managing your Mastodon instance, visit: https://docs.joinmastodon.org/"