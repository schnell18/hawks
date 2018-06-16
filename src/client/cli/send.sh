#!/bin/sh

curl -i -N \
     -H "Connection: Upgrade" \
     -H "Upgrade: websocket" \
     -H "Host: tut.jjhome.vn" \
     -H "Origin: https://www.websocket.org" \
     -H "sec-websocket-key: 34242143424" \
     -H "sec-websocket-version: 13" \
     http://tut.jjhome.vn/echo/5
