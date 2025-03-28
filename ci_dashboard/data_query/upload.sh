#!/bin/bash

# Run the program to generate the dashboard.
./main

# Upload the dashboard to GCS.
gcloud storage cp ./workflow_runs.json gs://ml-dashboard-data-gatherer
