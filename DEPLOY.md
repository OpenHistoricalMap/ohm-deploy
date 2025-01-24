# OHM Site Deployment and Migration Guide

Follow these steps to perform a migration, especially during upstream updates:

- 1.	Set the OHM site to read-only mode
This prevents users from making changes during the migration process.

- 2.	Take an EBS backup on AWS
Ensure the backup is fully completed before proceeding with the migration.

- 3.	Adjust the web autoscaling configuration to 1 
Make sure only one container is running to avoid potential migration conflicts.

### Post-Migration

Once the migration is complete, verify that everything has been successfully applied and bring the site back online.
