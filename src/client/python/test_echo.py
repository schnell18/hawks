# -*- coding: utf-8 -*-

from __future__ import print_function
from websocket import create_connection

if __name__ == "__main__":
    ws = create_connection("ws://tut.jjhome.vn/echo/5")
    print("Sending 'test echo'...")
    ws.send("test echo")
    print("Sent")
    print("Reeiving...")
    result = ws.recv()
    print("Received '%s'" % result)
    ws.close()
