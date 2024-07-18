# Mastodon-plugin

This repository builds Mastodon Plugin (a backend service) to handle ActivityPub events and direct them to local Kafka Broker. 

Any Mastodon Instance operator can run the Plugin as a docker-service in the `docker-compose.yaml` file of the Mastodon repository. The **Pre-built Image** is provided. 

Then it's needed to update the Nginx configuration forward /inbox requests to the kafka_sender service.

Now, you should be ready to go!

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

## Rebuilding the Docker Image (Optional)
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

Also, for the kafka service in your docker-compose.yaml, please include Your `Public IP` in the `KAFKA_ADVERTISED_LISTENERS`. You can also set `Kafka Broker Id` and do other Kafka configuration.
```yaml
 kafka:
    image: wurstmeister/kafka
    ports:
      - "9092:9092"
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://{YOUR PUBLIC IP ADDRESS}:9092
      KAFKA_BROKER_ID: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    depends_on:
      - zookeeper
```

## Setting Up Nginx
Update your Nginx configuration to forward /inbox requests to the kafka_sender service:

/etc/nginx/sites-enabled/mastodon.conf:
```
server {
...
   location /inbox {
        proxy_pass http://127.0.0.1:3001; # Forward to the Kafka sender service

        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $host;
    }
...
}
```

## Consuming Messages from Kafka
Here’s an example of how to consume messages from the Kafka activitypub_events topic using Go:

Pleae include your `Public IP of your Kafka broker` when you set up your Kafka consumer.

The group.id is: `test-group1`

Default port is: 9092

main.go:
```Go
package main

import (
    "fmt"
    "gopkg.in/confluentinc/confluent-kafka-go.v1/kafka"
)
func main() {
    // input the public IP of your Kafka broker
    config := &kafka.ConfigMap{"bootstrap.servers": "{Your Public IP}:9092", "group.id": "test-group1"}

    consumer, err := kafka.NewConsumer(config)
    if err != nil {
        fmt.Printf("Failed to create consumer: %s\n", err)
        return
    }

    defer consumer.Close()

    err = consumer.Subscribe("activitypub_events", nil)
    if err != nil {
        fmt.Printf("Failed to subscribe to topic: %s\n", err)
        return
    }

    for {
        msg, err := consumer.ReadMessage(-1)
        if err != nil {
            fmt.Printf("Consumer error: %v (%v)\n", err, msg)
            continue
        }

        fmt.Printf("Received message: %s\n", string(msg.Value))
    }
}
```


## Finished

You are ready to go, restart your docker service and see the result:

