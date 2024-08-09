FROM python:3.8-slim

RUN apt update && \
    apt install -y git

ENV workdir /usr/src/app

RUN git clone https://github.com/OpenHistoricalMap/tasking-manager.git $workdir
RUN cd $workdir && git checkout -f c2e85feed9660eb66dfcd2009bec2b049dfe0260
WORKDIR $workdir

# Setup backend dependencies
RUN apt update && apt install -y \
    gcc \
    g++ \
    make \
    libffi-dev \
    python3-dev \
    libpq-dev \
    proj-bin && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

RUN pip install --upgrade pip
RUN pip install -r requirements.txt
RUN pip install apscheduler==3.7.0
RUN pip install --upgrade markdown

## INITIALIZATION
EXPOSE 5000
CMD ["gunicorn", "-b", "0.0.0.0:5000", "--worker-class", "gevent", "--workers", "3", \
    "--threads", "3", "--timeout", "179", "manage:application", "&"]
