FROM python:3.8-slim
RUN pip install flask kafka-python requests
COPY kafka_sender.py /app/kafka_sender.py
WORKDIR /app
CMD ["python", "kafka_sender.py"]