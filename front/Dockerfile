# syntax=docker/dockerfile:1
FROM nginx:1.27-alpine

# nginx:alpine ya trae el usuario nginx (UID/GID 101). No se instala nada extra.
RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx:nginx public/ /usr/share/nginx/html/
COPY --chown=nginx:nginx docker-entrypoint.sh /usr/local/bin/front-entrypoint.sh

RUN chmod 0555 /usr/local/bin/front-entrypoint.sh \
    && chown -R nginx:nginx /usr/share/nginx/html /var/cache/nginx

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD ["wget", "-q", "-O", "-", "http://127.0.0.1:8080/healthz"]

ENTRYPOINT ["/usr/local/bin/front-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
