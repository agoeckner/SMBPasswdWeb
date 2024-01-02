FROM ubuntu:jammy

ENV LISTEN_ADDR=127.0.0.1
ENV LISTEN_PORT=9688
ENV SMBPASSWD_SMB_HOST="host.docker.internal"

RUN apt-get update; apt-get install -y build-essential wget libssl-dev libz-dev unzip samba

COPY ./ ./smb-passwd-web
    
RUN cd ./smb-passwd-web && ./configure --prefix=/opt/smb_passwd_web && \
    make install

CMD /opt/smb_passwd_web/bin/smb_passwd_web.pl prefork --listen=http://${LISTEN_ADDR}:${LISTEN_PORT}