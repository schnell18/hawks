def main():
   bot = EchoBot("echobot@tut.jjhome.vn/HelloWorld", "mypass")
   bot.run()


class EchoBot:
    def __init__(self, jid, password) :
        self.xmpp = sleekxmpp.ClientXMPP(jid, password)
        self.xmpp.add_event_handler("session_start", self.handleXMPPConnected)
        self.xmpp.add_event_handler("message", self.handleIncomingMessage)

    def run(self) :
        self.xmpp.connect()
        self.xmpp.process(threaded=False)

    def handleXMPPConnected(self, event):
        self.xmpp.sendPresence(pstatus = "Send me a message")

    def handleIncomingMessage(self, message) :
        self.xmpp.sendMessage(message["jid"], message["message"])
