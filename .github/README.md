# OpenEMR Docker Testing

This directory contains a GitHub Actions workflow to test the OpenEMR 7.0.4 Docker image.

## Workflow: OpenEMR Docker Test

The `build-test.yml` workflow verifies that the OpenEMR Docker image can be built correctly and functions with a database connection. It performs the following steps:

1. Builds the OpenEMR 7.0.4 Docker image
2. Sets up a test environment using Docker Compose with:
   - MariaDB 11.4 database
   - OpenEMR container connected to the database
3. Verifies that the web server is responding correctly

### Triggers

The workflow runs automatically when:
- Files in the `docker/openemr/7.0.4/` directory are changed on the main branch
- A pull request targeting the main branch changes files in the `docker/openemr/7.0.4/` directory

It can also be run manually through the GitHub Actions tab using workflow_dispatch.

## Running the Test Manually

To run the test manually:
1. Go to the GitHub Actions tab in the repository
2. Select "OpenEMR Docker Test" from the workflows list
3. Click "Run workflow"
4. Choose the branch to run the test on
5. Click "Run workflow"

For debugging purposes, you can enable the tmate debugging option when running the workflow manually. This will provide an SSH connection to the GitHub Actions runner for interactive debugging.

## Adding Tests for Other OpenEMR Versions

To add tests for other OpenEMR versions:
1. Copy the existing workflow and update the version number
2. Update the paths in the workflow triggers
3. Update the image tags and other version-specific information
