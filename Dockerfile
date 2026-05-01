FROM almalinux:9

RUN dnf install -y \
    https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm && \
    dnf -qy module disable postgresql && \
    dnf install -y \
    postgresql16-server \
    procps-ng && \
    dnf clean all

ENV PATH=/usr/pgsql-16/bin:$PATH \
    PGDATA=/var/lib/pgsql/16/data \
    PGUSER=postgres \
    PGPORT=5432 \
    PGDATABASE=postgres

EXPOSE 5432
USER postgres
WORKDIR /tmp

COPY --chown=postgres:postgres docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=3 \
    CMD pg_isready -U postgres || exit 1

ENTRYPOINT ["docker-entrypoint.sh"]


