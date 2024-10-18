from flask import Flask, request, jsonify
from kafka import KafkaProducer
import json
import os
import requests

app = Flask(__name__)

# Read Kafka configurations from environment variables
KAFKA_BROKER = os.environ.get('KAFKA_BROKER', 'kafka:9092')
KAFKA_TOPIC = os.environ.get('KAFKA_TOPIC', 'activitypub_events')

producer = KafkaProducer(
    bootstrap_servers=KAFKA_BROKER,
    value_serializer=lambda v: json.dumps(v).encode('utf-8')
)

def process_inbox(data):
    producer.send(KAFKA_TOPIC, data)
    return jsonify({'status': 'success'}), 202

@app.route('/inbox', methods=['POST'])
def inbox():
    data = request.get_json()
    return process_inbox(data)

@app.route('/actor/inbox', methods=['POST'])
def actor_inbox():
    data = request.get_json()
    if data.get('type') == 'Announce':
        object_url = data.get('object')
        if object_url:
            try:
                response = requests.get(object_url)
                if response.status_code == 200:
                    full_object = response.json()
                    data['full_object'] = full_object
            except requests.RequestException:
                # Handle any errors in fetching the full object
                print(f"Failed to fetch object")
                pass

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001)