script overrides?

Implement first time STEAMCMD downloader
Implement STEAMD_ID downloader
Implement APP_FILES exists check

create wrappers?

steamcmd update
steamcmd update appid
steamcmd test

wine init
wine test

gameserver start (supervisor, like supervisord, s6, runit, tini)
gameserver stop
gameserver update (steamcmd update appid)
gameserver test
gameserver backup

Auto sourced app scripts?

base image
    up.sh
    logging
    steamcmd
    wine
    boxes
