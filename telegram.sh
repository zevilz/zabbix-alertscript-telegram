#!/usr/bin/env bash
# Script for sending Zabbix alerts via Telegram bot
# URL: https://github.com/zevilz/zabbix-alertscript-telegram
# Author: zEvilz
# License: MIT
# Version: 2.0.0

# vars
TELEGRAM_BOT_TOKEN=""
TELEGRAM_MESSAGE_LIMIT=4000
TELEGRAM_CAPTION_LIMIT=900
GRAPHS=0
GRAPHS_DIR=
ZABBIX_URL=""
ZABBIX_USER=""
ZABBIX_PASS=""
ZABBIX_COOKIES_LIFETIME=30
ZABBIX_COOKIES_PATH=
MONOSPACED_DESCRIPTION=0
SCRIPT_LOG_PATH=
DEBUG=0

checkFilePermissions()
{
	if [ -w "$1" ] && ! [ -f "$1" ] || ! [ -f "$1" ] && ! [ -w "$(dirname $1)" ] || [ -f "$1" ] && ! [ -w "$1" ] || ! [ -d "$(dirname $1)" ] || [ -d "$1" ]; then
		echo "Can't write into $1 or it not a file!"
		exit 1
	fi
}

checkDirPermissions()
{
	if [ -w "$1" ] && ! [ -d "$1" ] || ! [ -d "$1" ] && ! [ -w "$(dirname $1)" ] || [ -d "$1" ] && ! [ -w "$1" ] || ! [ -d "$(dirname $1)" ] || [ -f "$1" ]; then
		echo "Can't write into $1 or it not a directory!"
		exit 1
	fi
}

prepareCookies()
{
	if ! [ -f "$ZABBIX_COOKIES_PATH" ]; then
		touch "$ZABBIX_COOKIES_PATH"
		chmod 600 "$ZABBIX_COOKIES_PATH"
	else
		if ! [ -z "$(grep zbx_session $ZABBIX_COOKIES_PATH)" ]; then
			COOKIE_EXPIRE_TIME=$(grep zbx_session "$ZABBIX_COOKIES_PATH" | tail -n 1 | awk '{print $5}')
			COOKIE_MODIFY_TIME=$(date -r "$ZABBIX_COOKIES_PATH" +%s)
			if [ "$CUR_TIME" -lt "$COOKIE_EXPIRE_TIME" ] && [ "$((CUR_TIME-COOKIE_MODIFY_TIME))" -lt "$ZABBIX_COOKIES_LIFETIME" ]; then
				ZABBIX_AUTH_NEEDED=0
			fi
			pushToLog "[DEBUG] - current time: $CUR_TIME; cookies expire time: $COOKIE_EXPIRE_TIME; cookies modify time: $COOKIE_MODIFY_TIME; cookies lifetime: $ZABBIX_COOKIES_LIFETIME; auth needed: $ZABBIX_AUTH_NEEDED"
		fi
	fi
}

prepareGraphsDir()
{
	if ! [ -d "$GRAPHS_DIR" ]; then
		mkdir "$GRAPHS_DIR"
		chmod 700 "$GRAPHS_DIR"
	fi

	GRAPHS_DIR=$(echo "$GRAPHS_DIR" | sed 's/\/$//')
}

extractGraphData()
{
	GRAPH_DATA=$(echo "$TEXT" | grep -o -E '(<graph:[^>]+>)' | tail -n 1 | tr -d '<>')
	TEXT=$(echo "$TEXT" | sed -E 's/<graph:[^>]+>//g')
}

zbxApiAuth()
{
	ZABBIX_AUTH_TOKEN=
	if ! [ -z "$ZABBIX_API_URL" ] && ! [ -z "$ZABBIX_USER" ] && ! [ -z "$ZABBIX_PASS" ]; then
		ZABBIX_AUTH=$(/usr/bin/curl -s -X POST \
			-H 'Content-Type: application/json-rpc' \
			-d " \
			{
			 \"jsonrpc\": \"2.0\",
			 \"method\": \"user.login\",
			 \"params\": {
			  \"user\": \"$ZABBIX_USER\",
			  \"password\": \"$ZABBIX_PASS\"
			 },
			 \"id\": 1,
			 \"auth\": null
			}
			" "$ZABBIX_API_URL" 2>/dev/null
		)

		if ! [ -z "$ZABBIX_AUTH" ]; then
			ZABBIX_AUTH_TOKEN=$(echo "$ZABBIX_AUTH" | jq -r '.result' 2>/dev/null)

			if [[ "$ZABBIX_AUTH_TOKEN" == "null" ]]; then
				ZABBIX_AUTH_TOKEN=

				ZABBIX_AUTH_ERROR=$(echo "$ZABBIX_AUTH" | jq -r '.error.data' 2>/dev/null)

				if ! [ -z "$ZABBIX_AUTH_ERROR" ]; then
					pushToLog "[ERROR] - Can't get Zabbix API auth token: $ZABBIX_AUTH_ERROR"
				else
					pushToLog "[ERROR] - Can't get Zabbix API auth token: wrong API response"
				fi
			fi
		else
			pushToLog "[ERROR] - Can't get Zabbix API auth token"
		fi
	else
		pushToLog "[ERROR] - Can't get Zabbix API auth token: wrong input data for auth in Zabbix API"
	fi
}

