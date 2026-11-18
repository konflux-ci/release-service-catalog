FROM registry.access.redhat.com/ubi9/ubi-minimal:latest

RUN mkdir -p /releases \
    && dd if=/dev/zero of=/releases/test-disk-image.raw bs=1M count=0 seek=1024 \
    && printf '\x00\x00\x00\x00\x83\x00\x00\x00\x00\x08\x00\x00\x00\xf8\x1f\x00' \
        | dd of=/releases/test-disk-image.raw bs=1 seek=446 conv=notrunc \
    && printf '\x55\xaa' \
        | dd of=/releases/test-disk-image.raw bs=1 seek=510 conv=notrunc
