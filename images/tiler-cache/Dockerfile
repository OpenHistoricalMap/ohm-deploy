FROM python:3.10
WORKDIR /app
RUN echo "installing requirements"
COPY ./requirements.txt .
RUN pip install --no-cache-dir --upgrade -r requirements.txt

ENV PYTHONPATH="/app"
COPY *.sh .
COPY *.py .
COPY utils/ ./utils
CMD ["python", "sqs_processor.py"]
