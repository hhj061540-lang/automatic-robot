FROM ubuntu:24.04

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
    apache2 \
    bash \
    curl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/cgi-bin

RUN a2enmod rewrite cgi

RUN printf '%s\n' \
'<Directory /var/www/html/cgi-bin>' \
'    Options +ExecCGI' \
'    AddHandler cgi-script .cgi' \
'    Require all granted' \
'</Directory>' \
> /etc/apache2/conf-available/cgi-api.conf

RUN a2enconf cgi-api

# ------------------------------------------------------------
# /api/models
# ------------------------------------------------------------

RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'' \
'printf "Content-Type: application/json\r\n"' \
'printf "Access-Control-Allow-Origin: *\r\n"' \
'printf "Access-Control-Allow-Methods: GET, OPTIONS\r\n"' \
'printf "Access-Control-Allow-Headers: Authorization\r\n"' \
'printf "\r\n"' \
'' \
'if [ "$REQUEST_METHOD" = "OPTIONS" ]; then exit 0; fi' \
'' \
'if [ "$REQUEST_METHOD" != "GET" ]; then' \
'    printf "{\"error\":\"GET required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'AUTH="${HTTP_AUTHORIZATION:-}"' \
'' \
'if [[ "$AUTH" != Bearer\ * ]]; then' \
'    printf "{\"error\":\"OpenAI API key required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'KEY="${AUTH#Bearer }"' \
'' \
'curl -sS --connect-timeout 15 --max-time 60 \' \
'    https://api.openai.com/v1/models \' \
'    -H "Authorization: Bearer $KEY"' \
> /var/www/html/cgi-bin/models.cgi

# ------------------------------------------------------------
# /api/chat
# ------------------------------------------------------------

RUN printf '%s\n' \
'#!/usr/bin/env bash' \
'' \
'printf "Content-Type: application/json\r\n"' \
'printf "Access-Control-Allow-Origin: *\r\n"' \
'printf "Access-Control-Allow-Methods: POST, OPTIONS\r\n"' \
'printf "Access-Control-Allow-Headers: Content-Type, Authorization\r\n"' \
'printf "\r\n"' \
'' \
'if [ "$REQUEST_METHOD" = "OPTIONS" ]; then exit 0; fi' \
'' \
'if [ "$REQUEST_METHOD" != "POST" ]; then' \
'    printf "{\"error\":\"POST required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'AUTH="${HTTP_AUTHORIZATION:-}"' \
'' \
'if [[ "$AUTH" != Bearer\ * ]]; then' \
'    printf "{\"error\":\"OpenAI API key required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'KEY="${AUTH#Bearer }"' \
'BODY="$(cat)"' \
'' \
'# Minimal JSON extraction without Python or jq.' \
'MODEL="$(printf "%s" "$BODY" | sed -n "s/.*\"model\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p")"' \
'PROMPT="$(printf "%s" "$BODY" | sed -n "s/.*\"prompt\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p")"' \
'' \
'if [ -z "$MODEL" ]; then' \
'    printf "{\"error\":\"model is required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'if [ -z "$PROMPT" ]; then' \
'    printf "{\"error\":\"prompt is required\"}\n"' \
'    exit 0' \
'fi' \
'' \
'# Escape basic JSON characters.' \
'MODEL="$(printf "%s" "$MODEL" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g")"' \
'PROMPT="$(printf "%s" "$PROMPT" | sed "s/\\\\/\\\\\\\\/g; s/\"/\\\\\"/g")"' \
'' \
'REQUEST="{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}"' \
'' \
'curl -sS --connect-timeout 15 --max-time 120 \' \
'    https://api.openai.com/v1/chat/completions \' \
'    -H "Authorization: Bearer $KEY" \' \
'    -H "Content-Type: application/json" \' \
'    -d "$REQUEST"' \
> /var/www/html/cgi-bin/chat.cgi

RUN chmod +x \
    /var/www/html/cgi-bin/models.cgi \
    /var/www/html/cgi-bin/chat.cgi

# ------------------------------------------------------------
# Apache URL routes
# ------------------------------------------------------------

RUN printf '%s\n' \
'RewriteEngine On' \
'RewriteRule ^api/models$ /cgi-bin/models.cgi [L,QSA]' \
'RewriteRule ^api/chat$ /cgi-bin/chat.cgi [L,QSA]' \
> /var/www/html/.htaccess

EXPOSE 10000

CMD ["bash", "-c", "sed -i \"s/^Listen .*/Listen ${PORT:-10000}/\" /etc/apache2/ports.conf && apachectl -D FOREGROUND"]
