FROM python:3.9

# Install kubectl
ARG KUBECTL_VERSION=v1.30.1
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/
RUN kubectl version --client
WORKDIR /app

COPY ./requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

ENV PYTHONPATH="/app"
COPY *.sh .
COPY *.py .
COPY utils/ ./utils
CMD ["python", "sqs_processor.py"]
