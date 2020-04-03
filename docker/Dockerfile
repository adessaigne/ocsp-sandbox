FROM ubuntu

RUN apt-get update && apt-get install -y openssl vim

ADD start.sh sign.sh revoke.sh rootca.sh /

RUN chmod +x /*.sh

EXPOSE 9000

CMD /start.sh
