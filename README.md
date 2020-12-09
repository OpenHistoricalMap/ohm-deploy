# ohm-deploy
OpenHistoricalMap deploy based on the osm-seed chart

## Using this repo

This repo is used for deploying to Staging and Production for the main parts of the stack that runs OpenHistoricalMap.org. 

Commits to `main` and `staging` will kick off a Github Actions build process that takes somewhere between 30 and 45 minutes.

You can't really test this code locally, which can make it tempting to commit changes directly to `staging` or `main`. Don't do it! Since every commit kicks off a build, it is still best practice to make all changes in a branch so you can review them, or ask someone else to do so, before merging in and kicking off a build.

## Updating the OHM website

For updating the OHM website, which is a common reason for a deploy, see these lines:

https://github.com/OpenHistoricalMap/ohm-deploy/blob/main/images/web/Dockerfile#L118-L121

```
# change the echo here with a reason for changing the commithash
RUN echo 'Set the right commit: iD and staging tiles for staging website'
RUN git fetch
RUN git checkout 293d27abe0ed16abba7dd5849a29a5d3c7de4588
```
Change the message as appropriate and the commit hash to whatever commit in the `ohm-website` repo that you want to deploy.

By practice, commit hashes from the `staging` branch on `ohm-website` should go to `staging` here and commit hashes from `production` on `ohm-website` should go to `main` here. 

That said, there are times when we have published feature branches to `staging` to allow them to be viewed and tested by people who are not running the stack locally. That is fine, but should not be done for `main`.