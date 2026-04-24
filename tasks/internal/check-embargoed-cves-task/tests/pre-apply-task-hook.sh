#!/usr/bin/env bash

# Create a dummy osidb secret (and delete it first if it exists)
# The secret name is hardcoded in the task so the mock secret name can't have the task name in it
kubectl delete secret osidb-service-account --ignore-not-found
kubectl create secret generic osidb-service-account --from-literal=name=myname --from-literal=base64_keytab=OWEyMmJmYzgtYzJkZi00Y2VhLWJkNWItYjMxNzYxZjFkM2M0Cg== --from-literal=osidb_url=myurl
