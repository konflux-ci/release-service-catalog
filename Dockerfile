FROM quay.io/konflux-ci/release-service-utils@sha256:288a903105481b1ea11e558b179cf4010d66a3fa4f4ff22765a256668471554b

ARG TKN_VERSION=0.40.0
ARG KUSTOMIZE_VERSION=5.6.0

# It is mandatory to set these labels
LABEL name="Konflux Release Service Catalog"
LABEL description="Konflux Release Service Catalog"
LABEL io.k8s.description="Konflux Release Service Catalog"
LABEL io.k8s.display-name="release-service-catalog"
LABEL summary="Konflux Release Service Catalog"
LABEL com.redhat.component="release-service-catalog"

# Switch to root to install dependencies
USER 0

RUN curl -L https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tektoncd-cli-${TKN_VERSION}_Linux-64bit.rpm \
    -o /tmp/tektoncd-cli-Linux-64bit.rpm
RUN dnf install -y /tmp/tektoncd-cli-Linux-64bit.rpm

RUN dnf -y --setopt=tsflags=nodocs install \
    gettext \
    procps-ng \
    && dnf clean all

RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz \
    | tar -C /usr/bin/ -xzf - kustomize &&\
    chmod +x /usr/bin/kustomize

# Install ansible system-wide so it's in /usr/local/bin (accessible by all users)  
RUN python3 -m pip install --no-cache-dir ansible  

ADD integration-tests/ /home/e2e/tests/

# Configure non-root user (UID 1001) for security and compatibility (inherited 
# from the release-service-utils base image). Ensure E2E tests can write under
# /home/e2e when running as non-root. OpenShift may assign a random UID/GID at
# runtime, so below sets the ownership and permissions to ensure write access
# for E2E tests at runtime.
RUN chown -R 1001:1001 /home/e2e && \
    # Make all files group-owned by root to allow OpenShift's random UID to work.
    chgrp -R 0 /home/e2e && \
    chmod -R g+rwX /home/e2e && \
    # Ensure group permissions are inherited by new subdirectories
    find /home/e2e -type d -exec chmod g+s {} +

# Switch back to the non-root user
USER 1001

RUN tkn version --component client
RUN ansible-vault --version
RUN kubectl version --client=true
