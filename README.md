# ohm-deploy
OpenHistoricalMap deploy based on the osm-seed chart

## Using this repo

This repo is used for deploying to Staging and Production for the main parts of the stack that runs OpenHistoricalMap.org. 

This repo is **not** used for local development. Each part of the stack has its own local dev methods. For the OHM Website, following the documentation at https://github.com/OpenHistoricalMap/ohm-website#docker-for-local-development.

Commits to `main` and `staging` will kick off a Github Actions build process that takes somewhere between 30 and 45 minutes.

## Where it deploys

Staging and production run on Hetzner k3s clusters. A push to `staging` deploys staging, a push to `main` deploys production:

1. `build-images.yaml` builds the images with chartpress and pushes them to ghcr.io.
2. When it succeeds, `deploy-k3s-cluster.yaml` runs `helm upgrade --install` on the cluster of that branch.

Values files:
- Production: `values.production.template.yaml`
- Staging: `values.staging.template.yaml`
- Website previews (`web-*` branches): `values.k3s.preview.template.yaml`

The `{{KEY}}` placeholders in the templates are filled from GitHub secrets at deploy time.

You can't really test this code locally, which can make it tempting to commit changes directly to `staging` or `main`. Don't do it! Since every commit kicks off a build, it is still best practice to make all changes in a branch so you can review them, or ask someone else to do so, before merging in and kicking off a build.

## Updating the OHM website

For updating the OHM website, which is a common reason for a deploy, see these lines:

https://github.com/OpenHistoricalMap/ohm-deploy/blob/main/images/web/Dockerfile#L52

```
#change commit hash here to pick up latest changes
ENV OPENHISTORICALMAP_WEBSITE_GITSHA=xyz
```
and line 58:
```
# change the echo here with a reason for changing the commithash
RUN echo 'message about change'
```
Change the message as appropriate and the commit hash to whatever commit in the `ohm-website` repo that you want to deploy.

## More details on process for changing, testing, and deploying

This is what the process of making changes to openhistoricalmap.org looks like:

1. Based on `staging`, make a feature-branch at `ohm-website` like `newinspector-stack` or `map-style-202101` or similar. 
2. Running the `ohm-website` locally, make and test your changes locally in that feature branch. You can and should push work-in-progress changes to your feature branch on github.com, so we can all see what's happening if needed. But don't commit directly to `staging` on `ohm-website`.
3. When your changes are working as desired, submit a PR from your feature branches into staging. Assign Dan, Sanjay, or Sajjad to review that PR. We can merge into `staging` and then update the commit hash on the staging branch of this repo, here https://github.com/OpenHistoricalMap/ohm-deploy/blob/staging/images/web/Dockerfile#L119-L121
4. When we do that and push here, that kicks off a Github Actions automated deploy that will make your changes live on https://www.ohmstaging.org.
5. Test on Staging. This is when we can review with folks who are not running locally, share with the community, etc.
6. When we're all happy with the code on Staging, make a PR of `staging` into `main` branch in this OHM-deploy repo, which then kicks off deploy to production to make changes live on https://openhistoricalmap.org.


## Cronjobs

The chart defines a set of cronjobs. Each one is gated by an `enabled` flag and a
`schedule` in the values file of each environment. Times are UTC. "main API DB"
is the `<release>-web-db` service (the OSM/Rails database).

### Production

| Cronjob | Schedule | When | Depends on |
|---|---|---|---|
| dbBackup web-db | `0 0 * * *` | daily 00:00 | main API DB |
| dbBackup tm-db | `0 1 * * *` | daily 01:00 | Tasking Manager DB |
| osmSimpleMetrics | `0 2 * * *` | daily 02:00 | main API DB + S3 |
| planetDump | `0 3 * * *` | daily 03:00 | main API DB + S3 |
| fullHistory | `0 3 * * 0` | Sunday 03:00 | main API DB + S3 |
| changesetsDump | `0 5 * * 0` | Sunday 05:00 | main API DB + S3 |
| planetStats | `0 7 * * *` | daily 07:00 | planet dump output |
| taginfoDataProcessor | `0 12 * * 0` | Sunday 12:00 | fullHistory output (full-history planet on S3) |
| osmchaApi (fetch_changesets) | `*/2 * * * *` | every 2 min | OSMCha DB + OSM changesets API |
| osmchaApi (process_changesets) | `*/2 * * * *` | every 2 min | OSMCha DB |

### Staging

Every cronjob is off on staging.

> Note: osmcha cron schedules are not set in the values files, so they fall back
> to the osm-seed chart defaults (`fetch_changesets_cronjob` /
> `process_changesets_cronjob`).

> Ordering: `taginfoDataProcessor` reads the full-history planet from S3
> (`URL_HISTORY_PLANET_FILE_STATE`), so it must run after `fullHistory` finishes
> the dump and upload. `fullHistory` runs Sunday 03:00; taginfo runs Sunday 12:00
> to leave ~9h of margin. If a full-history dump ever takes longer than that,
> push taginfo later (e.g. `0 0 * * 1`, Monday 00:00).

## Database backups

The web database has two backups:

- **pgBackRest** (`webDb.pgbackrest`): a sidecar in the `web-db` pod archives WAL
  to S3 every minute and takes a base backup every 24 hours. This allows a
  restore to any point in time.
- **dbBackup web-db** cronjob: a daily `pg_dump` to S3. Production only.

The Tasking Manager database only has the daily `pg_dump`, on production.

## License

This project is licensed under the BSD-2-Clause License. See the [LICENSE.txt](./LICENSE.txt) file for full details.
