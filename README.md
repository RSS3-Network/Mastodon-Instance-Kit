# Mastodon Plugin for RSS3 Node Integration

This repository provides tools to set up a Mastodon instance for integration with RSS3 nodes. 

The primary goal is to help you obtain a valid Mastodon endpoint (`mastodon_instance_external_ip:port`) for node deployment with a Mastodon worker at the [RSS3 Explorer](https://explorer.rss3.io/).

## Two Options for Mastodon Setup

1. **Automated Mastodon Deployment**: Quick setup of a new Mastodon instance.
2. **Manual Integration**: Modify an existing Mastodon instance.

## Option 1: Automated Mastodon Deployment

For users who want to quickly set up a new Mastodon instance with RSS3 node integration.

### Prerequisites

- A server with a `public IP` address
- A `domain name` pointing to your server's IP (Ensure DNS settings are correctly configured)
- `Docker` and `Docker Compose` installed
- `git`, `curl`, and `certbot` installed

### Deployment Steps

1. Clone this repository:

   ```sh
   git clone https://github.com/your-username/mastodon-plugin.git
   ```

2. Set the required environment variables:

   ```sh
   export DB_PASSWORD='your_secure_db_password'
   export REDIS_PASSWORD='your_secure_redis_password'
   ```

3. Run the deployment script:

   ```sh
   chmod +x deploy_mastodon.sh
   ./deploy_mastodon.sh
   ```

4. Follow the prompts to enter your `domain name` and server's `public IP` address.

5. After successful deployment, you'll receive:
   - The URL of your Mastodon instance
   - Admin account credentials

### Post-Deployment
- Log in and change the admin password immediately.
- Review and adjust the instance settings as needed.
 
## Option 2: Manual Integration with Existing Mastodon Instance

For users who already have a Mastodon instance and want to integrate it with RSS3 node.

### 1. Mastodon Instance Configuration

#### 1.1 Update docker-compose.yaml

Add the following services to your `docker-compose.yaml`:

```yaml
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
```

#### 1.2 Configure Kafka

Add the following environment variables to your `.env.production` file:

```sh
# Kafka settings
KAFKA_ADVERTISED_HOST=your_mastodon_instance_ip
KAFKA_BROKER_ID=1
KAFKA_TOPIC=activitypub_events
KAFKA_ZOOKEEPER_CONNECT=zookeeper:2181
KAFKA_LISTENERS=PLAINTEXT://0.0.0.0:9092
KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://${KAFKA_ADVERTISED_HOST}:9092
KAFKA_BROKER=kafka:9092
```

Replace `your_mastodon_instance_ip` with your actual Mastodon instance IP.

#### 1.3 Start New Services

Run the following command to start the new services:

```bash
docker-compose up kafka zookeeper kafka_sender
```

Verify Kafka broker logs:

```bash
docker-compose logs kafka
```

#### 1.4 Update Nginx Configuration

Add the following to your `/etc/nginx/sites-enabled/mastodon.conf` file:

```nginx
server {
  # ... (existing configuration)

  location /inbox {
    proxy_pass http://127.0.0.1:3001;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header Host $host;
  }
}
```

Restart Nginx:

```bash
sudo systemctl restart nginx
```


## Finished

Congratulations! You have successfully set up your Mastodon instance, and now have a valid Mastodon endpoint for your RSS3 node.

Your Mastodon endpoint is: `mastodon_instance_external_ip:9092`

### Next Steps: RSS3 Node Deployment

Now that you have your Mastodon endpoint, you can proceed with the RSS3 node deployment:

1. Return to the [RSS3 Explorer](https://explorer.rss3.io/).
2. If you haven't started the node deployment process, begin it now.
3. During the configuration step, you'll be asked to set up workers for your node.
4. Choose to add a Mastodon worker.
5. When prompted for a Mastodon endpoint, enter your endpoint: `your_external_ip:9092`.
6. Complete the remaining steps as guided by the RSS3 Explorer.

Note: If you've already deployed your node without the Mastodon worker, you can add it later through the node management interface on the RSS3 Explorer.

### Important Notes

- Ensure your firewall allows incoming connections on port 9092.
- If you encounter any issues during the RSS3 node deployment, double-check your Mastodon endpoint and review the integration steps.

## Support and Further Information

- For Mastodon-related questions, refer to the [official Mastodon documentation](https://docs.joinmastodon.org/).
- For RSS3-specific inquiries, check the [RSS3 documentation](https://docs.rss3.io/).
- If you encounter any issues with this integration, please open an issue in this repository.

