FROM python:3.7-alpine

RUN apk update && \
    apk add git

ENV workdir /usr/src/app

RUN git clone https://github.com/OpenHistoricalMap/tasking-manager.git $workdir
# Commits on 27 April, 2022
RUN cd $workdir && git checkout -f f0df07174f4014365220af09187b5f941f9770b0
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

RUN pip install --upgrade pip
RUN pip install wheel
RUN pip install -r requirements.txt
RUN pip install apscheduler==3.7.0

## INITIALIZATION
EXPOSE 5000
CMD ["gunicorn", "-b", "0.0.0.0:5000", "--worker-class", "gevent", "--workers", "3", \
    "--threads", "3", "--timeout", "179", "manage:application", "&"]
