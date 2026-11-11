# syntax=docker/dockerfile:1
FROM postgres:18

# El servidor de referencia usa TLS interno. El certificado es autofirmado y
# se genera al arrancar, fuera del repositorio. Para un proveedor gestionado,
# usar el certificado/CA que entregue el proveedor y sslmode=verify-full.
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint-ssl.sh /usr/local/bin/entrypoint-ssl.sh
RUN chmod 0555 /usr/local/bin/entrypoint-ssl.sh

ENTRYPOINT ["/usr/local/bin/entrypoint-ssl.sh"]
CMD ["postgres"]
