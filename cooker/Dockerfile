# Cooker container: Blender (headless) + inotify-tools + jq.
#
# Watches /raw for FBX changes, runs the transform under cooker/transforms/,
# writes results to /cooked, then regenerates /cooked/index.json via the
# shared updateIndex.sh script.
#
# Blender is installed from the official portable tarball so we get a known
# modern version (matches the host development tooling). The image is large
# (~700 MB after extraction) — built once per cooker version bump.

FROM debian:12-slim

ARG BLENDER_VERSION=5.1.1
ARG BLENDER_MAJOR_MINOR=5.1

RUN apt-get update && apt-get install -y --no-install-recommends \
        wget xz-utils ca-certificates \
        libxi6 libxxf86vm1 libxfixes3 libxrender1 libxkbcommon0 libsm6 \
        libgl1 libglu1-mesa libgomp1 \
        inotify-tools jq findutils bash python3 \
    && rm -rf /var/lib/apt/lists/*

RUN cd /opt \
 && wget -q "https://download.blender.org/release/Blender${BLENDER_MAJOR_MINOR}/blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
 && tar xJf "blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
 && rm "blender-${BLENDER_VERSION}-linux-x64.tar.xz" \
 && ln -s "/opt/blender-${BLENDER_VERSION}-linux-x64/blender" /usr/local/bin/blender

WORKDIR /opt/cooker

COPY transforms/ /opt/cooker/transforms/
COPY watch.sh    /opt/cooker/watch.sh
COPY cook.sh     /opt/cooker/cook.sh

RUN chmod +x /opt/cooker/watch.sh /opt/cooker/cook.sh

CMD ["/opt/cooker/watch.sh"]
