# Telegram alertscript for Zabbix

Script for sending Zabbix alerts via Telegram bot

## Requirements

- Telegram bot;
- curl;
- jo.

## Installation

- install curl and [jo](https://github.com/jpmens/jo#install);
- put the script into `/usr/lib/zabbix/alertscripts`;
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
- test the script by clicking on the `test` button in the list of media types.

The bot must be started if the message is sent as a private message or must be added to a group if the message is to be sent to the group. You can get chat ID via [@zGetMyID_bot](https://t.me/zGetMyID_bot).

By default long messages will be cutted to 4000 characters. if you will be sending long trigger descriptions in messages as monospaced text (triple apostrophe), set the `MONOSPACED_DESCRIPTION` var to 1. In this case the script will properly complete the cutted text. Example template:

````
Started: {EVENT.TIME} {EVENT.DATE}
Severity: {EVENT.SEVERITY}

Original problem ID: {EVENT.ID}

```
{TRIGGER.DESCRIPTION}```

````
