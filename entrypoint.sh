#!/bin/sh
set -e






# Start Zookeeper
/opt/bitnami/kafka/bin/zookeeper-server-start.sh /opt/bitnami/zookeeper/conf/zoo.cfg &
zookeeper_pid=$!

# Start Kafka
/opt/bitnami/kafka/bin/kafka-server-start.sh /opt/bitnami/kafka/config/server.properties &
kafka_pid=$!

# Start kafka_sender service
. /opt/venv/bin/activate
python3 /app/kafka_sender.py &
kafka_sender_pid=$!

# Wait for any process to exit
wait $zookeeper_pid
wait $kafka_pid
wait $kafka_sender_pid





# Exit with the status of the first process to stop
exit $?

