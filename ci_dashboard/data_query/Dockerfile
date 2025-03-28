FROM golang:1.24.1

RUN curl https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz | \
    tar zxf - google-cloud-sdk && \
    google-cloud-sdk/install.sh --quiet && \
    ln -s /google-cloud-sdk/bin/gcloud /usr/bin/gcloud
ENV PATH="$PATH:/go/google-cloud-sdk/bin/"

WORKDIR /data_query

COPY go.mod ./
COPY go.sum ./
COPY . .

RUN go mod download

RUN go build -o main .

CMD ["./upload.sh"]