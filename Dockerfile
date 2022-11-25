ARG ALPINE_VERSION=3.17.0

FROM alpine:${ALPINE_VERSION} as build

ARG ALPINE_VERSION
ENV APORTS /home/builder/aports

RUN apk add abuild curl tar make linux-headers patch g++ git gcc ncurses-dev autoconf file
RUN printf "export JOBS=$(getconf _NPROCESSORS_ONLN)\nexport MAKEFLAGS=-j$(getconf _NPROCESSORS_ONLN)\n" >> /etc/abuild.conf

RUN adduser -G abuild -D builder
RUN su builder -c 'git config --global user.email "builder@projecteve.dev" && git config --global user.name "Project EVE"'
RUN su builder -c 'abuild-keygen -a -n'
RUN su builder -c 'mkdir /home/builder/packages'
RUN cp /home/builder/.abuild/*.pub /etc/apk/keys

# RUN su builder -c 'git clone --single-branch --branch v3.16.2-riscv64 https://gitlab.alpinelinux.org/giggsoff/aports $APORTS'
RUN su builder -c 'git clone --single-branch --branch v${ALPINE_VERSION} https://gitlab.alpinelinux.org/alpine/aports $APORTS'

COPY /patches /tmp/patches
RUN busybox su builder -c 'cd $APORTS && if [ -d /tmp/patches/${ALPINE_VERSION} ]; then git am /tmp/patches/${ALPINE_VERSION}/*.patch; fi'

# before we run the build - lets setup our future rootfs
RUN mkdir -p /rootfs/etc/apk/keys
RUN cp /etc/apk/keys/* /home/builder/.abuild/*.rsa.pub /rootfs/etc/apk/keys
RUN cp /etc/passwd* /etc/shadow* /etc/group* /rootfs/etc/
RUN printf "/home/builder/packages/main\n/home/builder/packages/community\n" > /rootfs/etc/apk/repositories
RUN tar -C / -cf - home/builder | tar -C /rootfs -xf -
RUN rm -rf /home/builder/packages && ln -s /rootfs/home/builder/packages /home/builder/packages

RUN busybox su builder -c 'cd $APORTS && sh -x ./scripts/bootstrap.sh riscv64'

WORKDIR /

RUN apk add --arch riscv64 -X /home/builder/packages/main --no-cache --initdb -p /rootfs busybox-static apk-tools-static
RUN chroot /rootfs /bin/busybox.static --install -s /bin
RUN chroot /rootfs /sbin/apk.static add apk-tools busybox alpine-baselayout abuild ca-certificates

# now build the final image
FROM scratch

COPY --from=build /rootfs/ /

ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
USER builder
WORKDIR /home/builder
CMD sh

# to build minirootfs:
# ./mkimage.sh --repository ~/packages/main --repository ~/packages/community --outdir ~/minirootfs --profile "minirootfs"
