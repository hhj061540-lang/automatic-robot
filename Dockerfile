FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y apache2 bash curl && \
    a2enmod cgi rewrite headers && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/cgi-bin

RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'printf "Content-Type: application/json\r\n"' \
'printf "Access-Control-Allow-Origin: *\r\n"' \
'printf "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"' \
'printf "Access-Control-Allow-Headers: Authorization, Content-Type\r\n"' \
'printf "\r\n"' \
'' \
'if [ "$REQUEST_METHOD" = "OPTIONS" ]; then' \
'  printf "{\"ok\":true}\n"' \
'  exit 0' \
'fi' \
'' \
'if [ "$REQUEST_METHOD" != "GET" ]; then' \
'  printf "{\"error\":\"Method Not Allowed\"}\n"' \
'  exit 0' \
'fi' \
'' \
'AUTH="${HTTP_AUTHORIZATION:-}"' \
'KEY="${AUTH#Bearer }"' \
'' \
'if [ -z "$KEY" ] || [ "$KEY" = "$AUTH" ]; then' \
'  printf "{\"error\":\"Missing Authorization: Bearer OPENAI_API_KEY\"}\n"' \
'  exit 0' \
'fi' \
'' \
'curl -sS --connect-timeout 15 --max-time 60 \' \
'  https://api.openai.com/v1/models \' \
'  -H "Authorization: Bearer $KEY"' \
> /var/www/html/cgi-bin/models.cgi

RUN chmod +x /var/www/html/cgi-bin/models.cgi

RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'printf "Content-Type: application/json\r\n"' \
'printf "Access-Control-Allow-Origin: *\r\n"' \
'printf "Access-Control-Allow-Methods: POST, OPTIONS\r\n"' \
'printf "Access-Control-Allow-Headers: Authorization, Content-Type\r\n"' \
'printf "\r\n"' \
'' \
'if [ "$REQUEST_METHOD" = "OPTIONS" ]; then' \
'  printf "{\"ok\":true}\n"' \
'  exit 0' \
'fi' \
'' \
'if [ "$REQUEST_METHOD" != "POST" ]; then' \
'  printf "{\"error\":\"Method Not Allowed\"}\n"' \
'  exit 0' \
'fi' \
'' \
'AUTH="${HTTP_AUTHORIZATION:-}"' \
'KEY="${AUTH#Bearer }"' \
'' \
'if [ -z "$KEY" ] || [ "$KEY" = "$AUTH" ]; then' \
'  printf "{\"error\":\"Missing Authorization: Bearer OPENAI_API_KEY\"}\n"' \
'  exit 0' \
'fi' \
'' \
'BODY="$(cat)"' \
'MODEL="$(printf "%s" "$BODY" | sed -n '\''s/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'\'')"' \
'PROMPT="$(printf "%s" "$BODY" | sed -n '\''s/.*"prompt"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'\'')"' \
'' \
'if [ -z "$MODEL" ]; then' \
'  printf "{\"error\":\"Missing model\"}\n"' \
'  exit 0' \
'fi' \
'' \
'if [ -z "$PROMPT" ]; then' \
'  printf "{\"error\":\"Missing prompt\"}\n"' \
'  exit 0' \
'fi' \
'' \
'MODEL="$(printf "%s" "$MODEL" | sed '\''s/\\/\\\\/g; s/"/\\"/g'\'')" ' \
'PROMPT="$(printf "%s" "$PROMPT" | sed '\''s/\\/\\\\/g; s/"/\\"/g'\'')" ' \
'' \
'REQUEST="{\"model\":\"$MODEL\",\"input\":\"$PROMPT\"}"' \
'' \
'curl -sS --connect-timeout 15 --max-time 120 \' \
'  https://api.openai.com/v1/responses \' \
'  -H "Authorization: Bearer $KEY" \' \
'  -H "Content-Type: application/json" \' \
'  -d "$REQUEST"' \
> /var/www/html/cgi-bin/chat.cgi

RUN chmod +x /var/www/html/cgi-bin/chat.cgi

RUN printf '%s\n' \
'RewriteEngine On' \
'RewriteRule ^api/models$ /cgi-bin/models.cgi [L,QSA]' \
'RewriteRule ^api/chat$ /cgi-bin/chat.cgi [L,QSA]' \
> /var/www/html/.htaccess

RUN printf '%s\n' \
'<Directory /var/www/html/cgi-bin>' \
'    Options +ExecCGI' \
'    AddHandler cgi-script .cgi' \
'    Require all granted' \
'</Directory>' \
> /etc/apache2/conf-available/cgi-api.conf

RUN a2enconf cgi-api

RUN printf '%s\n' \
'ServerName localhost' \
> /etc/apache2/conf-available/servername.conf

RUN a2enconf servername

RUN sed -i 's/^Listen 80$/Listen 10000/' /etc/apache2/ports.conf

EXPOSE 10000

CMD ["bash", "-c", "sed -i \"s/<VirtualHost \\*:10000>/<VirtualHost *:${PORT:-10000}>/\" /etc/apache2/sites-available/000-default.conf; sed -i \"s/Listen 10000/Listen ${PORT:-10000}/\" /etc/apache2/ports.conf; apachectl -D FOREGROUND"]
