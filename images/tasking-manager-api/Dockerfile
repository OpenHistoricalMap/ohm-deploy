FROM python:3.8-slim

RUN apt update && \
    apt install -y git

ENV workdir /usr/src/app

RUN git clone https://github.com/OpenHistoricalMap/tasking-manager.git $workdir
# Commits on 27 April, 2022
RUN cd $workdir && git checkout -f 3eaeaf8605663258d83b291a3238d527cc22f84b
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
