# Deploy in hetzner

This folder contains the services that are being deployed on Hetzner.
Currently, deployment is handled through Docker Compose, with the correct configuration and automatic restarts.

This environment is used for development, since many of these secondary services consume significant resources, and deploying them on AWS would result in high maintenance costs. On Hetzner, however, the cost is much lower, and it provides large processing and memory capacities.

Each folder includes the configuration needed to start the containers. Also, remember to properly update the client configurations so that the URLs can correctly redirect traffic to these containers.
