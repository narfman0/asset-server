FROM nginx:alpine

RUN apk add --no-cache bash jq findutils

RUN cat > /etc/nginx/conf.d/default.conf <<'EOF'
server {
    listen 80;
    server_name _;
    root /usr/share/nginx/html;

    index index.json;

    location /assets/ {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
    }

    location ~ \.json$ {
        default_type application/json;
    }
}
EOF

COPY updateIndex.sh /usr/local/bin/updateIndex.sh
RUN chmod +x /usr/local/bin/updateIndex.sh

EXPOSE 80
CMD ["/bin/sh", "-c", "/usr/local/bin/updateIndex.sh && nginx -g 'daemon off;'"]