zbxApiGetGraphId()
{
	ZABBIX_GRAPH_ID=
	if ! [ -z "$ZABBIX_API_URL" ] && ! [ -z "$ZABBIX_AUTH_TOKEN" ] && ! [ -z "$GRAPH_ITEM_ID" ]; then
		ZABBIX_GRAPH=$(/usr/bin/curl -s -X POST \
			-H 'Content-Type: application/json-rpc' \
			-d " \
			{
			 \"jsonrpc\": \"2.0\",
				\"method\": \"graph.get\",
				\"params\": {
					\"output\": \"extend\",
					\"itemids\": $GRAPH_ITEM_ID
				},
				\"auth\": \"$ZABBIX_AUTH_TOKEN\",
				\"id\": 1
			}
			" "$ZABBIX_API_URL" 2>/dev/null
		)

		if ! [ -z "$ZABBIX_GRAPH" ]; then
			ZABBIX_GRAPH_ID=$(echo "$ZABBIX_GRAPH" | jq -r '.result[].graphid' 2>/dev/null)

			if [ -z "$ZABBIX_GRAPH_ID" ]; then
				ZABBIX_GRAPH_ERROR=$(echo "$ZABBIX_GRAPH" | jq -r '.error.data' 2>/dev/null)

				if [[ "$ZABBIX_GRAPH_ERROR" == "null" ]]; then
					if [ "$DEBUG" -eq 1 ]; then
						pushToLog "[DEBUG] - Graph not exists for this item (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID)"
					fi
				else
					pushToLog "[ERROR] - Can't get graph ID: $ZABBIX_GRAPH_ERROR (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID)"
				fi
			fi
		else
			pushToLog "[ERROR] - Can't get graph ID"
		fi
	else
		pushToLog "[ERROR] - Can't get graph ID: wrong input data for graph ID request"
	fi
}

