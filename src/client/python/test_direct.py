# -*- coding: utf-8 -*-

from __future__ import print_function
import websocket
import ssl

if __name__ == "__main__":
    # ws = websocket.WebSocket(sslopt={"cert_reqs": ssl.CERT_NONE})
    ws = websocket.WebSocket()
    ws.connect(
        "wss://im.test.pajkdc.com:5291/",
        subprotocols=["xmpp"]
    )
    print("Sending 'test echo'...")
    ws.send("test echo")
    print("Sent")
    print("Reeiving...")
    result = ws.recv()
    print("Received '%s'" % result)
    ws.close()
