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


@app.route('/actor/inbox', methods=['POST'])
def actor_inbox():
    data = request.get_json()
    full_object = None
    if data.get('type') == 'Announce':
        object_url = data.get('object')
        print("object_url:", object_url)
        if object_url:
            # Append /activity to the object_url to fetch the correct JSON
            object_url_with_activity = f"{object_url}/activity"
            try:
                # Fetch the object data from the external URL
                response = requests.get(object_url_with_activity)
                if response.status_code == 200:
                    full_object = response.json()

                    # Modify the 'id' to remove '/activity' at the end if it exists
                    if 'id' in full_object and full_object['id'].endswith('/activity'):
                        full_object['id'] = full_object['id'][:-9]  # Removes the last 9 characters (/activity)

                else:
                    return jsonify({
                        'status': 'error',
                        'message': f'Failed to fetch object from {object_url_with_activity}, Status Code: {response.status_code}',
                        'url': object_url_with_activity
                    }), 400
            except requests.RequestException as e:
                return jsonify({'status': 'error', 'message': f'Error fetching the object: {str(e)}', 'url': object_url_with_activity}), 500

    # Send the data to Kafka
    producer.send(KAFKA_TOPIC, full_object)
    return jsonify(full_object), 202


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=3001)
