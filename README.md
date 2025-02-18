# Mastodon Instance Kit for RSS3 Node Integration

This repository provides tools to help you obtain a `valid Mastodon endpoint` for node deployment with a Mastodon worker at the [RSS3 Explorer](https://explorer.rss3.io/).

## Two Options to Obtain Valid Mastodon Endpoints

1. **Automated Mastodon Instance Deployment**: Quick setup of a new Mastodon instance.
2. **Manual Mastodon Instance Modification**: Modify an existing Mastodon instance.




Both options will guide you through the initial setup. Once completed, you'll obtain a valid Mastodon endpoint necessary for the RSS3 node deployment with a Mastodon worker at the RSS3 explorer.




## Option 1: Automated Mastodon Instance Deployment

For users who want to quickly set up a new Mastodon instance with RSS3 node integration. It provides:
- A straightforward setup process for a ready-to-use Mastodon instance
- Pre-configured services, allowing your instance to receive messages from fediverse

This approach is ideal for those who want a simple solution that's operational right after deployment, with built-in connectivity to the wider Mastodon network.




### Prerequisites

- A server with a `public IP` address
- A `domain name` pointing to your server's IP
- Sufficient server hardware resources:
  - At least 2 CPU cores
  - Minimum 4GB RAM (8GB recommended)
  - At least 50GB of storage space (80GB recommended)
- Open ports: `80 (HTTP)`, `443 (HTTPS)`, `9092 (Kafka)`
  
### Deployment Steps
1. Configure domain's DNS settings:

Set up an A record for your domain (e.g., `mastodon.yourdomain.com`) pointing to your server's public IP address.


2. Clone this repository:

   ```sh
   git clone https://github.com/RSS3-Network/Mastodon-Instance-Kit.git
   cd Mastodon-Instance-Kit
   ```

3. Set the required environment variables:

   ```sh
   export POSTGRES_PASSWORD='your_secure_db_password'
   export REDIS_PASSWORD='your_secure_redis_password'
   export LETS_ENCRYPT_EMAIL='your_certificate_management_email'
   ```

4. Run the deployment script:

   ```sh
   chmod +x deploy_mastodon.sh
   ./deploy_mastodon.sh
   ```

5. Follow the prompts to enter any required information.

6. After successful deployment, you'll receive:
   - The URL of your Mastodon instance
   - Admin account credentials (admin username and password)

7. Wait for your instance to be ready

### Important Notes
- The SSL setup process may take up to to a few minutes. Please be patient and frequently check your domain status.
- The admin account is created automatically for your convenience, but it's crucial to change the password upon first login.
- Review and adjust the instance settings as needed.
- The deployment uses multiple Docker services. If you need to troubleshoot, you can check logs for specific services using:
  ```sh
  docker-compose logs [service_name]


### Q&A

- Rate Limit Error - Let's Encrypt is refusing to issue a new certificate because you've reached the limit for this domain
 ```sh
  rm -rf /data/caddy/certificates
  docker-compose restart caddy
 ```
## Option 2: Manual Mastodon Instance Modification

For users who already have a Mastodon instance and want to integrate it with RSS3 node.

### 1. Mastodon Instance Configuration

#### 1.1 Update docker-compose.yaml

Add the following services to your `docker-compose.yaml`:

```yaml
zookeeper:
  image: bitnami/zookeeper:latest
  ports:
    - "2181:2181"
  environment:
    ZOOKEEPER_CLIENT_PORT: 2181
    ZOOKEEPER_TICK_TIME: 2000
    ZOO_ENABLE_AUTH: true

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

#### 1.4 Update Nginx Configuration

Make sure your Proxy Server setup forwards requests from `/inbox` to the service running on `localhost` at port `3001`.

After making these adjustments, restart Nginx to apply the changes.


## Finished

Congratulations! You now have a valid Mastodon endpoint for your RSS3 node.

Your Mastodon endpoint is: `instance_external_ip:9092`



### Next Steps: RSS3 Node Deployment

Now that you have your Mastodon endpoint, you can proceed with the RSS3 node deployment:

1. Return to the [RSS3 Explorer](https://explorer.rss3.io/).
2. If you haven't started the node deployment process, begin it now.
3. During the configuration step, you'll be asked to set up workers for your node.
4. Choose to add a Mastodon worker.
5. When prompted for a Mastodon endpoint, enter your endpoint: `your_external_ip:9092`.
6. Complete the remaining steps as guided by the RSS3 Explorer.

### Important Notes

- Ensure your firewall allows incoming connections on port 9092.
- If you encounter any issues during the RSS3 node deployment, double-check your Mastodon endpoint and review the integration steps.

## Support and Further Information

- For Mastodon-related questions, refer to the [official Mastodon documentation](https://docs.joinmastodon.org/).
- For RSS3-specific inquiries, check the [RSS3 documentation](https://docs.rss3.io/).
- If you encounter any issues with this integration, please open an issue in this repository.

