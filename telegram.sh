#!/bin/bash

# vars
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID="$1"
SUBJECT="$2"
MESSAGE="$3"
MONOSPACED_DESCRIPTION=1

TEXT="*${SUBJECT}*

${MESSAGE}"

if [[ ${#TEXT} -gt 4000 ]]; then
	if [ $MONOSPACED_DESCRIPTION -eq 1 ]; then
		TEXT="${TEXT:0:4000}...\`\`\`"
	else
		TEXT="${TEXT:0:4000}..."
	fi
fi

DATA=$(jo chat_id="$TELEGRAM_CHAT_ID" text="$TEXT" parse_mode="markdown" disable_web_page_preview="true")

/usr/bin/curl \
	--silent \
	--output /dev/null \
	--header 'Content-Type: application/json' \
	--request 'POST' \
	--data "$DATA" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
