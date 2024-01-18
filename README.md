# Telegram alertscript for Zabbix [![Version](https://img.shields.io/badge/version-v2.1.1-brightgreen.svg)](https://github.com/zevilz/zabbix-alertscript-telegram/releases/tag/2.1.1)

Script for sending Zabbix alerts via Telegram bot. Sending native Zabbix graphs is supported.

## Requirements

- Telegram bot;
- curl;
- jq;
- [jo](https://github.com/jpmens/jo#install);
- [file](https://github.com/zevilz/zabbix-alertscript-telegram#official-zabbix-docker-images) (for official Zabbix Docker images).

## Installation

- install dependencies;
- put the script into `/usr/lib/zabbix/alertscripts` (set permissions to `700` and owner `zabbix:zabbix`);
- register Telegram bot via [@BotFather](https://t.me/BotFather);
- put bot token into var `TELEGRAM_BOT_TOKEN`;
- create new media type in `Administration` -> `Media types` -> `Create media type`:
	- Name: `Telegram`;
	- Type: `Script`;
	- Script name: `telegram.sh`;
	- Script parameters:
		- `{ALERT.SENDTO}`;
		- `{ALERT.SUBJECT}`;
		- `{ALERT.MESSAGE}`;
- test the script by clicking on the `test` button in the list of media types
- add message templates in media type or directly in trigger actions (you can use [Markdown](https://core.telegram.org/bots/api#markdown-style) in templates).

Now you can choose this media type when setting up users.

The bot must be started if the message is sent as a private message or must be added to a group if the message is to be sent to the group. You can get chat ID via [@zGetMyID_bot](https://t.me/zGetMyID_bot). If you want send messages to specified topic in group with topics add topic ID to chat ID via colon (ex.: `-100123456789:1234`).

Direct access to the script disabled for all users excluding `zabbix` user.

## Vars

- `TELEGRAM_BOT_TOKEN` - Telegram bot token;
- `TELEGRAM_MESSAGE_LIMIT` - maximum length of text that will be truncated (`4000` by default; Telegram API supported `4096` max length);
- `TELEGRAM_CAPTION_LIMIT` - maximum length of caption for graphs that will be truncated (`900` by default; Telegram API supported `1024` max length);
- `GRAPHS` - send graphs (text will send as caption for graphs if enabled; `0` - disabled, `1` enabled; disabled by default);
- `GRAPHS_DIR` - full path to temporary directory for graphs images (zabbix user must be have write permissions to that directory; empty by default; graphs stored in `/tmp/zbx_graphs` if empty value);
- `ZABBIX_URL` - full url to Zabbix web interface (empty by default);
- `ZABBIX_USER` - Zabbix user for get graphs (empty by default);
- `ZABBIX_PASS` - Zabbix user password (empty by default);
- `ZABBIX_COOKIES_LIFETIME` - Zabbix authorization cookies expiration date (cookies are set for a long time, but they may expire faster than specified. specify the required storage period for which the cookies will definitely not have time to expire; `30` by default);
- `ZABBIX_COOKIES_PATH` - full path to cookies file (zabbix user must be have write permissions to that file; empty by default; cookies stored in script directory in `zbx_cookies` file if empty value)
- `MONOSPACED_DESCRIPTION` - add tripple apostrophe in the end of big truncated text/caption (if trigger description as monospaced text and in the end of message template; `0` - disabled, `1` - enabled; disabled by default);
- `SCRIPT_LOG_PATH` - full path to script logs file (zabbix user must be have write permissions to that file; empty by default; logs stored in script directory in `zbx_tlg_bot.log` file if empty value)
- `DEBUG` - write debug messages in logs file (`0` - disabled, `1` enabled; disabled by default; disabled graphs deletion from disk on errors if enabled).

By default long messages will be truncated to 4000 characters (900 for graphs captions). if you will be sending long trigger descriptions in messages as monospaced text (triple apostrophe), set the `MONOSPACED_DESCRIPTION` var to `1`. In this case the script will properly complete truncated text. Example template:

````
Started: {EVENT.TIME} {EVENT.DATE}
Severity: {EVENT.SEVERITY}

Original problem ID: {EVENT.ID}

```
{TRIGGER.DESCRIPTION}```

````

NOTE: You can include a custom config in the script to override script variables. To do this, create a new file in the same directory named `<script_name>.conf` (ex.: `telegram.sh.conf`) and put necessary variables there. This will be useful when updating the script. In new versions of the script, variables will be removed from the script itself and will be defined only in configs.

## Graphs

To send graphs, specified user must have access to graphs of required data elements through the API and through the web interface. This can be a super admin or a user of any user role with required minimum rights. Also you may create super admin with minimal rights (all features are disabled, except for one of interface elements and API feature) and active only `graph.get` API method. This user will can access all graphs of all hosts.

Add folowing string with graph data to messages template if you want attach graphs to messages:

```
<graph:itemid:period:width:height>
```

Where:

- `itemid` (required) - item ID for get graph (usually it native macros `{ITEM.ID1}`, which get first item ID from trigger expression);
- `period` (required) - period for which you need to get a graph relative to the current time (number of secconds or relative period in units: `m` - minutes, `h` - hours, `d` - days, `w` - weeks, `M` - months, `y` - years);
- `width` (optional) - custom graph width (will be used predefined graph width if empty or `0`);
- `height` (optional) - custom graph height (will be used predefined graph height if empty or `0`);

Examples:

```
<graph:{ITEM.ID1}:1800>
<graph:{ITEM.ID1}:1h:900>
<graph:{ITEM.ID1}:2h:900:300>
<graph:{ITEM.ID1}:3h::300>
<graph:{ITEM.ID1}:1w:0:300>
```

Notes: 

- `GRAPHS` var must be set to `1` and `ZABBIX_URL`, `ZABBIX_USER`, `ZABBIX_PASS` vars must be filled correct data for sending graphs;
- regular message will be sent instead of graph with caption if there are errors when receiving a graph data via API and web interface;
- it is unnecessary to delete graph data from messages template if it is necessary to temporarly disable sending graphs (just set `GRAPHS` var to `0`).

## Official Zabbix Docker images

Official Docker images based on Alpine Linux that not provide required `file` utility. You can install it manually:

```
docker exec -it --user=root image-name apk add --no-cache file
```

## TODO
- [ ] add support for basic auth on Zabbix web interface;
- [ ] add custom graph rendering (only get graph data from API with API key)
- [ ] add support for more instances of the script via include custom configs (add script parameter in Zabbix web interface);
- [ ] add support for sending multiple graphs in one message;
- [ ] add graphs blacklist for specified items;
- [ ] add support for redefine item ID from specified trigger;
- [ ] add troubleshooting section in readme.

## Reviews
- [zevilz.dev](https://zevilz.dev/posts/825/) (RU)

## Changelog
- 18.01.2024 - 2.1.1 - Fix for sending alerts with graphs to chat threads
- 12.10.2023 - 2.1.0 - Added support for send alerts to chat topics
- 25.09.2023 - 2.0.5 - Fixed auth if Zabbix installed in subdir
- 11.09.2023 - 2.0.4 - Don't remove graph image if fail getting correct graph with enabled debug mode
- 01.05.2023 - 2.0.3 - Added support for including custom config, disabled graphs deletion on errors if debug mode enabled, bugfixes
- 30.04.2023 - 2.0.2 - Fixed get graphs from Zabbix 6.4
- 05.04.2023 - 2.0.1 - Added support for non GNU Linux distros
- 08.02.2023 - 2.0.0 - [Added support for sending graphs, logging and more](https://github.com/zevilz/zabbix-alertscript-telegram/releases/tag/2.0.0)
- 06.01.2023 - 1.0.0 - released
