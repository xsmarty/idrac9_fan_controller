FROM ubuntu:latest

LABEL org.opencontainers.image.authors="xsmarty@gmail.com"

RUN apt-get update

RUN apt-get install ipmitool -y

ADD functions.sh /app/functions.sh
ADD healthcheck.sh /app/healthcheck.sh
ADD controller.sh /app/controller.sh

RUN chmod 0777 /app/functions.sh /app/healthcheck.sh /app/controller.sh

WORKDIR /app

HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "/app/healthcheck.sh" ]

# you should override these default values when running. See README.md
#ENV IDRAC_HOST 192.168.1.1
ENV IDRAC_HOST local
#ENV IDRAC_USERNAME root
#ENV IDRAC_PASSWORD calvin
ENV FAN_BASELINE 7
ENV CPU_TEMPERATURE_THRESHOLD 50
ENV GPU_TEMPERATURE_THRESHOLD 60

CMD ["./controller.sh"]
