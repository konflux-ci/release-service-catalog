FROM registry.access.redhat.com/ubi8/ubi

RUN curl -L https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -o /usr/bin/jq &&\
    curl -L https://github.com/mikefarah/yq/releases/download/v4.25.1/yq_linux_amd64 -o /usr/bin/yq &&\
    chmod +x /usr/bin/jq /usr/bin/yq

RUN dnf -y --setopt=tsflags=nodocs install \
    git \
    python3 \
    && dnf clean all
