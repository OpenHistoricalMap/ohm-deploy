# ohm-deploy
OpenHistoricalMap deploy based on the osm-seed chart

## Using this repo

This repo is used for deploying to Staging and Production for the main parts of the stack that runs OpenHistoricalMap.org. 

This repo is **not** used for local development. Each part of the stack has its own local dev methods. For the OHM Website, following the documentation at https://github.com/OpenHistoricalMap/ohm-website#docker-for-local-development.

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

## More details on process for changing, testing, and deploying

This is what the process of making changes to openhistoricalmap.org looks like:

1. Based on `staging`, make a feature-branch at `ohm-website` like `newinspector-stack` or `map-style-202101` or similar. 
2. Running the `ohm-website` locally, make and test your changes locally in that feature branch. You can and should push work-in-progress changes to your feature branch on github.com, so we can all see what's happening if needed. But don't commit directly to `staging` on `ohm-website`.
3. When your changes are working as desired, submit a PR from your feature branches into staging. Assign Dan, Sanjay, or Sajjad to review that PR. We can merge into `staging` and then update the commit hash on the staging branch of this repo, here https://github.com/OpenHistoricalMap/ohm-deploy/blob/staging/images/web/Dockerfile#L119-L121
4. When we do that and push here, that kicks off a Github Actions automated deploy that will make your changes live on https://staging.openhistoricalmap.org.
5. Test on Staging. This is when we can review with folks who are not running locally, share with the community, etc.
6. When we're all happy with the code on Staging, we go back to `ohm-website` repo and make a PR of `staging` into `production` and then update the commit hash on the `main` branch in this OHM-deploy repo, which then kicks off deploy to production to make changes live on https://openhistoricalmap.org.
