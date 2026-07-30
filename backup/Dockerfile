FROM rclone/rclone:latest

RUN apk add --no-cache \
    bash \
    postgresql16-client \
    dcron \
    tzdata

COPY backup.sh /usr/local/bin/backup.sh
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /usr/local/bin/backup.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
