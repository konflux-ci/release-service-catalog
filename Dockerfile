FROM registry.access.redhat.com/ubi9/ubi-minimal:9.4-1227.1726694542

# It is mandatory to set these labels
LABEL name="Konflux Release Service Catalog"
LABEL description="Konflux Release Service Catalog"
LABEL io.k8s.description="Konflux Release Service Catalog"
LABEL io.k8s.display-name="release-service Catalog"
LABEL summary="Konflux Release Service Catalog"
LABEL com.redhat.component="release-service Catalog"
