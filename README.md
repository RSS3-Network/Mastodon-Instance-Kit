# Mastodon-plugin

This repository builds Mastodon Plugin (a backend service) to handle ActivityPub events and direct them to local Kafka Broker. 

Any Mastodon Instance operator can run the Plugin as a docker-service in the `docker-compose.yaml` file of the Mastodon repository. The **Pre-built Image** is provided. 

Note: Some configuration is required in `.env.production` file of the Mastodon repository. (details below)

## Usage

### Using the Pre-built Image from Package Registry

You can directly use the pre-built Docker image from the package registry in your `docker-compose.yml` file. Here's an example `docker-compose.yml`:


```yaml
kafka_sender:
    image: ghcr.io/frankli123/mastodon-plugin-image:latest
    restart: always
    ports:
      - '3001:3001'
    depends_on:
      - kafka
    environment:
      - KAFKA_BROKER=${KAFKA_BROKER:-kafka:9092}
      - KAFKA_TOPIC=${KAFKA_TOPIC:-activitypub_events}
```

## Rebuilding the Docker Image
If you need to make changes to kafka_sender.py or the Dockerfile, you can rebuild the Docker image and push it to your own **Github package registry**.


### Build the Docker Image:
```shell
docker build -t ghcr.io/{your-username}/mastodon-plugin-image:latest .
```

### Log in to GitHub Packages:
```shell
echo "your-github-token" | docker login ghcr.io -u your-username --password-stdin
```

Replace your-github-token with your GitHub token and your-username with your GitHub username.

### Push the Docker image to the package registry:
```shell
docker push ghcr.io/{your-username}/mastodon-plugin-image:latest
```


### Push the Docker image to the package registry:

```shell
docker push ghcr.io/{your-username}/mastodon-plugin-image:latest
```

## Configuration Requirement:
Ensure that the **KAFKA_BROKER** and **KAFKA_TOPIC** environment variables are set correctly in your **docker-compose.yml** file or through a .env file.
You can customize the behavior of the Kafka sender by modifying kafka_sender.py.

Example:
.env.production
```
KAFKA_BROKER=kafka:9092
KAFKA_TOPIC=activitypub_events
```
