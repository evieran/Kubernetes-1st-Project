FROM nginx:alpine
LABEL maintainer="name <email>"

COPY website /website
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
