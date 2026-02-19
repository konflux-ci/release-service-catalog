FROM registry.access.redhat.com/ubi9/ubi:latest

RUN dnf install -y python3 python3-pip vim git wget && dnf clean all

# Size set by build-images.sh when copying (300-1500 MB)
ARG IMAGE_SIZE_MB=900
RUN SIZE_MB=${IMAGE_SIZE_MB} && \
    echo "Building large test image: ${SIZE_MB} MB" && \
    dd if=/dev/urandom of=/opt/data.bin bs=1M count=${SIZE_MB} 2>/dev/null && \
    echo "Image size: ${SIZE_MB} MB" > /opt/size.txt

WORKDIR /app
COPY . /app/

LABEL test-type="large-snapshot" size-range="300-1500MB"

CMD ["/bin/bash", "-c", "cat /opt/size.txt && tail -f /dev/null"]
