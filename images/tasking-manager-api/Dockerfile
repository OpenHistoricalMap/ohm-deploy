FROM python:3.7-alpine

RUN apk update && \
    apk add git

ENV workdir /usr/src/app

RUN git clone https://github.com/OpenHistoricalMap/tasking-manager.git $workdir
# Commits on 25 April, 2022
RUN cd $workdir && git checkout -f 7ae7cd258b48cf0d3404e4648589e8f61e4ed7b1
WORKDIR $workdir

# Setup backend dependencies
RUN apk update && \
    apk add \
        gcc \
        g++ \
        make \
        musl-dev \
        libffi-dev \
        python3-dev \
        postgresql-dev \
        geos-dev \
        proj-util \
        proj-dev

RUN pip install -r requirements.txt
RUN pip install apscheduler==3.7.0

## INITIALIZATION
EXPOSE 5000
CMD ["gunicorn", "-b", "0.0.0.0:5000", "--worker-class", "gevent", "--workers", "3", \
    "--threads", "3", "--timeout", "179", "manage:application", "&"]