zbxGetGraphImage()
{
	local ZABBIX_WEB_AUTH
	local ZABBIX_WEB_AUTH_FAIL=0
	local GRAPH_PATH_FILEINFO
	local GRAPH_PATH_FILEINFO_HEIGHT
	local GRAPH_WIDTH_PARAM
	local GRAPH_HEIGHT_PARAM

	if ! [ -z "$ZABBIX_URL" ] && ! [ -z "$ZABBIX_USER" ] && ! [ -z "$ZABBIX_PASS" ] && ! [ -z "$ZABBIX_GRAPH_ID" ] && ! [ -z "$GRAPH_PERIOD" ]; then
		GRAPH_PATH="${GRAPHS_DIR}/graph_${ZABBIX_GRAPH_ID}_${CUR_TIME}.png"

		if [ "$ZABBIX_AUTH_NEEDED" -eq 1 ]; then
			if [ "$DEBUG" -eq 1 ]; then
				pushToLog "[DEBUG] - Cookies expired. Trying re-auth."
			fi
			ZABBIX_WEB_AUTH=$(/usr/bin/curl -s -b "$ZABBIX_COOKIES_PATH" -c "$ZABBIX_COOKIES_PATH" -L -d "name=${ZABBIX_USER}&password=${ZABBIX_PASS}&autologin=1&enter=Sign+in" "$ZABBIX_URL" 2>/dev/null)
			if [ -z "$ZABBIX_WEB_AUTH" ]; then
				pushToLog "[ERROR] - Can't auth in Zabbix web: wrong response"
				ZABBIX_WEB_AUTH_FAIL=1
			elif ! [ -z "$(echo "$ZABBIX_WEB_AUTH" | grep "Incorrect user name or password or account is temporarily blocked")" ]; then
				pushToLog "[ERROR] - Can't auth in Zabbix web: incorrect user name or password or account is temporarily blocked"
				ZABBIX_WEB_AUTH_FAIL=1
			fi
		fi

		if [ "$ZABBIX_WEB_AUTH_FAIL" -eq 0 ]; then
			if ! [ -z "$GRAPH_WIDTH" ] && [[ "$GRAPH_WIDTH" =~ ^[0-9]+$ ]] && ! [ "$GRAPH_WIDTH" -eq 0 ]; then
				GRAPH_WIDTH_PARAM="&width=${GRAPH_WIDTH}"
			fi
			if ! [ -z "$GRAPH_HEIGHT" ] && [[ "$GRAPH_HEIGHT" =~ ^[0-9]+$ ]] && ! [ "$GRAPH_HEIGHT" -eq 0 ]; then
				GRAPH_HEIGHT_PARAM="&height=${GRAPH_HEIGHT}"
			fi

			/usr/bin/curl -s -b "$ZABBIX_COOKIES_PATH" -c "$ZABBIX_COOKIES_PATH" -L -H 'Content-Type: image/png' -o "$GRAPH_PATH" "${ZABBIX_URL}/chart2.php?graphid=${ZABBIX_GRAPH_ID}&from=now-${GRAPH_PERIOD}&to=now&profileIdx=web.graphs.filter${GRAPH_WIDTH_PARAM}${GRAPH_HEIGHT_PARAM}" > /dev/null 2>/dev/null

			if [ -f "$GRAPH_PATH" ]; then
				GRAPH_PATH_FILEINFO=$(file "$GRAPH_PATH")

				if [ -z "$(echo "$GRAPH_PATH_FILEINFO" | grep 'PNG')" ]; then
					pushToLog "[ERROR] - Can't get graph image: graph not a PNG or you have no access to graph (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID; graphID: $ZABBIX_GRAPH_ID)"
					rm "$GRAPH_PATH"
				else
					GRAPH_PATH_FILEINFO_HEIGHT=$(echo "$GRAPH_PATH_FILEINFO" | grep -o -E '[0-9]+\ x\ [0-9]+' | awk '{print $NF}')

					if ! [ -z "$GRAPH_PATH_FILEINFO_HEIGHT" ] && [ "$GRAPH_PATH_FILEINFO_HEIGHT" -lt 50 ]; then
						pushToLog "[ERROR] - Can't get graph image: image not a graph or you have no access to graph (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID; graphID: $ZABBIX_GRAPH_ID)"
						rm "$GRAPH_PATH"
					fi
				fi
			else
				pushToLog "[ERROR] - Can't get graph image (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID; graphID: $ZABBIX_GRAPH_ID)"
			fi

			if [ -f "$GRAPH_PATH" ]; then
				GRAPH_ISSET=1
			fi
		fi
	fi
}

tlgSendMessage()
{
	DATA=$(jo chat_id="$TELEGRAM_CHAT_ID" text="$TEXT" parse_mode="markdown" disable_web_page_preview="true")

	TLG_RESPONSE=$(/usr/bin/curl -s \
		-X POST \
		-H 'Content-Type: application/json' \
		-d "$DATA" "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage")
}

tlgSendPhoto()
{
	TEXT=$(echo "$TEXT" | sed -E -e 's/([-"`´,§$%&/(){}#@!?*.\t])/\\\1/g')
	TEXT=$(echo "$TEXT" | sed -E -e 's/\\([^nu])/\1/g')

	TLG_RESPONSE=$(/usr/bin/curl -s \
		-X POST \
		-H "Content-Type:multipart/form-data" \
		-F "chat_id=${TELEGRAM_CHAT_ID}>" \
		-F "photo=@${GRAPH_PATH}" \
		-F "caption=${TEXT}" \
		-F "parse_mode=markdown" \
		"https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendPhoto")
}

