FROM python:3.9
ARG KUBECTL_VERSION=v1.30.1
RUN curl -LO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
    && chmod +x kubectl \
    && mv kubectl /usr/local/bin/
RUN kubectl version --client
WORKDIR /app
COPY ./requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --upgrade -r ./requirements.txt
COPY *.sh .
COPY *.py .

# CMD ["bash", "/app/start.sh"]


# RUN apk update && apk add --no-cache \
#     proj \
#     proj-dev \
#     gdal \
#     gdal-dev \
#     geos \
#     geos-dev \
#     python3-dev \
#     py3-pip \
#     build-base \
#     proj-util \
#     git

# # Ensure PROJ_DIR and PATH are set
# ENV PROJ_DIR=/usr
# ENV PATH="/usr/share/proj:${PATH}"

# # Upgrade pip
# RUN python3 -m pip install --upgrade pip

# WORKDIR /app

# # Install Python dependencies
# COPY requirements.txt .
# RUN pip install --no-cache-dir -r requirements.txt

# COPY *.py .

# ENTRYPOINT ["python purge.py"]
