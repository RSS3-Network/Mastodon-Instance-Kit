# Use Bitnami Kafka image that includes Kafka and Zookeeper
FROM bitnami/kafka:latest

# Switch to root user to install Python3 and pip
USER root

# Install python3 and pip
RUN apt-get update && apt-get install -y python3 python3-pip python3-venv


# Switch back to non-root user (the default user in Bitnami images is non-root)
USER root


# Copy the Zookeeper and Kafka configuration files
#COPY config/zoo.cfg /opt/bitnami/zookeeper/conf/zoo.cfg
#COPY config/server.properties /opt/bitnami/kafka/config/server.properties



# Copy the entrypoint script and set executable permissions
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh



RUN python3 -m venv /opt/venv

# Activate the virtual environment and install Python dependencies
COPY requirements.txt /app/
RUN /opt/venv/bin/pip install -r /app/requirements.txt





# Copy your kafka_sender.py script into the image
COPY kafka_sender.py /app/kafka_sender.py

# Expose necessary ports for Zookeeper, Kafka, and your kafka_sender service
EXPOSE 2181 9092 3001

# Set entrypoint to manage all services
ENTRYPOINT ["/entrypoint.sh"]