tlgCutText()
{
	if ! [ -z $1 ] && [[ ${#TEXT} -gt $1 ]]; then
		if [ $MONOSPACED_DESCRIPTION -eq 1 ]; then
			TEXT="${TEXT:0:$1}...\`\`\`"
		else
			TEXT="${TEXT:0:$1}..."
		fi
	fi
}

tlgResult()
{
	tlgResult=$(echo "$TLG_RESPONSE" | jq -r '.["ok"]')

	if [[ "$tlgResult" == 'true' ]]; then
		echo 0
	elif [[ "$tlgResult" == 'false' ]]; then
		tlgResult_DESCRIPTION=$(echo "$TLG_RESPONSE" | jq -r '.["description"]')

		if [ "$DEBUG" -eq 1 ]; then
			DEBUG_MESSAGE="\ntext:\n$TEXT"
		else
			DEBUG_MESSAGE=
		fi

		if [ "$GRAPH_ISSET" -eq 1 ]; then
			pushToLog "[ERROR] - Can't send graph: $tlgResult_DESCRIPTION (chatID: $TELEGRAM_CHAT_ID; subject: $SUBJECT; itemID: $GRAPH_ITEM_ID; graphID: $ZABBIX_GRAPH_ID)${DEBUG_MESSAGE}"
		else
			pushToLog "[ERROR] - Can't send message: $tlgResult_DESCRIPTION (chatID: $TELEGRAM_CHAT_ID; subject: $SUBJECT)${DEBUG_MESSAGE}"
		fi

		echo 1
	else
		echo 1
	fi
}

pushToLog()
{
	if [[ $# -eq 1 ]]; then
		echo -e "[$(date +%Y-%m-%d\ %H:%M:%S)] Zabbix Telegram alertscript: $1" >> "$SCRIPT_LOG_PATH"
	fi
}

if [[ $(whoami) != "zabbix" ]]; then
	echo "The script not for direct usage or current user not \"zabbix\"!"
	exit 1
fi

if [[ "$OSTYPE" != "linux-gnu" ]]; then
	echo "The script only for using on GNU Linux dists!"
	exit 1
fi

CUR_DIR=$(dirname "$0")
CUR_TIME=$(date +%s)
GRAPH_ISSET=0
ZABBIX_AUTH_NEEDED=1
TELEGRAM_CHAT_ID="$1"
SUBJECT="$2"
MESSAGE="$3"
TEXT="*${SUBJECT}*

${MESSAGE}"

if [ -z "$ZABBIX_COOKIES_PATH" ]; then
	ZABBIX_COOKIES_PATH="${CUR_DIR}/zbx_cookies"
fi

if [ -z "$SCRIPT_LOG_PATH" ]; then
	SCRIPT_LOG_PATH="${CUR_DIR}/zbx_tlg_bot.log"
fi

if [ -z "$GRAPHS_DIR" ]; then
	GRAPHS_DIR="/tmp/zbx_graphs"
fi

ZABBIX_URL=$(echo "$ZABBIX_URL" | sed 's/\/$//')
ZABBIX_API_URL="${ZABBIX_URL}/api_jsonrpc.php"

checkFilePermissions "$SCRIPT_LOG_PATH"
if [ $GRAPHS -eq 1 ]; then
	checkFilePermissions "$ZABBIX_COOKIES_PATH"
	checkDirPermissions "$GRAPHS_DIR"
fi

extractGraphData

if [ $GRAPHS -eq 1 ] && ! [ -z "$GRAPH_DATA" ] && ! [ -z "$ZABBIX_URL" ] && ! [ -z "$ZABBIX_API_URL" ] && ! [ -z "$ZABBIX_USER" ] && ! [ -z "$ZABBIX_PASS" ]; then
	GRAPH_ITEM_ID=$(echo "$GRAPH_DATA" | awk -F ':' '{print $2}')
	GRAPH_PERIOD=$(echo "$GRAPH_DATA" | awk -F ':' '{print $3}')
	GRAPH_WIDTH=$(echo "$GRAPH_DATA" | awk -F ':' '{print $4}')
	GRAPH_HEIGHT=$(echo "$GRAPH_DATA" | awk -F ':' '{print $5}')

	if ! [ -z "$GRAPH_ITEM_ID" ] && [[ "$GRAPH_ITEM_ID" =~ ^[0-9]+$ ]] && ! [ -z "$GRAPH_PERIOD" ] && [[ "$GRAPH_PERIOD" =~ ^[0-9]+[mhdwMy]{0,1}$ ]]; then
		if [ "$DEBUG" -eq 1 ]; then
			pushToLog "[DEBUG] - Graphs enabled and graph data exists (graphData: $GRAPH_DATA; itemID: $GRAPH_ITEM_ID; period: $GRAPH_PERIOD; width: $GRAPH_WIDTH; height: $GRAPH_HEIGHT)"
		fi

		zbxApiAuth

		if ! [ -z "$ZABBIX_AUTH_TOKEN" ]; then
			zbxApiGetGraphId

			if ! [ -z "$ZABBIX_GRAPH_ID" ]; then
				prepareCookies
				prepareGraphsDir
				zbxGetGraphImage
			fi
		fi
	else
		pushToLog "[WARNING] - Graph data exists but incorrect (graphData: $GRAPH_DATA)"
	fi
fi

if [ "$GRAPH_ISSET" -eq 1 ]; then
	tlgCutText "$TELEGRAM_CAPTION_LIMIT"
	tlgSendPhoto
else
	tlgCutText "$TELEGRAM_MESSAGE_LIMIT"
	tlgSendMessage
fi

if ! [ -z "$GRAPH_PATH" ] && [ -f "$GRAPH_PATH" ]; then
	rm "$GRAPH_PATH"
fi

exit "$(tlgResult)"
