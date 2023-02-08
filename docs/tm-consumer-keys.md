# Tasking Manager consumer keys

This is a small guide on how to generate consumer keys for Tasking Manager and where to place  those keys to deploy in Production and Staging. TM is composed of frontend and backend in both ends is necessary to use the same consumer key and those keys need to be place in [`Secrets and Variables/Actions`](https://github.com/OpenHistoricalMap/ohm-deploy/settings) in Github.

- For staging: `STAGING_TM_API_CONSUMER_KEY` and `STAGING_TM_API_CONSUMER_SECRET`
- For production: `PRODUCTION_TM_API_CONSUMER_KEY` and `PRODUCTION_TM_API_CONSUMER_SECRET`


## How to generate consumer keys for TM?

Tasking Manager currently works with OAuth 1, this applications needs permissions of: `read their user preferences` and `modify the map`. e.g 👇

![image](https://user-images.githubusercontent.com/1152236/217357632-3a515574-7693-4b55-b5d8-7e28545c8a41.png)

Use the [staging](https://staging.openhistoricalmap.org/) or [production](https://www.openhistoricalmap.org/) sites to create the consumer keys.