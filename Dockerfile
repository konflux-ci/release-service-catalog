FROM quay.io/konflux-ci/release-service-utils@sha256:aa18816418dbec54abef7213ff92e594dee4f9c2f173df81e96c867ba1ce4042

ARG TKN_VERSION=0.40.0
ARG KUSTOMIZE_VERSION=5.6.0

# It is mandatory to set these labels
LABEL name="Konflux Release Service Catalog"
LABEL description="Konflux Release Service Catalog"
LABEL io.k8s.description="Konflux Release Service Catalog"
LABEL io.k8s.display-name="release-service-catalog"
LABEL summary="Konflux Release Service Catalog"
LABEL com.redhat.component="release-service-catalog"

RUN curl -L https://github.com/tektoncd/cli/releases/download/v${TKN_VERSION}/tektoncd-cli-${TKN_VERSION}_Linux-64bit.rpm \
    -o /tmp/tektoncd-cli-Linux-64bit.rpm
RUN dnf install -y /tmp/tektoncd-cli-Linux-64bit.rpm
RUN tkn version --component client

RUN dnf -y --setopt=tsflags=nodocs install \
    gettext \
    procps-ng \
    && dnf clean all

RUN python3 -m pip install --user ansible
RUN ansible-vault --version
RUN kubectl version --client=true
RUN echo $HOME

RUN curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz \
    | tar -C /usr/bin/ -xzf - kustomize &&\
    chmod +x /usr/bin/kustomize

ADD integration-tests/ /home/e2e/tests/
