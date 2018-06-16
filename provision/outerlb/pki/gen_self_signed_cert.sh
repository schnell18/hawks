#!/bin/sh

openssl req -x509 -newkey rsa:4096 -keyout key.pem -nodes  -out cert.pem -days 365
