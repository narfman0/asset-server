FROM nginx:alpine

RUN apk add --no-cache bash jq findutils

RUN cat > /etc/nginx/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;

    # The cooker writes /usr/share/nginx/html/assets/index.json directly into
    # the served tree, so /index.json resolves to it via the rewrite below.
    location = /index.json {
        try_files /assets/index.json =404;
    }
    location = / {
        return 302 /index.json;
    }

    location /assets/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location /raw/ {
        alias /raw/;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location ~ \.json$ {
        default_type application/json;
    }
}
EOF

# Index regeneration script lives outside this image — bind-mounted from the
# host so cooker and nginx see the same script. The container's startup runs
# it once as a belt-and-suspenders pass in case the cooker hasn't yet.
COPY updateIndex.sh /usr/local/bin/updateIndex.sh
RUN chmod +x /usr/local/bin/updateIndex.sh

EXPOSE 80
CMD ["/bin/sh", "-c", "COOKED_DIR=/usr/share/nginx/html/assets RAW_DIR=/raw OUTPUT=/usr/share/nginx/html/assets/index.json /usr/local/bin/updateIndex.sh; nginx -g 'daemon off;'"]
