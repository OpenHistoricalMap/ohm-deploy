FROM python:3.9-slim
WORKDIR /app
RUN pip install --no-cache-dir boto3 kubernetes
COPY main.py /app/main.py
ENTRYPOINT ["python", "main.py"]
